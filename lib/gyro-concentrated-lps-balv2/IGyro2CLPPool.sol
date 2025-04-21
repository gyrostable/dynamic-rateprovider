
pragma solidity ^0.8;

import {IGyroBasePool} from "./IGyroBasePool.sol";

/// @notice This is an ad-hoc interface for required functions of 2CLPs under Balancer v2.
/// See https://github.com/gyrostable/concentrated-lps/blob/main/contracts/eclp/GyroECLPPool.sol
interface IGyro2CLPPool is IGyroBasePool {
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

    function getActualSupply() external view returns (uint256);

    function getPrice() external view returns (uint256 spotPrice);

    function getSqrtParameters() external view returns (uint256[2] memory);

    function getSwapFeePercentage() external view returns (uint256);

    function getTokenRates() external view returns (uint256 rate0, uint256 rate1);

    function getVirtualParameters() external view returns (uint256[] memory virtualParams);

    function rateProvider0() external view returns (address);

    function rateProvider1() external view returns (address);
}
