pragma solidity ^0.8.24;

import {BaseUpdatableRateProvider} from "./BaseUpdatableRateProvider.sol";
import {
    IGyroECLPPool,
    GyroECLPPoolImmutableData
} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";
import {
    IGyro2CLPPool,
    Gyro2CLPPoolImmutableData
} from "balancer-v3-interfaces/pool-gyro/IGyro2CLPPool.sol";
import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {IProtocolFeeController} from "balancer-v3-interfaces/vault/IProtocolFeeController.sol";
import {TokenInfo} from "balancer-v3-interfaces/vault/VaultTypes.sol";
import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";

/// @notice Balancer V3 variant of the updatable rateprovider for volatile asset pairs in Gyroscope
/// ECLPs. Like a `ConstantRateProvider` but can be updated when the pool goes out of range.
contract UpdatableRateProviderBalV3 is BaseUpdatableRateProvider {
    using FixedPoint for uint256;

    /// @notice The Balancer V3 vault to which we are connected. Settable once, in `setPool()`.
    IVault public vault;

    /// @param _feed A RateProvider to use for updates
    /// @param _invert If true, use 1/(value returned by the feed) instead of the feed value itself
    /// @param _admin Address to be set for the `DEFAULT_ADMIN_ROLE`, which can set the pool later
    /// and
    ///     manage permissions
    /// @param _updater Address to be set for the `UPDATER_ROLE`, which can call `.updateToEdge()`.
    ///     Pass the zero address if you don't want to set an updater yet; the admin can manage
    /// roles
    ///     later.
    constructor(address _feed, bool _invert, address _admin, address _updater)
        BaseUpdatableRateProvider(_feed, _invert, _admin, _updater)
    {}

    /// @notice Set the pool that this rateprovider should be connected to. Required before
    /// `.updateToEdge()` is called. Callable at most once and by admin only.
    ///
    /// @param _vault The Balancer V3 vault
    /// @param _pool A Balancer V3 ECLP registered in `_vault`
    function setPool(address _vault, address _pool, PoolType _poolType)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_poolType == PoolType.C3LP) {
            // There is no 3CLP for Balancer V3 yet.
            // We revert here to prevent a potential usage error later.
            revert("Not implemented: UpdatableRateProvider for 3CLP in Bal V3");
        }

        (, TokenInfo[] memory tokenInfo,,) = IVault(_vault).getPoolTokenInfo(_pool);

        uint8 _ourTokenIx = _calcOurTokenIx(_tokenInfo2RateProviderAddresses(tokenInfo));

        // Ensure that there is no fee on yield. This could lead to incorrect accounting during the
        // update. Reverts otherwise.
        // NB tokenInfo is set upon registration of the pool and cannot be changed after, so this is
        // safe to do only once.
        require(
            !tokenInfo[_ourTokenIx].paysYieldFees, "Pool token yield fees configured on our token"
        );

        _setPool(_pool, _poolType, _ourTokenIx);
        vault = IVault(_vault);
    }

    /// @notice If the pool is out of range, update this rateprovider such that the true current
    /// price it is just on the edge of its price range after the update. Reverts if the pool is not
    /// out of range. Callable by the updater role only. Uses the linked `feed` rateprovider to get
    /// the true current price.
    function updateToEdge() external onlyRole(UPDATER_ROLE) {
        require(pool != ZERO_ADDRESS, "Pool not set");

        if (poolType == PoolType.ECLP) {
            GyroECLPPoolImmutableData memory immutableData =
                IGyroECLPPool(pool).getGyroECLPPoolImmutableData();
            _updateToEdge(uint256(immutableData.paramsAlpha), uint256(immutableData.paramsBeta));
        } else if (poolType == PoolType.C2LP) {
            Gyro2CLPPoolImmutableData memory immutableData =
                IGyro2CLPPool(pool).getGyro2CLPPoolImmutableData();
            _updateToEdge(
                immutableData.sqrtAlpha.mulDown(immutableData.sqrtAlpha),
                immutableData.sqrtBeta.mulDown(immutableData.sqrtBeta)
            );
        } else if (poolType == PoolType.C3LP) {
            // Has been caught in `setPool()`.
            assert(false);
        } else {
            assert(false);
        }
    }

    function _tokenInfo2RateProviderAddresses(TokenInfo[] memory tokenInfo)
        internal
        pure
        returns (address[] memory rateProviders)
    {
        rateProviders = new address[](tokenInfo.length);
        for (uint256 i = 0; i < tokenInfo.length; ++i) {
            rateProviders[i] = address(tokenInfo[i].rateProvider);
        }
    }
}
