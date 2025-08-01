// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {IGyroBasePool} from "gyro-concentrated-lps-balv2/IGyroBasePool.sol";
import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

// The third incarnation of IERC20!
import {SafeERC20, IERC20 as IERC20OZ} from "oz/token/ERC20/utils/SafeERC20.sol";

import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";
import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";

/// @notice Some helpers for Balancer V2 gyro pools
/// @dev These are copied from UpdatableRateProviderBalV2. SOMEDAY that contract can use this library instead.
library GyroBalV2PoolHelpers {
    using SafeERC20 for IERC20OZ;

    /// @notice Some collected pool metadata we pass around.
    struct PoolMetadata {
        IGyroBasePool pool; // Additionally satisifes another one of the IGyro*Pool interfaces based on which one it is.
        IVault vault;
        bytes32 poolId;
        IERC20Bal[] tokens;
        uint256[] poolBalancesPreJoin;
    }

    /// @notice Internal helper struct to back up and restore protocol fees.
    struct ProtocolFeeSetting {
        bool isSet;
        uint256 value; // valid iff isSet.
    }

    /// @notice Key used by pools to retrieve their swap fees, see:
    /// https://github.com/gyrostable/concentrated-lps/blob/main/libraries/GyroConfigHelpers.sol
    bytes32 internal constant PROTOCOL_SWAP_FEE_PERC_KEY = "PROTOCOL_SWAP_FEE_PERC";

    function getPoolMetadata(address _pool)
        internal
        view
        returns (PoolMetadata memory meta)
    {
        IGyroBasePool pool_ = IGyroBasePool(_pool);
        IVault vault_ = IVault(pool_.getVault());
        bytes32 poolId_ = pool_.getPoolId();

        meta.pool = pool_;
        meta.vault = vault_;
        meta.poolId = poolId_;
        (meta.tokens, meta.poolBalancesPreJoin,) = vault_.getPoolTokens(poolId_);
    }
    // 
    // Join the pool with (potentially) all our assets.
    function joinPoolAll(PoolMetadata memory meta) internal {
        uint256[] memory balances = getBalances(meta.tokens);

        // NB `.getActualSupply()` is like `.totalSupply()` but accounts for the fact that due
        // protocol fees are distributed before the join (so it may be slightly higher than
        // totalSupply).
        uint256 bptAmount =
            calcBptAmountForJoin(balances, meta.poolBalancesPreJoin, meta.pool.getActualSupply());

        makeMaxApprovals(meta);
        joinPoolFor(bptAmount, meta);
    }
    
    // Exit all our LP shares from the pool.
    function exitPoolAll(PoolMetadata memory meta) internal {
        exitPoolFor(meta.pool.balanceOf(address(this)), meta);
    }

    // Get our balances of the pool tokens in their native number of decimals
    function getBalances(IERC20Bal[] memory tokens)
        internal
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = IERC20(address(tokens[i]));
            balances[i] = token.balanceOf(address(this));
        }
    }

    // Calculate BPT amount that we can get by joining, given our balances. Never returns 0.
    function calcBptAmountForJoin(
        uint256[] memory balances,
        uint256[] memory poolBalances,
        uint256 totalSupply
    ) internal pure returns (uint256 shares) {
        shares = type(uint256).max;
        for (uint256 i = 0; i < balances.length; ++i) {
            // Note that decimal/rate scaling factors cancel out and the result is an 18-decimal
            // number
            // (i.e., in the same scale as LP shares).
            if (poolBalances[i] > 0) {
                uint256 assetShares = totalSupply * balances[i] / poolBalances[i];
                if (assetShares < shares) {
                    shares = assetShares;
                }
            }
            // If poolBalances[i] == 0 (a mostly theoretical concern), we don't need to put any of
            // those assets in, so they don't constrain the shares we get out.
        }

        // Just as a conservative safety margin if the pool rounds down slightly more than we do
        // here.
        // It really doesn't matter with which amount we join.
        shares /= 2;

        if (shares == 0) {
            // In this case, someone has to give this contract a bit more assets.
            revert("Not enough assets.");
        }
    }

    // Approve the max amount if no approval has been made yet. Is gonna last a lifetime.
    function makeMaxApprovals(PoolMetadata memory meta) internal {
        // We just make one blanket approval per token.
        for (uint256 i = 0; i < meta.tokens.length; ++i) {
            IERC20OZ token = IERC20OZ(address(meta.tokens[i]));
            if (token.allowance(address(this), address(meta.vault)) == 0) {
                token.forceApprove(address(meta.vault), type(uint256).max);
            }
        }
    }

    // Interacts with Balancer to join the pool with specified amounts.
    function joinPoolFor(uint256 bptAmount, PoolMetadata memory meta) internal {
        // We don't use limits b/c they don't matter here, and amounts are small anyways.
        uint256[] memory maxAmountsIn = new uint256[](meta.tokens.length);
        for (uint256 i = 0; i < meta.tokens.length; ++i) {
            maxAmountsIn[i] = type(uint256).max;
        }

        // All CLPs use the same user data encoding as the weighted pool.
        bytes memory userData =
            abi.encode(WeightedPoolUserData.JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptAmount);

        meta.vault.joinPool(
            meta.poolId,
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: tokens2assets(meta.tokens),
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );
    }

    // Same as _joinPoolFor() but for exiting.
    function exitPoolFor(uint256 bptAmount, PoolMetadata memory meta) internal {
        uint256[] memory minAmountsOut = new uint256[](meta.tokens.length);
        for (uint256 i = 0; i < meta.tokens.length; ++i) {
            minAmountsOut[i] = 0;
        }

        bytes memory userData =
            abi.encode(WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, bptAmount);

        meta.vault.exitPool(
            meta.poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest({
                assets: tokens2assets(meta.tokens),
                minAmountsOut: minAmountsOut,
                userData: userData,
                toInternalBalance: false
            })
        );
    }
    
    // This function does nothing but casting types.
    function tokens2assets(IERC20Bal[] memory tokens)
        internal
        pure
        returns (IAsset[] memory assets)
    {
        assets = new IAsset[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            assets[i] = IAsset(address(tokens[i]));
        }
    }

    // We only check if a protocol fee is configured *explicitly* for the pool. Note that the actual
    // fee follows a default cascade (first per pool, then per pool type, then a global default),
    // but we don't need to consider this here. Therefore, if `res.isSet == false`, this just means
    // that the pool does not have an explicit fee configured, not that there is no protocol fee.
    function getPoolProtocolFeeSetting(IGyroConfigManager gyroConfigManager, address _pool)
        internal
        view
        returns (ProtocolFeeSetting memory res)
    {
        IGyroConfig gyroConfig = gyroConfigManager.config();
        bytes32 key = getPoolKey(_pool, PROTOCOL_SWAP_FEE_PERC_KEY);
        if (gyroConfig.hasKey(key)) {
            res.isSet = true;
            res.value = gyroConfig.getUint(key);
        } else {
            res.isSet = false;
        }
    }
    
    // See:
    // https://github.com/gyrostable/concentrated-lps/blob/main/libraries/GyroConfigHelpers.sol
    function getPoolKey(address pool, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, pool));
    }

    function setPoolProtocolFeeSetting(IGyroConfigManager gyroConfigManager, IGovernanceRoleManager governanceRoleManager, address _pool, ProtocolFeeSetting memory feeSetting)
        internal
    {
        IGovernanceRoleManager.ProposalAction[] memory actions =
            new IGovernanceRoleManager.ProposalAction[](1);
        actions[0].target = address(gyroConfigManager);
        actions[0].value = 0;
        if (feeSetting.isSet) {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.setPoolConfigUint.selector,
                _pool,
                PROTOCOL_SWAP_FEE_PERC_KEY,
                feeSetting.value
            );
        } else {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.unsetPoolConfig.selector, _pool, PROTOCOL_SWAP_FEE_PERC_KEY
            );
        }

        governanceRoleManager.executeActions(actions);
    }
}

