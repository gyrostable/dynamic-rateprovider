pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from "oz/access/extensions/AccessControlDefaultAdminRules.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";
import {IGyroECLPPool as IGyroECLPPoolBalV3} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";

contract UpdatableRateProvider is AccessControlDefaultAdminRules, IRateProvider {
    /// @notice Connected chainlink feed.
    AggregatorV3Interface public immutable feed;

    /// @notice Scaling factor to get the chainlink feed value to 18 decimals. This is itself and
    // 18-decimal value.
    uint256 public immutable scalingFactor;

    /// @notice If true, we use 1 / (the chainlink feed value) as the true value. This can be useful
    // for pairs like wstETH/USDC where the wstETH side is already "used up" for the live wstETH/
    // WETH rate and the actual range needs to be captured on the USDC side.
    bool public immutable invert;

    /// @notice Address of the connected pool. Settable once by the owner.
    address public pool;

    /// @notice Whether the pool is a Balancer V3 pool (or otherwise Balancer V2). Settable once by
    // the owner.
    bool public isBalancerV3;

    /// @notice Current value.
    uint256 public value;

    /// @notice Emitted at most once during contract lifetime, when the admin has set the connected pool.
    event PoolSet(address pool, bool isBalancerV3);

    address internal constant ZERO_ADDRESS = address(0x00);

    using FixedPoint for uint256;

    constructor(address _feed, bool _invert, address _admin) AccessControlDefaultAdminRules(1 days, _admin) {
        feed = AggregatorV3Interface(_feed);
        invert = _invert;
        scalingFactor = 10 ** (18 - feed.decimals());

        // NB we can do this *once*, here, while the pool is stil uninitialized.
        // During normal operation, we need to set the value much more carefully to avoid arbitrage
        // loss, and we can't usually set it to the current value.
        value = _getFeedValue();
    }

    function getRate() external view override returns (uint256) {
        return value;
    }

    function setPool(address _pool, bool _isBalancerV3) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_pool != ZERO_ADDRESS, "Cannot set pool to the zero address.");
        require(pool == ZERO_ADDRESS, "Pool already set; can only be set once.");
        pool = _pool;
        isBalancerV3 = _isBalancerV3;
        emit PoolSet(_pool, _isBalancerV3);
    }

    function _getFeedValue() internal view returns (uint256 ret) {
        (, int256 _value,,,) = feed.latestRoundData();
        require(_value > 0, "Invalid feed response");
        ret = uint256(_value) * scalingFactor;
        if (invert) {
            ret = FixedPoint.ONE.divDown(ret);
        }
    }
}
