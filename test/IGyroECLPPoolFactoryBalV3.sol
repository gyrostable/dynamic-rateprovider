pragma solidity ^0.8.0;

import "balancer-v3-interfaces/vault/VaultTypes.sol";
import {IGyroECLPPool} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";

/// @notice Ad-hoc interface for the ECLP factory in balancer v3
interface IGyroECLPPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedEclpParams,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        address poolHooksContract,
        bool enableDonation,
        bool disableUnbalancedLiquidity,
        bytes32 salt
    ) external returns (address pool);
}

