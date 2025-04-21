
pragma solidity ^0.8;

import {IGyroBasePool} from "./IGyroBasePool.sol";

/// @notice This is an ad-hoc interface for required functions of 3CLPs under Balancer v2.
/// See https://github.com/gyrostable/concentrated-lps/blob/main/contracts/eclp/GyroECLPPool.sol
interface IGyro3CLPPool is IGyroBasePool {
    function calculateCurrentValues(
        uint256 balanceTokenIn,
        uint256 balanceTokenOut,
        bool tokenInIsToken0
    )
        external
        view
        returns (
            uint256 currentInvariant,
            uint256 virtualParamIn,
            uint256 virtualParamOut
        );

    function getPrices() external view returns (uint256 spotPrice0, uint256 spotPrice1);

    function getRoot3Alpha() external view returns (uint256);

    function getTokenRates() external view returns (uint256 rate0, uint256 rate1, uint256 rate2);

    function rateProvider0() external view returns (address);

    function rateProvider1() external view returns (address);

    function rateProvider2() external view returns (address);
}
