
pragma solidity ^0.8.24;

import {IGyroConfig} from "./IGyroConfig.sol";

/// @notice Ad-hoc interface for some functions from GyroConfigManager we need
/// See https://github.com/gyrostable/governance-l2/pull/5
interface IGyroConfigManager {
    function config() external returns (IGyroConfig);

    function setPoolConfigUint(address pool, bytes32 key, uint256 value) external;

    function unsetPoolConfig(address pool, bytes32 key) external;
}

