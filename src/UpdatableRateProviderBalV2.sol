pragma solidity ^0.8.24;

import {BaseUpdatableRateProvider} from "./BaseUpdatableRateProvider.sol";

import {IGyroBasePool} from "gyro-concentrated-lps-balv2/IGyroBasePool.sol";
import {IGyroECLPPool} from "gyro-concentrated-lps-balv2/IGyroECLPPool.sol";
import {IGyro2CLPPool} from "gyro-concentrated-lps-balv2/IGyro2CLPPool.sol";
import {IGyro3CLPPool} from "gyro-concentrated-lps-balv2/IGyro3CLPPool.sol";

import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";
import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
// *sigh* Balancer's version of IERC20 doesn't include `.decimals()`. Foundry's version is actually
// IERC20Metadata.
import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";
import {LogExpMath} from "balancer-v3/pkg/solidity-utils/contracts/math/LogExpMath.sol";

/// @notice Balancer V2 variant of the updatable rateprovider for volatile asset pairs in Gyroscope
/// ECLPs. Like a `ConstantRateProvider` but can be updated when the pool goes out of range.
contract UpdatableRateProviderBalV2 is BaseUpdatableRateProvider {
    using FixedPoint for uint256;
    using LogExpMath for uint256;

    /// @notice Connected `GyroConfigManager` used to set the protocol fee to 0 during update.
    IGyroConfigManager public immutable gyroConfigManager;

    /// @notice Connected `GovernanceRoleManager` used to set the protocol fee to 0 during update.
    IGovernanceRoleManager public immutable governanceRoleManager;

    /// @notice Key used by pools to retrieve their swap fees, see:
    /// https://github.com/gyrostable/concentrated-lps/blob/main/libraries/GyroConfigHelpers.sol
    bytes32 internal constant PROTOCOL_SWAP_FEE_PERC_KEY = "PROTOCOL_SWAP_FEE_PERC";

    /// @notice Internal helper struct to back up and restore protocol fees.
    struct ProtocolFeeSetting {
        bool isSet;
        uint256 value; // valid iff isSet.
    }

    /// @notice Some collected pool metadata we pass around.
    struct PoolMetadata {
        IGyroBasePool pool; // Additionally satisifes one of the IGyro*Pool interfaces based on
            // `poolType`.
        PoolType poolType;
        IVault vault;
        bytes32 poolId;
        IERC20Bal[] tokens;
        uint256[] poolBalancesPreJoin;
    }

    /// @param _feed A RateProvider to use for updates
    /// @param _invert If true, use 1/(value returned by the feed) instead of the feed value itself.
    /// @param _admin Address to be set for the `DEFAULT_ADMIN_ROLE`, which can set the pool later
    /// and
    ///     manage permissions
    /// @param _updater Address to be set for the `UPDATER_ROLE`, which can call `.updateToEdge()`.
    ///     Pass the zero address if you don't want to set an updater yet; the admin can manage
    /// roles
    ///     later.
    /// @param _gyroConfigManager Address of the `GyroConfigManager` that we can use to set swap
    /// fees
    /// @param _governanceRoleManager Address of the `GovernanceRoleManager` that we can use to set
    ///   swap fees.
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
    /// `.updateToEdge()` is called. Callable at most once and by admin only.
    ///
    /// @param _pool A Balancer V2 ECLP
    function setPool(address _pool, PoolType _poolType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address[] memory rateProviders = _getRateProviders(_pool, _poolType);
        _setPool(_pool, _poolType, _calcOurTokenIx(rateProviders));
    }

    function _getRateProviders(address _pool, PoolType _poolType)
        internal
        view
        returns (address[] memory rateProviders)
    {
        if (_poolType == PoolType.ECLP) {
            IGyroECLPPool pool_ = IGyroECLPPool(_pool);
            rateProviders = new address[](2);
            rateProviders[0] = pool_.rateProvider0();
            rateProviders[1] = pool_.rateProvider1();
        } else if (_poolType == PoolType.C2LP) {
            IGyro2CLPPool pool_ = IGyro2CLPPool(_pool);
            rateProviders = new address[](2);
            rateProviders[0] = pool_.rateProvider0();
            rateProviders[1] = pool_.rateProvider1();
        } else if (_poolType == PoolType.C3LP) {
            IGyro3CLPPool pool_ = IGyro3CLPPool(_pool);
            rateProviders = new address[](3);
            rateProviders[0] = pool_.rateProvider0();
            rateProviders[1] = pool_.rateProvider1();
            rateProviders[2] = pool_.rateProvider2();
        } else {
            assert(false);
        }
    }

    /// @notice If the pool is out of range, update this rateprovider such that the true current
    /// price it is just on the edge of its price range after the update. Reverts if the pool is not
    /// out of range. Callable by the updater role only. Uses the linked `feed` rateprovider to get
    /// the true current price.
    function updateToEdge() external onlyRole(UPDATER_ROLE) {
        require(pool != ZERO_ADDRESS, "Pool not set");

        PoolMetadata memory meta = _getPoolMetadata(pool, poolType);

        // Unless protocol fees are 0, we need to set them to 0 so they don't get in the way when
        // updating our rate. We do a join+exit combo with a small amount around our updating of our
        // rate to update the accounting for protocol fees (`lastInvariant` in the ECLP). Note that
        // order matters here. We store the old value to restore it later. We also have to store
        // _if_ protocol fees are set for this pool because they follow a default cascade.
        ProtocolFeeSetting memory oldProtocolFees = _getPoolProtocolFee(address(meta.pool));

        // If they are already set to explicit 0, we do not need to do anything, and we don't. This
        // saves a bit of unnecessary interaction.
        // TODO what if they're implicit 0? Should also be fine right??
        // (I think I just didn't wanna model the default cascade)
        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            _joinPoolAll(meta);
            _setPoolProtocolFee(address(meta.pool), ProtocolFeeSetting(true, 0));
        }

        (uint256 alpha, uint256 beta) = _getPriceBounds(meta);
        _updateToEdge(alpha, beta);

        // Update protocol fee accounting and reset their config.
        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            _exitPoolAll(meta);
            _setPoolProtocolFee(address(meta.pool), oldProtocolFees);
        }
    }

    function _getPoolMetadata(address _pool, PoolType _poolType)
        internal
        view
        returns (PoolMetadata memory meta)
    {
        IGyroBasePool pool_ = IGyroBasePool(_pool);
        IVault vault_ = IVault(pool_.getVault());
        bytes32 poolId_ = pool_.getPoolId();

        meta.pool = pool_;
        meta.poolType = _poolType;
        meta.vault = vault_;
        meta.poolId = poolId_;
        (meta.tokens, meta.poolBalancesPreJoin,) = vault_.getPoolTokens(poolId_);
    }

    function _getPriceBounds(PoolMetadata memory meta) internal view returns (uint256, uint256) {
        if (meta.poolType == PoolType.ECLP) {
            (IGyroECLPPool.Params memory params,) =
                IGyroECLPPool(address(meta.pool)).getECLPParams();
            return (uint256(params.alpha), uint256(params.beta));
        } else if (meta.poolType == PoolType.C2LP) {
            uint256[2] memory sqrtParams = IGyro2CLPPool(address(meta.pool)).getSqrtParameters();
            return (sqrtParams[0].mulDown(sqrtParams[0]), sqrtParams[1].mulDown(sqrtParams[1]));
        } else if (meta.poolType == PoolType.C3LP) {
            uint256 root3Alpha = IGyro3CLPPool(address(meta.pool)).getRoot3Alpha();
            uint256 alpha = root3Alpha.pow(3 * uint256(LogExpMath.ONE_18));
            // NB the 3CLP is symmetric, i.e., beta = 1 / alpha.
            return (alpha, FixedPoint.ONE.divDown(alpha));
        } else {
            assert(false);
            return (0, 0); // unreachable, to make the compiler happy.
        }
    }

    // Join the pool with (potentially) all our assets.
    function _joinPoolAll(PoolMetadata memory meta) internal {
        uint256[] memory balances = _getBalances(meta.tokens);

        // NB `.getActualSupply()` is like `.totalSupply()` but accounts for the fact that due
        // protocol fees are distributed before the join (so it may be slightly higher than
        // totalSupply).
        uint256 bptAmount =
            _calcBptAmount(balances, meta.poolBalancesPreJoin, meta.pool.getActualSupply());

        _makeApprovals(meta);
        _joinPoolFor(bptAmount, meta);
    }

    // Exit all our LP shares from the pool.
    function _exitPoolAll(PoolMetadata memory meta) internal {
        _exitPoolFor(meta.pool.balanceOf(address(this)), meta);
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

    // Calculate BPT amount that we can get by joining, given our balances. Never returns 0.
    function _calcBptAmount(
        uint256[] memory balances,
        uint256[] memory poolBalances,
        uint256 totalSupply
    ) internal pure returns (uint256 shares) {
        shares = type(uint256).max;
        for (uint256 i = 0; i < balances.length; ++i) {
            // Note that decimal/rate scaling factors cancel out and the result is an 18-decimal
            // number
            // (i.e., in the same scale as LP shares).
            if (poolBalances[i] > 0) {
                uint256 assetShares = totalSupply * balances[i] / poolBalances[i];
                if (assetShares < shares) {
                    shares = assetShares;
                }
            }
            // If poolBalances[i] == 0 (a mostly theoretical concern), we don't need to put any of
            // those assets in, so they don't constrain the shares we get out.
        }

        // Just as a conservative safety margin if the pool rounds down slightly more than we do
        // here.
        // It really doesn't matter with which amount we join.
        shares /= 2;

        if (shares == 0) {
            // In this case, someone has to give this contract a bit more assets.
            revert("Not enough assets.");
        }
    }

    function _makeApprovals(PoolMetadata memory meta) internal {
        // We just make one blanket approval per token.
        for (uint256 i = 0; i < meta.tokens.length; ++i) {
            IERC20Bal token = meta.tokens[i];
            if (token.allowance(address(this), address(meta.vault)) == 0) {
                token.approve(address(meta.vault), type(uint256).max);
            }
        }
    }

    // Interacts with Balancer to join the pool with specified amounts.
    function _joinPoolFor(uint256 bptAmount, PoolMetadata memory meta) internal {
        // We don't use limits b/c they don't matter here, and amounts are small anyways.
        uint256[] memory maxAmountsIn = new uint256[](meta.tokens.length);
        for (uint256 i = 0; i < meta.tokens.length; ++i) {
            maxAmountsIn[i] = type(uint256).max;
        }

        // All CLPs use the same user data encoding as the weighted pool.
        bytes memory userData =
            abi.encode(WeightedPoolUserData.JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptAmount);

        meta.vault.joinPool(
            meta.poolId,
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: _tokens2assets(meta.tokens),
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );
    }

    // Same as _joinPoolFor() but for exiting.
    function _exitPoolFor(uint256 bptAmount, PoolMetadata memory meta) internal {
        uint256[] memory minAmountsOut = new uint256[](meta.tokens.length);
        for (uint256 i = 0; i < meta.tokens.length; ++i) {
            minAmountsOut[i] = 0;
        }

        bytes memory userData =
            abi.encode(WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, bptAmount);

        meta.vault.exitPool(
            meta.poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest({
                assets: _tokens2assets(meta.tokens),
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

    // See:
    // https://github.com/gyrostable/concentrated-lps/blob/main/libraries/GyroConfigHelpers.sol
    function _getPoolKey(address pool, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, pool));
    }

    function _setPoolProtocolFee(address _pool, ProtocolFeeSetting memory feeSetting) internal {
        IGovernanceRoleManager.ProposalAction[] memory actions =
            new IGovernanceRoleManager.ProposalAction[](1);
        bytes32 key = _getPoolKey(_pool, PROTOCOL_SWAP_FEE_PERC_KEY);

        actions[0].target = address(gyroConfigManager);
        actions[0].value = 0;
        if (feeSetting.isSet) {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.setPoolConfigUint.selector, _pool, key, feeSetting.value
            );
        } else {
            actions[0].data =
                abi.encodeWithSelector(gyroConfigManager.unsetPoolConfig.selector, _pool, key);
        }

        governanceRoleManager.executeActions(actions);
    }
}
