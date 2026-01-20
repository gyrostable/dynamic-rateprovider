// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library CoreControlled {
    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }
}

interface ILPTCurveOracleV1 {
    error EnforcedPause();
    error ExpectedPause();
    error UnderlyingCallReverted(bytes returnData);

    event CoreUpdate(address indexed oldCore, address indexed newCore);
    event Paused(address account);
    event SetReferences(uint256 timestamp, address lockingController, address accounting);
    event Unpaused(address account);

    function accounting() external view returns (address);
    function core() external view returns (address);
    function emergencyAction(CoreControlled.Call[] memory calls) external payable returns (bytes[] memory returnData);
    function exchangeRateStaked() external view returns (uint256);
    function exchangeRate_1() external view returns (uint256);
    function exchangeRate_13() external view returns (uint256);
    function exchangeRate_2() external view returns (uint256);
    function exchangeRate_4() external view returns (uint256);
    function exchangeRate_6() external view returns (uint256);
    function exchangeRate_8() external view returns (uint256);
    function getExchangeRate(uint32 _unwindingEpochs) external view returns (uint256);
    function iusd() external view returns (address);
    function lockingController() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function setCore(address newCore) external;
    function setReferences(address _lockingController, address _accounting) external;
    function siusd() external view returns (address);
    function unpause() external;
}
