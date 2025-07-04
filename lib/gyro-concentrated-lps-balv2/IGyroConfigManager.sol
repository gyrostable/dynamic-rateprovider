
pragma solidity ^0.8.24;

import {IGyroConfig} from "./IGyroConfig.sol";

/// @notice Ad-hoc interface for some functions from GyroConfigManager we need
/// See https://github.com/gyrostable/governance-l2/pull/5
interface IGyroConfigManager {
    function config() external view returns (IGyroConfig);

    function setPoolConfigUint(address pool, bytes32 key, uint256 value) external;

    function unsetPoolConfig(address pool, bytes32 key) external;

    function owner() external view returns (address);

    // GyroConfigManager fallback-delegates to GyroConfig. We add this function from GyroConfig b/c
    // we need it in tests.
    function acceptGovernance() external;
}

