// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";
import {ILPTCurveOracleV1} from "lib/ILPTCurveOracleV1/ILPTCurveOracleV1.sol";

/// @notice A rateprovider adaptor for Infinifi locked iUSD versions
contract LiusdRateProvider is IRateProvider {
    /// @notice The numerator rate provider
    ILPTCurveOracleV1 public immutable lpt;
    uint32 public immutable lockWeeks;

    /// @param _lpt address of Infinifi oracle
    /// @param _lockWeeks must be supported by the oracle
    constructor(address _lpt, uint32 _lockWeeks) {
        lpt = ILPTCurveOracleV1(_lpt);
        lockWeeks = _lockWeeks;
    }

    function getRate() public view override returns (uint256) {
        return lpt.getExchangeRate(lockWeeks);
    }
}
