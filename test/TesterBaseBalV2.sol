pragma solidity ^0.8.24;

import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";
import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

import {TesterBase} from "./TesterBase.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";
import {UpdatableRateProviderBalV2} from "src/UpdatableRateProviderBalV2.sol";

import {IAccessControl} from "oz/access/IAccessControl.sol";

import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";
import {IGyroBasePool} from "gyro-concentrated-lps-balv2/IGyroBasePool.sol";

import {ICappedLiquidity} from "./ICappedLiquidity.sol";
import {ILocallyPausable} from "./ILocallyPausable.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

abstract contract TesterBaseBalV2 is TesterBase {
    using SafeERC20 for IERC20;

    bytes32 internal constant PROTOCOL_SWAP_FEE_PERC_KEY = "PROTOCOL_SWAP_FEE_PERC";

    UpdatableRateProviderBalV2 updatableRateProvider;
    IVault constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IGyroConfigManager constant gyroConfigManager =
        IGyroConfigManager(0x688E49f075bdFAeC61AeEaa97B6E3a37097A0418);
    IGovernanceRoleManager constant governanceRoleManager =
        IGovernanceRoleManager(0x063c6957945a56441032629Da523C475aAc54752);
    IGyroConfig constant gyroConfig = IGyroConfig(0x8A5eB9A5B726583a213c7e4de2403d2DfD42C8a6);

    // MUST be set by derived contracts in setUp().
    IGyroBasePool poolBase;

    function getUpdatableRateProvider()
        internal
        view
        override
        returns (BaseUpdatableRateProvider)
    {
        return updatableRateProvider;
    }

    function setUp() public virtual override {
        TesterBase.setUp();

        // Prank-move governance over to the GyroConfigManager (it isn't yet).
        vm.prank(gyroConfig.governor());
        gyroConfig.changeGovernor(address(gyroConfigManager));
        vm.prank(gyroConfigManager.owner());
        gyroConfigManager.acceptGovernance();

        updatableRateProvider = new UpdatableRateProviderBalV2(
            address(feed),
            false,
            address(this),
            updater,
            address(gyroConfigManager),
            address(governanceRoleManager)
        );

        // Send some tokens to updatableRateProvider.
        // (they only need the tokens in the pool, the third one is unnecessary for 2CLP and ECLP,
        // but doesn't matter)
        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i].transfer(address(updatableRateProvider), 2e18);
        }

        // Approve tokens for pool initialization
        // Make the required approvals and initialize the pool.
        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i].approve(address(vault), type(uint256).max);
        }
    }

    // Give the updatableRateProvider permission to set gyroconfig params on this specific pool.
    // (we don't condition on updating the protocol fee only, but this would also be possible.)
    function setGyroConfigPermissions(address pool) internal {
        IGovernanceRoleManager.ParameterRequirement[] memory parameterRequirements =
            new IGovernanceRoleManager.ParameterRequirement[](1);
        parameterRequirements[0] = IGovernanceRoleManager.ParameterRequirement({
            index: 0,
            value: bytes32(abi.encode(pool))
        });
        vm.startPrank(governanceRoleManager.owner());
        governanceRoleManager.addPermission(
            address(updatableRateProvider),
            address(gyroConfigManager),
            gyroConfigManager.setPoolConfigUint.selector,
            parameterRequirements
        );
        governanceRoleManager.addPermission(
            address(updatableRateProvider),
            address(gyroConfigManager),
            gyroConfigManager.unsetPoolConfig.selector,
            parameterRequirements
        );
        vm.stopPrank();
    }

    function initializePool(bytes32 poolId, uint256 n_tokens) internal {
        IAsset[] memory assets = new IAsset[](n_tokens);
        for (uint256 i = 0; i < n_tokens; ++i) {
            assets[i] = IAsset(address(tokens[i]));
        }
        uint256[] memory maxAmountsIn = new uint256[](n_tokens);
        for (uint256 i = 0; i < n_tokens; ++i) {
            maxAmountsIn[i] = 100e18;
        }
        // NB for some reason I have to pass maxAmountsIn in two distinct places.
        bytes memory userData = abi.encode(WeightedPoolUserData.JoinKind.INIT, maxAmountsIn);
        IVault.JoinPoolRequest memory joinRequest = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });
        vault.joinPool(poolId, address(this), address(this), joinRequest);
    }

    function mkPoolTokens(uint256 n_tokens) internal view returns (IERC20Bal[] memory poolTokens) {
        poolTokens = new IERC20Bal[](n_tokens);
        for (uint256 i = 0; i < n_tokens; ++i) {
            poolTokens[i] = IERC20Bal(address(tokens[i]));
        }
    }

    // We are attached to token0
    function mkRateProviders(uint256 n_tokens)
        internal
        view
        returns (address[] memory rateProviders)
    {
        rateProviders = new address[](n_tokens);
        rateProviders[0] = address(updatableRateProvider);
        for (uint256 i = 1; i < n_tokens; ++i) {
            rateProviders[i] = address(0);
        }
    }

    function mkCapParams() internal pure returns (ICappedLiquidity.CapParams memory) {
        return ICappedLiquidity.CapParams({capEnabled: false, perAddressCap: 0, globalCap: 0});
    }

    function mkPauseParams() internal pure returns (ILocallyPausable.PauseParams memory) {
        return ILocallyPausable.PauseParams({
            pauseWindowDuration: 365 days,
            bufferPeriodDuration: 365 days
        });
    }

    // Additional tests with different protocol fee settings. The default is to have it not set,
    // implying 0 b/c there are no global / per-pool-type fees configured.

    function testUpdateBelowWithProtoFees() public {
        setPoolProtocolFee(address(poolBase), 0.5e18);
        ProtocolFeeSetting memory oldProtoFeeSetting = _getPoolProtocolFeeSetting(address(poolBase));
        // We check getActualSupply() = the supply including pending protocol fees here. If protocol
        // fees accrued and/or were paid, this would go up b/c protocol fees are paid in LP shares.
        uint256 actualSupplyBefore = poolBase.getActualSupply();
        testUpdateBelow();
        vm.assertApproxEqAbs(poolBase.getActualSupply(), actualSupplyBefore, 1);
        assertEq(oldProtoFeeSetting, _getPoolProtocolFeeSetting(address(poolBase)));
    }

    function testUpdateAboveWithProtoFees() public {
        setPoolProtocolFee(address(poolBase), 0.5e18);
        uint256 actualSupplyBefore = poolBase.getActualSupply();
        ProtocolFeeSetting memory oldProtoFeeSetting = _getPoolProtocolFeeSetting(address(poolBase));
        testUpdateAbove();
        vm.assertApproxEqAbs(poolBase.getActualSupply(), actualSupplyBefore, 1);
        assertEq(oldProtoFeeSetting, _getPoolProtocolFeeSetting(address(poolBase)));
    }

    function testUpdateBelowExplicit0ProtoFees() public {
        setPoolProtocolFee(address(poolBase), 0);
        uint256 actualSupplyBefore = poolBase.getActualSupply();
        ProtocolFeeSetting memory oldProtoFeeSetting = _getPoolProtocolFeeSetting(address(poolBase));
        testUpdateBelow();
        vm.assertApproxEqAbs(poolBase.getActualSupply(), actualSupplyBefore, 1);
        assertEq(oldProtoFeeSetting, _getPoolProtocolFeeSetting(address(poolBase)));
    }

    function testUpdateAboveExplicit0ProtoFees() public {
        setPoolProtocolFee(address(poolBase), 0);
        uint256 actualSupplyBefore = poolBase.getActualSupply();
        ProtocolFeeSetting memory oldProtoFeeSetting = _getPoolProtocolFeeSetting(address(poolBase));
        testUpdateAbove();
        vm.assertApproxEqAbs(poolBase.getActualSupply(), actualSupplyBefore, 1);
        assertEq(oldProtoFeeSetting, _getPoolProtocolFeeSetting(address(poolBase)));
    }

    function assertEq(ProtocolFeeSetting memory actual, ProtocolFeeSetting memory expected) pure internal {
        vm.assertEq(actual.isSet, expected.isSet);
        vm.assertEq(actual.value, expected.value);
    }

    // Copied from UpdatableRateProviderBalV2: Protocol fee tools.

    struct ProtocolFeeSetting {
        bool isSet;
        uint256 value; // valid iff isSet.
    }

    // We only check if a protocol fee is configured *explicitly* for the pool. Note that the actual
    // fee follows a default cascade (first per pool, then per pool type, then a global default),
    // but we don't need to consider this here. Therefore, if `res.isSet == false`, this just means
    // that the pool does not have an explicit fee configured, not that there is no protocol fee.
    function _getPoolProtocolFeeSetting(address _pool) internal view returns (ProtocolFeeSetting memory res) {
        bytes32 key = _getPoolKey(_pool, PROTOCOL_SWAP_FEE_PERC_KEY);
        if (gyroConfig.hasKey(key)) {
            res.isSet = true;
            res.value = gyroConfig.getUint(key);
        } else {
            res.isSet = false;
        }
    }

    // See:
    // https://github.com/gyrostable/concentrated-lps/blob/main/libraries/GyroConfigHelpers.sol
    function _getPoolKey(address pool, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, pool));
    }

    function _setPoolProtocolFeeSetting(address _pool, ProtocolFeeSetting memory feeSetting) internal {
        IGovernanceRoleManager.ProposalAction[] memory actions =
            new IGovernanceRoleManager.ProposalAction[](1);
        actions[0].target = address(gyroConfigManager);
        actions[0].value = 0;
        if (feeSetting.isSet) {
            actions[0].data = abi.encodeWithSelector(
                gyroConfigManager.setPoolConfigUint.selector, _pool, PROTOCOL_SWAP_FEE_PERC_KEY, feeSetting.value
            );
        } else {
            actions[0].data =
                abi.encodeWithSelector(gyroConfigManager.unsetPoolConfig.selector, _pool, PROTOCOL_SWAP_FEE_PERC_KEY);
        }

        governanceRoleManager.executeActions(actions);
    }

    function setPoolProtocolFee(address _pool, uint256 value) internal {
        // We prank the updatableRateProvider b/c we've just set it up such that it has permissions.
        vm.prank(address(updatableRateProvider));
        _setPoolProtocolFeeSetting(_pool, ProtocolFeeSetting(true, value));
    }
}
