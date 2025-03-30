pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from "oz/access/extensions/AccessControlDefaultAdminRules.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";

import {IGyroECLPPool as IGyroECLPPoolBalV3} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";

contract UpdatableRateProvider is AccessControlDefaultAdminRules, IRateProvider {
    AggregatorV3Interface public immutable feed;
    uint256 public immutable scalingFactor;

    // Settable once by owner. Must be set for the update function to work.
    address public pool;
    bool public isBalancerV3;

    uint256 public value;

    address constant internal ZERO_ADDRESS = address(0x00);

    constructor(address _feed, address _admin) AccessControlDefaultAdminRules(1 days, _admin) {
        feed = AggregatorV3Interface(_feed);
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
    }

    function _getFeedValue() internal view returns (uint256) {
        (, int256 _value,,,) = feed.latestRoundData();
        require(_value > 0, "Invalid feed response");
        return uint256(_value) * scalingFactor;
    }
}
