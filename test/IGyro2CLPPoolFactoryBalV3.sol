pragma solidity ^0.8.24;

import "balancer-v3-interfaces/vault/VaultTypes.sol";
import "balancer-v3-interfaces/vault/IVault.sol";

/// @notice Ad-hoc interface for the 2CLP factory in balancer v3
interface IGyro2CLPPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 sqrtAlpha,
        uint256 sqrtBeta,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        address poolHooksContract,
        bool enableDonation,
        bool disableUnbalancedLiquidity,
        bytes32 salt
    ) external returns (address pool);

    function getVault() view external returns (IVault);
}
