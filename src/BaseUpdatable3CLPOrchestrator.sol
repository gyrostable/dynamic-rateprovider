// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from
    "oz/access/extensions/AccessControlDefaultAdminRules.sol";

import {SettableRateProvider} from "./SettableRateProvider.sol";

// NB the Bal V2 and V3 interfaces for IRateProvider are the same.
import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";

import {BalancerLPSharePricing} from "gyro-concentrated-lps-balv2/BalancerLPSharePricing.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";
import {LogExpMath} from "balancer-v3/pkg/solidity-utils/contracts/math/LogExpMath.sol";

contract BaseUpdatable3CLPOrchestrator is AccessControlDefaultAdminRules {
    using FixedPoint for uint256;
    using LogExpMath for uint256;

    event PoolSet(address pool);

    enum OutOfRangeMarker {
        IN_RANGE,
        BELOW,
        ABOVE
    }

    event ValuesUpdated(
        uint256 value0,
        OutOfRangeMarker indexed why0,
        uint256 value1,
        OutOfRangeMarker indexed why1,
        uint256 value2,
        OutOfRangeMarker indexed why2
    );

    /// @notice Address of the connected pool. Settable once by the owner.
    address public pool;

    // TODO documentation

    address[3] public feeds;
    SettableRateProvider[3] public childRateProviders;
    uint256 public ixNumeraire;

    /// @notice The role that can call the update function.
    bytes32 public constant UPDATER_ROLE = "UPDATER_ROLE";

    address internal constant ZERO_ADDRESS = address(0);

    constructor(address[3] memory _feeds, uint256 _ixNumeraire, address _admin, address _updater)
        AccessControlDefaultAdminRules(1 days, _admin)
    {
        if (_updater != ZERO_ADDRESS) {
            _grantRole(UPDATER_ROLE, _updater);
        }

        feeds = _feeds;

        require(0 <= _ixNumeraire && _ixNumeraire <= 2, "Invalid _ixNumeraire");
        ixNumeraire = _ixNumeraire;

        for (uint256 i = 0; i < 3; ++i) {
            if (i == _ixNumeraire) {
                childRateProviders[i] = SettableRateProvider(ZERO_ADDRESS);
            } else {
                childRateProviders[i] =
                    new SettableRateProvider(_getRateProviderRate(IRateProvider(_feeds[i])));
            }
        }
    }

    function _setPool(address _pool) internal {
        // address[] memory rateProviders = _getRateProviders(_pool, _poolType);
        require(pool == ZERO_ADDRESS, "Pool already set");
        pool = _pool;
        emit PoolSet(_pool);
    }

    function _getRateProviderRate(IRateProvider rp) internal view returns (uint256) {
        if (address(rp) == ZERO_ADDRESS) {
            return FixedPoint.ONE;
        }
        return rp.getRate();
    }

    function _updateToEdge(uint256 alpha) internal {
        uint256[3] memory feedValues = _getFeedValues();
        uint256[3] memory childValues = _getChildValues();

        (uint256 ixX, uint256 ixY) = _calcNonNumeraireIndices(ixNumeraire);

        // NB the child value for ixNumeraire = delta_z is implicitly always equal to 1.
        uint256 pXZdelta =
            feedValues[ixX].divDown(feedValues[ixNumeraire]).divDown(childValues[ixX]);
        uint256 pYZdelta =
            feedValues[ixY].divDown(feedValues[ixNumeraire]).divDown(childValues[ixY]);

        (uint256 PXZdelta, uint256 PYZdelta) =
            BalancerLPSharePricing.relativeEquilibriumPrices3CLP(alpha, pXZdelta, pYZdelta);

        if (PXZdelta == pXZdelta && PYZdelta == pYZdelta) {
            // This is a correct condition for the pool actually being in range.
            // Note that the equilibrium computation algorithm returns (pXZ, pYZ) unchanged in its
            // "else" case, so we can actually test for equality to check that the algorithm didn't
            // detect any out-of-range condtiion.
            revert("Pool not out of range");
        }

        // We store some temporary values to emit the event below.
        uint256[3] memory newChildValues;
        newChildValues[ixNumeraire] = FixedPoint.ONE;
        newChildValues[ixX] = childValues[ixX].mulDown(pXZdelta).divDown(PXZdelta);
        newChildValues[ixY] = childValues[ixY].mulDown(pYZdelta).divDown(PYZdelta);

        childRateProviders[ixX].setRate(newChildValues[ixX]);
        childRateProviders[ixY].setRate(newChildValues[ixY]);

        emit ValuesUpdated(
            newChildValues[0],
            _calcOutOfRangeMarker(childValues[0], newChildValues[0]),
            newChildValues[1],
            _calcOutOfRangeMarker(childValues[1], newChildValues[1]),
            newChildValues[2],
            _calcOutOfRangeMarker(childValues[2], newChildValues[2])
        );
    }

    function _getFeedValues() internal view returns (uint256[3] memory feedValues) {
        for (uint256 i = 0; i < 3; ++i) {
            feedValues[i] = _getRateProviderRate(IRateProvider(feeds[i]));
        }
    }

    function _getChildValues() internal view returns (uint256[3] memory childValues) {
        for (uint256 i = 0; i < 3; ++i) {
            childValues[i] = _getRateProviderRate(childRateProviders[i]);
        }
    }

    // Indices for assets "x" and "y" if we label the numeraire "z".
    function _calcNonNumeraireIndices(uint256 _ixNumeraire)
        internal
        pure
        returns (uint256, uint256)
    {
        return ((_ixNumeraire + 1) % 3, (_ixNumeraire + 2) % 3);
    }

    function _calcOutOfRangeMarker(uint256 oldValue, uint256 newValue)
        internal
        pure
        returns (OutOfRangeMarker)
    {
        if (newValue < oldValue) {
            return OutOfRangeMarker.BELOW;
        } else if (newValue > oldValue) {
            return OutOfRangeMarker.ABOVE;
        } else {
            return OutOfRangeMarker.IN_RANGE;
        }
    }

    function _root3AlphaToAlpha(uint256 root3Alpha) internal pure returns (uint256) {
        return root3Alpha.pow(3 * uint256(LogExpMath.ONE_18));
    }
}
