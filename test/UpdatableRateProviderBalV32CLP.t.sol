pragma solidity ^0.8.24;

import {TesterBaseBalV3} from "./TesterBaseBalV3.sol";
import {IGyro2CLPPoolFactory} from "./IGyro2CLPPoolFactoryBalV3.sol";
import {IGyro2CLPPool} from "balancer-v3-interfaces/pool-gyro/IGyro2CLPPool.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";

import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";

import "balancer-v3-interfaces/vault/VaultTypes.sol";
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

        // UNUSED since the UpdatableRateProviderBalV3 also checks the token config.
        // Set the protocol fee for the new pool to 0. This is required for the update routine
        // (checks and o/w reverts). The factory sets it to 10% by default.
        // IVault vault = factory.getVault();
        // IProtocolFeeController protocolFeeController = vault.getProtocolFeeController();
        // TODO WIP this is not authorized even though it seems it should, and then this test fails
        // https://docs.balancer.fi/developer-reference/authorizer/base.html
        // vm.prank(0x35fFB749B273bEb20F40f35EdeB805012C539864);
        // protocolFeeController.setProtocolYieldFeePercentage(address(pool), 0);

        // Register pool in the updatable rateprovider
        updatableRateProvider.setPool(
            address(vault), address(pool), BaseUpdatableRateProvider.PoolType.C2LP
        );

        initializePool(address(pool), 2);
    }

    // Independent of the pool type.
    function testCannotSetPoolTwice() public {
        vm.expectRevert("Pool already set");
        updatableRateProvider.setPool(
            address(vault), address(pool), BaseUpdatableRateProvider.PoolType.C2LP
        );
    }

    // Test that updateToEdge() reverts when a yield fee is configured on the pool. This
    // is independent of the pool type. Note that (at the forked block at least) the
    // ProtocolFeeController takes a default 10% yield fee, so if we don't disable it in the token
    // info, there is actually a yield fee.
    function testRevertOnYieldFees() public {
        // We need to redeploy a new updatableRateProvider here.
        updatableRateProvider =
            new UpdatableRateProviderBalV3(address(feed), false, address(this), updater);

        TokenConfig[] memory tokenConfigs = mkTokenConfigs(2);
        tokenConfigs[0].paysYieldFees = true;

        // We need a different salt here! O/w create2 fails (due to conflict I guess).
        bytes32 salt = "foobar123";
        pool = IGyro2CLPPool(
            factory.create(
                "Test 2CLP",
                "T2CLP",
                tokenConfigs,
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

        vm.prank(updater);
        vm.expectRevert("Pool has protocol yield fee");
        updatableRateProvider.updateToEdge();
    }
}
