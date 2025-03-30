pragma solidity ^0.8.24;

import {BaseUpdatableRateProvider} from "./BaseUpdatableRateProvider.sol";
import {
    IGyroECLPPool,
    GyroECLPPoolImmutableData
} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";
import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {TokenInfo} from "balancer-v3-interfaces/vault/VaultTypes.sol";

contract UpdatableRateProviderBalV2 is BaseUpdatableRateProvider {
    /// @notice Parameters:
    ///
    /// -  `_feed`: A RateProvider to use for updates
    /// - `_invert`: If true, use 1/(value returned by the feed) instead of the value itself.
    /// - `_admin`: Address to be set for the `DEFAULT_ADMIN_ROLE`, which can set the pool later and
    ///     manage permissions.
    /// - `_updater`: Address to be set for the `UPDATER_ROLE`, which can call `.updateToEdge()`.
    //     Pass the zero address if you don't want to set an updater yet; the admin can manage roles
    //     later.
    constructor(address _feed, bool _invert, address _admin, address _updater)
        BaseUpdatableRateProvider(_feed, _invert, _admin, _updater)
    {}

    /// @notice Set the pool that this rateprovider should be connected to. Required before
    /// `.updateToEdge()` is called. Admin only.
    ///
    /// `_pool` must be a Balancer V3 ECLP registered in `_vault`.
    function setPool(address _vault, address _pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (, TokenInfo[] memory tokenInfo,,) = IVault(_vault).getPoolTokenInfo(_pool);
        require(tokenInfo.length == 2, "Unexpected number of tokens");

        bool _thisIsToken0 =
            _getThisIsToken0(address(tokenInfo[0].rateProvider), address(tokenInfo[1].rateProvider));
        _setPool(_pool, _thisIsToken0);
    }

    /// @notice If the pool is out of range, update this rateprovider such that it is just on the
    /// edge of its price range after the update. Reverts if the pool is not out of range. Updater
    /// only. Uses the linked `feed` rateprovider to get the true price.
    function updateToEdge() external onlyRole(UPDATER_ROLE) {
        require(pool != ZERO_ADDRESS, "Pool not set");

        GyroECLPPoolImmutableData memory immutableData =
            IGyroECLPPool(pool).getGyroECLPPoolImmutableData();

        _updateToEdge(uint256(immutableData.paramsAlpha), uint256(immutableData.paramsBeta));
    }
}
