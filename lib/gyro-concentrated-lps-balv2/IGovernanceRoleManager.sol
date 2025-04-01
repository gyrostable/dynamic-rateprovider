
pragma solidity ^0.8.24;

/// @notice This is an ad-hoc interface for required functions of the GovernanceRoleManager in the
/// Gyro governance system.
/// See https://github.com/gyrostable/governance-l2/pull/5
interface IGovernanceRoleManager {
    /// @notice Proposal action as defined in L1 governance contract
    struct ProposalAction {
        address target;
        bytes data;
        uint256 value;
    }

    /// @notice Executes a list of actions
    /// @param actions The actions to execute
    function executeActions(ProposalAction[] calldata actions) external;
}


