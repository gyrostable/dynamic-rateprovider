// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

import {AccessControlDefaultAdminRules} from
    "oz/access/extensions/AccessControlDefaultAdminRules.sol";

import {SettableRateProvider} from "./SettableRateProvider.sol";

import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";

import {IGyro3CLPPool} from "gyro-concentrated-lps-balv2/IGyro3CLPPool.sol";

// NB the Bal V2 and V3 interfaces for IRateProvider are the same.
import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";

import {GyroBalV2PoolHelpers as PH} from "./GyroBalV2PoolHelpers.sol";

import {BalancerLPSharePricing} from "gyro-concentrated-lps-balv2/BalancerLPSharePricing.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";
import {LogExpMath} from "balancer-v3/pkg/solidity-utils/contracts/math/LogExpMath.sol";

pragma solidity ^0.8.24;

contract Updatable3CLPOrchestratorBalV2 is AccessControlDefaultAdminRules {
    using FixedPoint for uint256;
    using LogExpMath for uint256;

    event PoolSet(address pool);

    /// @notice Address of the connected pool. Settable once by the owner.
    address public pool;

    address[3] public feeds;
    SettableRateProvider[3] public childRateProviders;
    uint256 public ixNumeraire;

    /// @notice Connected `GyroConfigManager` used to set the protocol fee to 0 during update.
    IGyroConfigManager public immutable gyroConfigManager;

    /// @notice Connected `GovernanceRoleManager` used to set the protocol fee to 0 during update.
    IGovernanceRoleManager public immutable governanceRoleManager;

    /// @notice The role that can call the update function.
    bytes32 public constant UPDATER_ROLE = "UPDATER_ROLE";

    address internal constant ZERO_ADDRESS = address(0);

    /// @param _feeds The RateProvider's to use for updates. You can pass the zero address for any of these and then the rate is assumed to be 1. This is useful for the numeraire (see the next item).
    /// @param _ixNumeraire The token index (in _feeds) to be used as the numeraire. This token will _not_ have an associated rateprovider created.
    /// @param _admin Address to be set for the `DEFAULT_ADMIN_ROLE`, which can set the pool later and manage permissions
    /// @param _updater Address to be set for the `UPDATER_ROLE`, which can call `.updateToEdge()`. Pass the zero address if you don't want to set an updater yet; the admin can manage roles later.
    /// @param _gyroConfigManager Address of the `GyroConfigManager` that we can use to set swap
    /// fees
    /// @param _governanceRoleManager Address of the `GovernanceRoleManager` that we can use to set
    ///   swap fees.
    constructor(address[3] memory _feeds, uint256 _ixNumeraire, address _admin, address _updater, address _gyroConfigManager, address _governanceRoleManager) AccessControlDefaultAdminRules(1 days, _admin) {
        if (_updater != ZERO_ADDRESS) {
            _grantRole(UPDATER_ROLE, _updater);
        }

        feeds = _feeds;

        require(0 <= _ixNumeraire && _ixNumeraire <= 2, "Invalid _ixNumeraire");
        ixNumeraire = _ixNumeraire;

        gyroConfigManager = IGyroConfigManager(_gyroConfigManager);
        governanceRoleManager = IGovernanceRoleManager(_governanceRoleManager);

        for (uint256 i = 0; i < 3; ++i) {
            if (i == _ixNumeraire) {
                childRateProviders[i] = SettableRateProvider(ZERO_ADDRESS);
            } else {
                childRateProviders[i] = new SettableRateProvider(_getRateProviderRate(IRateProvider(_feeds[i])));
            }
        }
    }

    /// @notice Set the pool that this rateprovider should be connected to. Required before
    /// `.updateToEdge()` is called. Callable at most once and by admin only.
    ///
    /// @param _pool A Balancer V2 ECLP
    function setPool(address _pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // address[] memory rateProviders = _getRateProviders(_pool, _poolType);
        require(pool == ZERO_ADDRESS, "Pool already set");
        pool = _pool;
        emit PoolSet(_pool);
    }

    function _getRateProviderRate(IRateProvider rp) view internal returns (uint256) {
        if (address(rp) == ZERO_ADDRESS) {
            return 1e18;
        }
        return rp.getRate();
    }

    function updateToEdge() external onlyRole(UPDATER_ROLE) {
        require(pool != ZERO_ADDRESS, "Pool not set");

        // For the protocol fee update procedure, see UpdatableRateProviderBalV2.

        // TODO review and then make this
        PH.PoolMetadata memory meta = PH.getPoolMetadata(pool);

        PH.ProtocolFeeSetting memory oldProtocolFees = PH.getPoolProtocolFeeSetting(gyroConfigManager, address(meta.pool));

        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            PH.joinPoolAll(meta);
            PH.setPoolProtocolFeeSetting(gyroConfigManager, governanceRoleManager, address(meta.pool), PH.ProtocolFeeSetting(true, 0));
        }

        uint256 alpha = _getAlpha(IGyro3CLPPool(address(meta.pool)));
        _updateToEdge(alpha);

        if (!(oldProtocolFees.isSet && oldProtocolFees.value == 0)) {
            PH.exitPoolAll(meta);
            PH.setPoolProtocolFeeSetting(gyroConfigManager, governanceRoleManager, address(meta.pool), oldProtocolFees);
        }
    }

    function _getAlpha(IGyro3CLPPool _pool) view internal returns (uint256) {
        uint256 root3Alpha = _pool.getRoot3Alpha();
        return root3Alpha.pow(3 * uint256(LogExpMath.ONE_18));
    }

    // See the writeup for the algorithm and why it makes sense.
    function _updateToEdge(uint256 alpha) internal {
        uint256[3] memory feedValues = _getFeedValues();

        (uint256 ixX, uint256 ixY) = _calcNonNumeraireIndices(ixNumeraire);
        uint256 pXZ = feedValues[ixX].divDown(feedValues[ixNumeraire]);
        uint256 pYZ = feedValues[ixY].divDown(feedValues[ixNumeraire]);

        (uint256 PXZ, uint256 PYZ) = BalancerLPSharePricing.relativeEquilibriumPrices3CLP(alpha, pXZ, pYZ);

        if (PXZ == pXZ && PYZ == pYZ) {
            // This is a correct condition for the pool actually being in range.
            // Note that the equilibrium computation algorithm returns (pXZ, pYZ) unchanged in its
            // "else" case, so we can actually test for equality to check that the algorithm didn't
            // detect any out-of-range condtiion.
            revert("Pool not out of range");
        }

        _scaleChildRateProvider(ixX, pXZ.divDown(PXZ));
        _scaleChildRateProvider(ixY, pYZ.divDown(PYZ));

        // TODO we should emit some kind of event
    }

    function _getFeedValues() view internal returns (uint256[3] memory feedValues) {
        for (uint256 i = 0; i < 3; ++i) {
            feedValues[i] = _getRateProviderRate(IRateProvider(feeds[i]));
        }
    }

    // Indices for assets "x" and "y" if we label the numeraire "z".
    function _calcNonNumeraireIndices(uint256 _ixNumeraire) pure internal returns (uint256, uint256) {
        return ((_ixNumeraire + 1) % 3, (_ixNumeraire + 2) % 3);
    }

    function _scaleChildRateProvider(uint256 ix, uint256 factor) internal {
        SettableRateProvider srp = childRateProviders[ix];
        assert(address(srp) != ZERO_ADDRESS);
        // SOMEDAY add a .mulRate() method to SettableRateProvider.
        srp.setRate(srp.getRate().mulDown(factor));
    }
}
