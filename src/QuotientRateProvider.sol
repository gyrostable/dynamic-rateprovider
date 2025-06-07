// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";

/// @notice A simple rateprovider adapter that always returns the quotient of two other rate
/// providers, `rp1 / rp2`. This computes (something akin to) a quotient price.
contract QuotientRateProvider is IRateProvider {
    using FixedPoint for uint256;

    /// @notice The numerator rate provider
    IRateProvider public immutable rp1;

    /// @notice The denominator rate provider
    IRateProvider public immutable rp2;

    /// @param _rp1 The numerator rate provider
    /// @param _rp2 The denominator rate provider
    constructor(address _rp1, address _rp2) {
        rp1 = IRateProvider(_rp1);
        rp2 = IRateProvider(_rp2);
    }

    function getRate() public view override returns (uint256) {
        return rp1.getRate().divDown(rp2.getRate());
    }
}
