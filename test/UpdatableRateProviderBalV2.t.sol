pragma solidity ^0.8.24;

import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";
import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

import {TesterBase} from "./TesterBase.sol";
import {IGyro2CLPPool} from "gyro-concentrated-lps-balv2/IGyro2CLPPool.sol";
import {IGyro2CLPPoolFactory, ICappedLiquidity, ILocallyPausable} from "./IGyro2CLPPoolFactoryBalV2.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";
// TODO fix file name lol. Also letter case for the V3 version.
import {UpdatableRateProviderBalV2} from "src/UpdatablaRateProviderBalV2.sol";

import {IAccessControl} from "oz/access/IAccessControl.sol";

import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";

contract UpdatableRateProviderBalV2Test is TesterBase {
    using SafeERC20 for IERC20;

    UpdatableRateProviderBalV2 updatableRateProvider;
    IVault constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    
    IGyro2CLPPoolFactory constant c2lpFactory =
        IGyro2CLPPoolFactory(0x46E89B8426C0281816E3477bA0Bf674C3D58D92c);
    IGyroConfig gyroConfig;

    // alpha = 0.5; beta = 1.5.
    uint256 constant c2lpAlpha = 0.5e18;
    uint256 constant c2lpBeta = 1.5e18;
    uint256 constant c2lpSqrtAlpha = 0.707106781186547524e18;
    uint256 constant c2lpSqrtBeta = 1.224744871391589049e18;
    IGyro2CLPPool c2lpPool;

    IGyroConfigManager constant gyroConfigManager = IGyroConfigManager(0x688E49f075bdFAeC61AeEaa97B6E3a37097A0418);
    IGovernanceRoleManager constant governanceRoleManager = IGovernanceRoleManager(0x063c6957945a56441032629Da523C475aAc54752);

    function getUpdatableRateProvider() internal override view returns (BaseUpdatableRateProvider) {
        return updatableRateProvider;
    }

    function setUp() public override {
        TesterBase.setUp();

        // Prank-move governance over to the GyroConfigManager (it isn't yet).
        gyroConfig = IGyroConfig(c2lpFactory.gyroConfigAddress());

        vm.prank(gyroConfig.governor());
        gyroConfig.changeGovernor(address(gyroConfigManager));
        vm.prank(gyroConfigManager.owner());
        // TODO WIP this seems to do nothing. The config manager is still pendingGovernor but not governor after this.
        gyroConfigManager.acceptGovernance();

        updatableRateProvider =
            new UpdatableRateProviderBalV2(address(feed), false, address(this), updater, address(gyroConfigManager), address(governanceRoleManager));

        // Deploy pool
        IERC20Bal[] memory poolTokens = new IERC20Bal[](2);
        poolTokens[0] = IERC20Bal(address(tokens[0]));
        poolTokens[1] = IERC20Bal(address(tokens[1]));

        uint256[] memory sqrts = new uint256[](2);
        sqrts[0] = c2lpSqrtAlpha;
        sqrts[1] = c2lpSqrtBeta;

        address[] memory rateProviders = new address[](2);
        rateProviders[0] = address(updatableRateProvider);
        rateProviders[1] = address(0);

        ICappedLiquidity.CapParams memory capParams = ICappedLiquidity.CapParams({
            capEnabled: false,
            perAddressCap: 0,
            globalCap: 0
        });
        ILocallyPausable.PauseParams memory pauseParams = ILocallyPausable.PauseParams({
            pauseWindowDuration: 365 days,
            bufferPeriodDuration: 365 days
        });

        c2lpPool = IGyro2CLPPool(c2lpFactory.create(
            "Test 2CLP",
            "T2CLP",
            poolTokens,
            sqrts,
            rateProviders,
            // 1% swap fee
            0.01e18,
            address(this),  // owner
            address(this),  // cap manager
            capParams,
            address(this),  // pause manager
            pauseParams
        ));

        // Give the updatableRateProvider permission to set gyroconfig params on this specific pool.
        // (we don't condition on updating the protocol fee only, but this would also be possible.)
        IGovernanceRoleManager.ParameterRequirement[] memory parameterRequirements = new IGovernanceRoleManager.ParameterRequirement[](1);
        parameterRequirements[0] = IGovernanceRoleManager.ParameterRequirement({
            index: 0,
            value: bytes32(abi.encode(address(c2lpPool)))
        });
        vm.startPrank(governanceRoleManager.owner());
        governanceRoleManager.addPermission(address(updatableRateProvider), address(gyroConfigManager), gyroConfigManager.setPoolConfigUint.selector, parameterRequirements);
        governanceRoleManager.addPermission(address(updatableRateProvider), address(gyroConfigManager), gyroConfigManager.unsetPoolConfig.selector, parameterRequirements);
        vm.stopPrank();

        // Register pool in the updatable rateprovider
        updatableRateProvider.setPool(
            address(c2lpPool), BaseUpdatableRateProvider.PoolType.C2LP
        );

        // Send some tokens to updatableRateProvider.
        for (uint256 i=0; i < 2; ++i) {
            poolTokens[i].transfer(address(updatableRateProvider), 2e18);
        }

        // Make the required approvals and initialize the pool.
        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i].approve(address(vault), type(uint256).max);
        }

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokens[0]));
        assets[1] = IAsset(address(tokens[1]));
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = 100e18;
        maxAmountsIn[1] = 100e18;
        // NB for some reason I have to pass maxAmountsIn in two distinct places.
        bytes memory userData = abi.encode(WeightedPoolUserData.JoinKind.INIT, maxAmountsIn);
        IVault.JoinPoolRequest memory joinRequest = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });
        vault.joinPool(
            c2lpPool.getPoolId(),
            address(this),
            address(this),
            joinRequest
        );

        // TODO set protocol fees to nonzero. Use the contract for this, o/w painful.
        // Maybe this should be a separate test.

        // TODO validate price. Should be around 1, but not exactly b/c the pool is not symmetric.
    }
}
