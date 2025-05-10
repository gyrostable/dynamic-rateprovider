pragma solidity ^0.8.24;

import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";
import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

import {TesterBaseBalV2} from "./TesterBaseBalV2.sol";
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

contract UpdatableRateProviderBalV2Test2CLP is TesterBaseBalV2 {
    using SafeERC20 for IERC20;

    IGyro2CLPPoolFactory constant factory =
        IGyro2CLPPoolFactory(0x46E89B8426C0281816E3477bA0Bf674C3D58D92c);

    // alpha = 0.5; beta = 1.5.
    uint256 constant alpha = 0.5e18;
    uint256 constant beta = 1.5e18;
    uint256 constant sqrtAlpha = 0.707106781186547524e18;
    uint256 constant sqrtBeta = 1.224744871391589049e18;
    IGyro2CLPPool pool;

    function setUp() public override {
        TesterBaseBalV2.setUp();

        // Deploy pool
        uint256[] memory sqrts = new uint256[](2);
        sqrts[0] = sqrtAlpha;
        sqrts[1] = sqrtBeta;

        pool = IGyro2CLPPool(factory.create(
            "Test 2CLP",
            "T2CLP",
            mkPoolTokens(2),
            sqrts,
            mkRateProviders(2),
            // 1% swap fee
            0.01e18,
            address(this),  // owner
            address(this),  // cap manager
            mkCapParams(),
            address(this),  // pause manager
            mkPauseParams()
        ));

        setGyroConfigPermissions(address(pool));

        // Register pool in the updatable rateprovider
        updatableRateProvider.setPool(
            address(pool), BaseUpdatableRateProvider.PoolType.C2LP
        );

        initializePool(pool.getPoolId(), 2);

        // TODO set protocol fees to nonzero. Use the contract for this, o/w painful.
        // Maybe this should be a separate test.

        // TODO validate price. Should be around 1, but not exactly b/c the pool is not symmetric.
    }
}
