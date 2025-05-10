pragma solidity ^0.8.24;

import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {IRouter} from "balancer-v3-interfaces/vault/IRouter.sol";

import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {IAccessControl} from "oz/access/IAccessControl.sol";

import {TesterBaseBalV3} from "./TesterBaseBalV3.sol";
import {IGyro2CLPPoolFactory} from "./IGyro2CLPPoolFactoryBalV3.sol";
import {IGyro2CLPPool} from "balancer-v3-interfaces/pool-gyro/IGyro2CLPPool.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";
import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";

import "balancer-v3-interfaces/vault/VaultTypes.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract UpdatableRateProviderBalV3Test2CLP is TesterBaseBalV3 {
    IGyro2CLPPoolFactory constant factory =
        IGyro2CLPPoolFactory(0xf5CDdF6feD9C589f1Be04899F48f9738531daD59);

    // alpha = 0.5; beta = 1.5.
    uint256 constant alpha = 0.5e18;
    uint256 constant beta = 1.5e18;
    uint256 constant sqrtAlpha = 0.707106781186547524e18;
    uint256 constant sqrtBeta = 1.224744871391589049e18;
    IGyro2CLPPool pool;

    function setUp() public override {
        TesterBaseBalV3.setUp();

        // Deploy 2CLP with the updatable rate provider for token0.
        // poolCreator must be address(0) b/c this is a "standard pool" (from a factory I think). O/w
        // we get error `StandardPoolWithCreator()`
        bytes32 salt = "foobar";
        pool = IGyro2CLPPool(
            factory.create(
                "Test 2CLP",
                "T2CLP",
                mkTokenConfigs(2),
                sqrtAlpha,
                sqrtBeta,
                mkRoleAccounts(),
                // 1% swap fee to make things easy
                0.01e18,
                address(0),
                true, // enable donation (let's set to true)
                false, // don't disable unbalanced liquidity (let's not disable)
                salt
            )
        );

        // Register pool in the updatable rateprovider
        updatableRateProvider.setPool(
            address(vault), address(pool), BaseUpdatableRateProvider.PoolType.C2LP
        );

        initializePool(address(pool), 2);

        // TODO validate price. Should be around 1, but not exactly b/c the pool is not symmetric.
    }
}
