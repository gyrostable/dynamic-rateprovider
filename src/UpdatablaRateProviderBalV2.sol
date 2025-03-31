pragma solidity ^0.8.24;

import {BaseUpdatableRateProvider} from "./BaseUpdatableRateProvider.sol";
import {IGyroECLPPool} from "gyro-concentrated-lps-balv2/IGyroECLPPool.sol";
import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";
import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
// IERC20Bal is a *sigh* pointless interface conversion.
import {IVault, IERC20} from "balancer-v2-interfaces/vault/IVault.sol";
import {IBalancerQueries} from "balancer-v2-interfaces/standalone-utils/IBalancerQueries.sol";
// import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract UpdatableRateProviderBalV2 is BaseUpdatableRateProvider {
    IGyroConfigManager public immutable gyroConfigManager;
    IGovernanceRoleManager public immutable governanceRoleManager;
    IBalancerQueries public immutable balancerQueries;

    bytes32 internal constant PROTOCOL_SWAP_FEE_PERC_KEY = "PROTOCOL_SWAP_FEE_PERC";

    /// @notice Internal helper struct to back up and restore protocol fees.
    struct ProtocolFeeSetting {
        bool isSet;
        uint256 value;  // valid iff isSet.
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
    // - `_governanceRoleManager`: Address of the `GovernanceRoleManager` that we can use to set swap fees.
    constructor(address _feed, bool _invert, address _admin, address _updater, address _gyroConfigManager, address _governanceRoleManager, address _balancerQueries)
        BaseUpdatableRateProvider(_feed, _invert, _admin, _updater)
    {
        gyroConfigManager = IGyroConfigManager(_gyroConfigManager);
        governanceRoleManager = IGovernanceRoleManager(_governanceRoleManager);
        balancerQueries = IBalancerQueries(_balancerQueries);
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

        // Add a small amount of assets to the pool to update `lastInvariant`, which tracks protocol fees.
        _joinPoolAll(pool);
        // TODO ^^ not required when protocol fees are explicit 0 right??
        // TODO join pool

        // Set protocol fees to 0 so they don't get in the way when updating our rate. Store the old
        // value. We also have to store _if_ protocol fees are set for this pool because they follow
        // a default cascade.
        ProtocolFeeSetting memory oldProtocolFees = _getPoolProtocolFee(pool);

        // If they are already set to explicit 0, we do not need to do anything, and we don't. This
        // saves a bit of unnecessary interaction with the governanceRoleManager.
        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            _setPoolProtocolFee(pool, ProtocolFeeSetting(true, 0));
        }

        (IGyroECLPPool.Params memory params,) = IGyroECLPPool(pool).getECLPParams();
        _updateToEdge(uint256(params.alpha), uint256(params.beta));

        // Exit the pool to update `lastInvariant` again.
        _exitPoolAll(pool);

        // Reset the protocol fees.

        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            _setPoolProtocolFee(pool, oldProtocolFees);
        }
    }

    function _joinPoolAll(address _pool) internal {
        IGyroECLPPool pool_ = IGyroECLPPool(_pool);
        
        IVault vault = IVault(pool_.getVault());
        (IERC20[] memory tokens,,) = vault.getPoolTokens(pool_.getPoolId());
        require(tokens.length == 2, "Unexpected number of tokens");

        uint256[] memory balances = _getBalances(tokens);

        // We need some nonzero assets to perform the join.
        require(balances[0] > 0 && balances[1] > 0, "Missing assets");

        // TODO approve all

        // See: https://web.archive.org/web/20241206210129/https://docs.balancer.fi/reference/contracts/query-functions.html#queryjoin
        // Note: We are not supposed to use this to compute limits, but we only use it to compute
        // the BPT (LP shares) amount corresponding to our assets. The limits are always our total
        // (small) assets.
        IBalancerQueries queries = IBalancerQueries(balancerQueries);
        (uint256 bptOut,) = queries.queryJoin(
            pool_.getPoolId(),
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: _tokens2addresses(tokens),
                maxAmountsIn: balances,
                userData: userData,
                fromInternalBalancer: false
            })
        );
    }

    function _exitPoolAll(address _pool) internal {
        // TODO
    }

    function _getBalances(IERC20[] memory tokens) internal view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            balances[i] = tokens[i].balanceOf(address(this));
        }
    }

    // This function does nothing but casting types.
    function _tokens2addresses(IERC20[] memory tokens) internal pure returns (address[] memory addresses) {
        addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            addresses[i] = address(tokens[i]);
        }
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
        IGovernanceRoleManager.ProposalAction[] memory actions = new IGovernanceRoleManager.ProposalAction[](1);
        bytes32 key = _getPoolKey(pool, PROTOCOL_SWAP_FEE_PERC_KEY);

        actions[0].target = address(gyroConfigManager);
        actions[0].value = 0;
        if (feeSetting.isSet) {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.setPoolConfigUint.selector,
                pool,
                key,
                feeSetting.value
            );
        } else {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.unsetPoolConfig.selector,
                pool,
                key
            );
        }

        governanceRoleManager.executeActions(actions);               
    }
}
