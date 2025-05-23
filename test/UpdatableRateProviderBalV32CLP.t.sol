pragma solidity ^0.8.24;

import {TesterBaseBalV3} from "./TesterBaseBalV3.sol";
import {IGyro2CLPPoolFactory} from "./IGyro2CLPPoolFactoryBalV3.sol";
import {IGyro2CLPPool} from "balancer-v3-interfaces/pool-gyro/IGyro2CLPPool.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";

import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {IProtocolFeeController} from "balancer-v3-interfaces/vault/IProtocolFeeController.sol";

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

        // Set the protocol fee for the new pool to 0. This is required for the update routine
        // (checks and o/w reverts). The factory sets it to 10% by default.
        IVault vault = factory.getVault();
        IProtocolFeeController protocolFeeController = vault.getProtocolFeeController();
        // TODO WIP this is not authorized even though it seems it should, and then this test fails
        // https://docs.balancer.fi/developer-reference/authorizer/base.html
        vm.prank(0x9ff471F9f98F42E5151C7855fD1b5aa906b1AF7e);
        protocolFeeController.setProtocolYieldFeePercentage(address(pool), 0);

        // Register pool in the updatable rateprovider
        updatableRateProvider.setPool(
            address(vault), address(pool), BaseUpdatableRateProvider.PoolType.C2LP
        );

        initializePool(address(pool), 2);
    }
}
