// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";
import {Ownable} from "oz/access/Ownable.sol";

/// @notice A RateProvider where the rate can be set by its owner.
contract SettableRateProvider is IRateProvider, Ownable {
    event ValueUpdated(uint256 newValue);

    uint256 internal value;

    constructor(uint256 value_) Ownable(msg.sender) {
        value = value_;
    }

    function getRate() external view override returns (uint256) {
        return value;
    }

    function setRate(uint256 value_) external onlyOwner {
        value = value_;
        emit ValueUpdated(value_);
    }
}
