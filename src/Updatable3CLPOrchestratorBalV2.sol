// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.
pragma solidity ^0.8.24;

import {BaseUpdatable3CLPOrchestrator} from "./BaseUpdatable3CLPOrchestrator.sol";

import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";

import {IGyro3CLPPool} from "gyro-concentrated-lps-balv2/IGyro3CLPPool.sol";

import {GyroBalV2PoolHelpers as PH} from "./GyroBalV2PoolHelpers.sol";

contract Updatable3CLPOrchestratorBalV2 is BaseUpdatable3CLPOrchestrator {
    /// @notice Connected `GyroConfigManager` used to set the protocol fee to 0 during update.
    IGyroConfigManager public immutable gyroConfigManager;

    /// @notice Connected `GovernanceRoleManager` used to set the protocol fee to 0 during update.
    IGovernanceRoleManager public immutable governanceRoleManager;

    /// @param _feeds The RateProvider's to use for updates. You can pass the zero address for any
    /// of these and then the rate is assumed to be 1. This is useful for the numeraire (see the
    /// next item).
    /// @param _ixNumeraire The token index (in _feeds) to be used as the numeraire. This token will
    /// _not_ have an associated rateprovider created.
    /// @param _admin Address to be set for the `DEFAULT_ADMIN_ROLE`, which can set the pool later
    /// and manage permissions
    /// @param _updater Address to be set for the `UPDATER_ROLE`, which can call `.updateToEdge()`.
    /// Pass the zero address if you don't want to set an updater yet; the admin can manage roles
    /// later.
    /// @param _gyroConfigManager Address of the `GyroConfigManager` that we can use to set swap
    /// fees
    /// @param _governanceRoleManager Address of the `GovernanceRoleManager` that we can use to set
    /// swap fees.
    constructor(
        address[3] memory _feeds,
        uint256 _ixNumeraire,
        address _admin,
        address _updater,
        address _gyroConfigManager,
        address _governanceRoleManager
    ) BaseUpdatable3CLPOrchestrator(_feeds, _ixNumeraire, _admin, _updater) {
        gyroConfigManager = IGyroConfigManager(_gyroConfigManager);
        governanceRoleManager = IGovernanceRoleManager(_governanceRoleManager);
    }

    /// @notice Set the pool that this rateprovider should be connected to. Required before
    /// `.updateToEdge()` is called. Callable at most once and by admin only.
    ///
    /// @param _pool A Balancer V2 ECLP
    function setPool(address _pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPool(_pool);
    }

    function updateToEdge() external onlyRole(UPDATER_ROLE) {
        require(pool != ZERO_ADDRESS, "Pool not set");

        // For the protocol fee update procedure, see UpdatableRateProviderBalV2.

        PH.PoolMetadata memory meta = PH.getPoolMetadata(pool);

        PH.ProtocolFeeSetting memory oldProtocolFees =
            PH.getPoolProtocolFeeSetting(gyroConfigManager, address(meta.pool));

        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            PH.joinPoolAll(meta);
            PH.setPoolProtocolFeeSetting(
                gyroConfigManager,
                governanceRoleManager,
                address(meta.pool),
                PH.ProtocolFeeSetting(true, 0)
            );
        }

        uint256 alpha = _root3AlphaToAlpha(IGyro3CLPPool(address(meta.pool)).getRoot3Alpha());
        _updateToEdge(alpha);

        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            PH.exitPoolAll(meta);
            PH.setPoolProtocolFeeSetting(
                gyroConfigManager, governanceRoleManager, address(meta.pool), oldProtocolFees
            );
        }
    }
}
