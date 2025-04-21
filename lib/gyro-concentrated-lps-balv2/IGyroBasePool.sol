
pragma solidity ^0.8;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Interface shared between all Gyro CLPs
interface IGyroBasePool is IERC20 {
    function getVault() external view returns (address);
    function getPoolId() external view returns (bytes32);
    function gyroConfig() external view returns (address);

    function getActualSupply() external view returns (uint256);
    function getInvariant() external view returns (uint256);

    function getInvariantDivActualSupply() external view returns (uint256);

    function getLastInvariant() external view returns (uint256);

    function getSwapFeePercentage() external view returns (uint256);
}
