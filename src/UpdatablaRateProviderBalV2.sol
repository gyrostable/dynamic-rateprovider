pragma solidity ^0.8.24;

import {BaseUpdatableRateProvider} from "./BaseUpdatableRateProvider.sol";
import {IGyroECLPPool} from "gyro-concentrated-lps-balv2/IGyroECLPPool.sol";
import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";
import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
// *sign* Balancer's version of IERC20 doesn't include `.decimals()`. Foundry's version is actually
// IERC20Metadata.
import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

contract UpdatableRateProviderBalV2 is BaseUpdatableRateProvider {
    IGyroConfigManager public immutable gyroConfigManager;
    IGovernanceRoleManager public immutable governanceRoleManager;

    bytes32 internal constant PROTOCOL_SWAP_FEE_PERC_KEY = "PROTOCOL_SWAP_FEE_PERC";

    /// @notice Internal helper struct to back up and restore protocol fees.
    struct ProtocolFeeSetting {
        bool isSet;
        uint256 value; // valid iff isSet.
    }

    /// @notice Parameters:
    ///
    /// -  `_feed`: A RateProvider to use for updates
    /// - `_invert`: If true, use 1/(value returned by the feed) instead of the value itself.
    /// - `_admin`: Address to be set for the `DEFAULT_ADMIN_ROLE`, which can set the pool later and
    ///     manage permissions.
    /// - `_updater`: Address to be set for the `UPDATER_ROLE`, which can call `.updateToEdge()`.
    //     Pass the zero address if you don't want to set an updater yet; the admin can manage roles
    //     later.
    // - `_gyroConfigManager`: Address of the `GyroConfigManager` that we can use to set swap fees.
    // - `_governanceRoleManager`: Address of the `GovernanceRoleManager` that we can use to set
    //   swap fees.
    constructor(
        address _feed,
        bool _invert,
        address _admin,
        address _updater,
        address _gyroConfigManager,
        address _governanceRoleManager
    ) BaseUpdatableRateProvider(_feed, _invert, _admin, _updater) {
        gyroConfigManager = IGyroConfigManager(_gyroConfigManager);
        governanceRoleManager = IGovernanceRoleManager(_governanceRoleManager);
    }

    /// @notice Set the pool that this rateprovider should be connected to. Required before
    /// `.updateToEdge()` is called. Admin only.
    ///
    /// `_pool` must be a Balancer V2 ECLP.
    function setPool(address _pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IGyroECLPPool pool_ = IGyroECLPPool(_pool);
        bool _thisIsToken0 = _getThisIsToken0(pool_.rateProvider0(), pool_.rateProvider1());
        _setPool(_pool, _thisIsToken0);
    }

    /// @notice If the pool is out of range, update this rateprovider such that it is just on the
    /// edge of its price range after the update. Reverts if the pool is not out of range. Updater
    /// only. Uses the linked `feed` rateprovider to get the true price.
    function updateToEdge() external onlyRole(UPDATER_ROLE) {
        require(pool != ZERO_ADDRESS, "Pool not set");

        // Unless protocol fees are 0, we need to set them to 0 so they don't get in the way when
        // updating our rate. We do a join+exit combo with a small amount around our updating of our
        // rate to update the accounting for protocol fees (`lastInvariant` in the ECLP). Note that
        // order matters here. We store the old value to restore it later. We also have to store
        // _if_ protocol fees are set for this pool because they follow a default cascade.
        ProtocolFeeSetting memory oldProtocolFees = _getPoolProtocolFee(pool);

        // If they are already set to explicit 0, we do not need to do anything, and we don't. This
        // saves a bit of unnecessary interaction.
        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            _joinPoolAll(pool);
            _setPoolProtocolFee(pool, ProtocolFeeSetting(true, 0));
        }

        (IGyroECLPPool.Params memory params,) = IGyroECLPPool(pool).getECLPParams();
        _updateToEdge(uint256(params.alpha), uint256(params.beta));

        // Update protocol fee accounting and reset their config.
        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            _exitPoolAll(pool);
            _setPoolProtocolFee(pool, oldProtocolFees);
        }
    }

    // Join the pool with (potentially) all our assets.
    function _joinPoolAll(address _pool) internal {
        IGyroECLPPool pool_ = IGyroECLPPool(_pool);

        IVault vault = IVault(pool_.getVault());
        bytes32 poolId = pool_.getPoolId();
        (IERC20Bal[] memory tokens, uint256[] memory poolBalances,) = vault.getPoolTokens(poolId);
        require(tokens.length == 2, "Unexpected number of tokens");

        uint256[] memory balances = _getBalances(tokens);
        // We need some nonzero assets to perform the join.
        require(balances[0] > 0 && balances[1] > 0, "Missing assets");
        // NB `.getActualSupply()` is like `.totalSupply()` but accounts for the fact that due
        // protocol fees are distributed before the join (so it may be slightly higher than
        // totalSupply).
        uint256 bptAmount = _calcBptAmount(balances, poolBalances, pool_.getActualSupply());

        _makeApprovals(address(vault), tokens);
        _joinPoolFor(bptAmount, tokens, poolId, vault);
    }

    // Exit all our LP shares from the pool.
    function _exitPoolAll(address _pool) internal {
        // This is partially but not completely analogous to `_joinPoolAll()` b/c we don't need to
        // calculate stuff or make approvals.

        IGyroECLPPool pool_ = IGyroECLPPool(_pool);

        IVault vault = IVault(pool_.getVault());
        bytes32 poolId = pool_.getPoolId();

        (IERC20Bal[] memory tokens,,) = vault.getPoolTokens(poolId);

        _exitPoolFor(pool_.balanceOf(address(this)), tokens, poolId, vault);
    }

    // Get our balances of the pool tokens in their native number of decimals
    function _getBalances(IERC20Bal[] memory tokens)
        internal
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = IERC20(address(tokens[i]));
            balances[i] = token.balanceOf(address(this));
        }
    }

    // This function does nothing but casting types.
    function _tokens2assets(IERC20Bal[] memory tokens)
        internal
        pure
        returns (IAsset[] memory assets)
    {
        assets = new IAsset[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            assets[i] = IAsset(address(tokens[i]));
        }
    }

    function _calcBptAmount(
        uint256[] memory balances,
        uint256[] memory poolBalances,
        uint256 totalSupply
    ) internal pure returns (uint256 shares) {
        // We don't use 18-decimal methods like `FixedPoint.mulDown()` to improve precision with
        // low-decimals tokens like USDC. Note that decimal/rate scaling factors cancel out and the
        // result is an 18-decimal number (i.e., in the same scale as LP shares).
        uint256 shares0 = totalSupply * balances[0] / poolBalances[0];
        uint256 shares1 = totalSupply * balances[1] / poolBalances[1];
        shares = shares0 <= shares1 ? shares0 : shares1;
    }

    function _makeApprovals(address _vault, IERC20Bal[] memory tokens) internal {
        // We just make one blanket approval per token.
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20Bal token = tokens[i];
            if (token.allowance(address(this), _vault) == 0) {
                token.approve(_vault, type(uint256).max);
            }
        }
    }

    // Interacts with Balancer to join the pool with specified amounts.
    function _joinPoolFor(
        uint256 bptAmount,
        IERC20Bal[] memory tokens,
        bytes32 poolId,
        IVault vault
    ) internal {
        // We don't use limits b/c they don't matter here, and amounts are small anyways.
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = type(uint256).max;
        maxAmountsIn[1] = type(uint256).max;

        // The ECLP uses the same user data encoding as the weighted pool.
        bytes memory userData =
            abi.encode(WeightedPoolUserData.JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptAmount);

        vault.joinPool(
            poolId,
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: _tokens2assets(tokens),
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );
    }

    // Same as _joinPoolFor() but for exiting.
    function _exitPoolFor(
        uint256 bptAmount,
        IERC20Bal[] memory tokens,
        bytes32 poolId,
        IVault vault
    ) internal {
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;

        bytes memory userData =
            abi.encode(WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, bptAmount);

        vault.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest({
                assets: _tokens2assets(tokens),
                minAmountsOut: minAmountsOut,
                userData: userData,
                toInternalBalance: false
            })
        );
    }

    function _getPoolProtocolFee(address _pool) internal returns (ProtocolFeeSetting memory res) {
        IGyroConfig gyroConfig = gyroConfigManager.config();
        bytes32 key = _getPoolKey(_pool, PROTOCOL_SWAP_FEE_PERC_KEY);
        if (gyroConfig.hasKey(key)) {
            res.isSet = true;
            res.value = gyroConfig.getUint(key);
        } else {
            res.isSet = false;
        }
    }

    function _getPoolKey(address pool, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, pool));
    }

    function _setPoolProtocolFee(address pool, ProtocolFeeSetting memory feeSetting) internal {
        IGovernanceRoleManager.ProposalAction[] memory actions =
            new IGovernanceRoleManager.ProposalAction[](1);
        bytes32 key = _getPoolKey(pool, PROTOCOL_SWAP_FEE_PERC_KEY);

        actions[0].target = address(gyroConfigManager);
        actions[0].value = 0;
        if (feeSetting.isSet) {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.setPoolConfigUint.selector, pool, key, feeSetting.value
            );
        } else {
            actions[0].data =
                abi.encodeWithSelector(gyroConfigManager.unsetPoolConfig.selector, pool, key);
        }

        governanceRoleManager.executeActions(actions);
    }
}
