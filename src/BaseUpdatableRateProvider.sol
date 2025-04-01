pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from
    "oz/access/extensions/AccessControlDefaultAdminRules.sol";

// NB the Bal V2 and V3 interfaces for IRateProvider are the same.
import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";

import {IVault as IVaultBalV3} from "balancer-v3-interfaces/vault/IVault.sol";

abstract contract BaseUpdatableRateProvider is AccessControlDefaultAdminRules, IRateProvider {
    using FixedPoint for uint256;

    /// @notice The side where the pool price was out of range on `updateToEdge()`. Only for
    /// logging.
    enum OutOfRangeSide {
        BELOW,
        ABOVE
    }

    /// @notice Connected price feed. This is a RateProvider (often a ChainlinkRateProvider or a
    /// transformation of one).
    IRateProvider public immutable feed;

    /// @notice If true, we use 1 / (the feed value) as the true value. This can be useful
    /// for pairs like wstETH/USDC where the wstETH side is already "used up" for the live wstETH/
    /// WETH rate and the actual range needs to be captured on the USDC side.
    bool public immutable invert;

    /// @notice Address of the connected pool. Settable once by the owner.
    address public pool;

    /// @notice True if this rateprovider is attached to token0 of the pool. Otherwise, it's
    /// attached to token1. Settable once, together with `pool`.
    bool public thisIsToken0;

    /// @notice Current value.
    uint256 public value;

    /// @notice The role that can call the update function.
    bytes32 public constant UPDATER_ROLE = "UPDATER_ROLE";

    /// @notice Emitted at most once during contract lifetime, when the admin has set the connected
    /// pool.
    event PoolSet(address pool, bool thisIsToken0);

    /// @notice Emitted whenever the stored value (the rate) is updated.
    event ValueUpdated(uint256 value, OutOfRangeSide why);

    address internal constant ZERO_ADDRESS = address(0);

    constructor(address _feed, bool _invert, address _admin, address _updater)
        AccessControlDefaultAdminRules(1 days, _admin)
    {
        if (_updater != ZERO_ADDRESS) {
            _grantRole(UPDATER_ROLE, _updater);
        }

        feed = IRateProvider(_feed);
        invert = _invert;

        // NB we can do this *once*, here, while the pool is stil uninitialized.
        // During normal operation, we need to set the value much more carefully to avoid arbitrage
        // loss, and we can't usually set it to the current value.
        value = _getFeedValue();
    }

    function getRate() external view override returns (uint256) {
        return value;
    }

    function _setPool(address _pool, bool _thisIsToken0) internal {
        require(pool == ZERO_ADDRESS, "Pool already set");
        pool = _pool;
        thisIsToken0 = _thisIsToken0;
        emit PoolSet(_pool, thisIsToken0);
    }

    function _setValue(uint256 _value, OutOfRangeSide why) internal {
        value = _value;
        emit ValueUpdated(_value, why);
    }

    function _getFeedValue() internal view returns (uint256 ret) {
        ret = feed.getRate();
        if (invert) {
            ret = FixedPoint.ONE.divDown(ret);
        }
    }

    function _updateToEdge(uint256 alpha, uint256 beta) internal {
        uint256 feedValue = _getFeedValue();
        if (thisIsToken0) {
            uint256 valueBelow = feedValue.divDown(alpha);
            uint256 valueAbove = feedValue.divDown(beta);
            if (value > valueBelow) {
                _setValue(valueBelow, OutOfRangeSide.BELOW);
            } else if (value < valueAbove) {
                _setValue(valueAbove, OutOfRangeSide.ABOVE);
            } else {
                // SOMEDAY should we revert here or just do nothing?
                revert("Pool not out of range");
            }
        } else {
            uint256 valueBelow = feedValue.mulDown(alpha);
            uint256 valueAbove = feedValue.mulDown(beta);
            if (value < valueBelow) {
                _setValue(valueBelow, OutOfRangeSide.BELOW);
            } else if (value > valueAbove) {
                _setValue(valueAbove, OutOfRangeSide.ABOVE);
            } else {
                // SOMEDAY should we revert here or just do nothing?
                revert("Pool not out of range");
            }
        }
    }

    /// @notice Calculate the `thisIsToken0` flag given the two rateproviders.
    function _calcThisIsToken0(address rateProvider0, address rateProvider1)
        internal
        view
        returns (bool)
    {
        if (rateProvider0 == address(this)) {
            return true;
        } else if (rateProvider1 == address(this)) {
            return false;
        } else {
            revert("Rateprovider not configured in pool.");
        }
    }
}
