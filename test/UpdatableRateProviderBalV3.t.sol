pragma solidity ^0.8.24;

import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {IRouter} from "balancer-v3-interfaces/vault/IRouter.sol";

import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {IAccessControl} from "oz/access/IAccessControl.sol";

import {TesterBase} from "./TesterBase.sol";
import {IGyro2CLPPoolFactory} from "./IGyro2CLPPoolFactoryBalV3.sol";
import {
    IGyro2CLPPool
} from "balancer-v3-interfaces/pool-gyro/IGyro2CLPPool.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";
import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";

import "balancer-v3-interfaces/vault/VaultTypes.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract UpdatableRateProviderBalV3Test is TesterBase {
    UpdatableRateProviderBalV3 updatableRateProvider;

    // See https://github.com/balancer/balancer-deployments/tree/master/v3/tasks/00000000-permit2
    IPermit2 permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // See https://docs.balancer.fi/developer-reference/contracts/deployment-addresses/base.html#pool-factories
    IVault constant vault = IVault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    IGyro2CLPPoolFactory constant c2lpFactory = IGyro2CLPPoolFactory(0xf5CDdF6feD9C589f1Be04899F48f9738531daD59);
    IRouter constant router = IRouter(0x3f170631ed9821Ca51A59D996aB095162438DC10);

    // alpha = 0.5; beta = 1.5.
    uint256 constant c2lpAlpha = 0.5e18;
    uint256 constant c2lpBeta = 1.5e18;
    uint256 constant c2lpSqrtAlpha = 0.707106781186547524e18;
    uint256 constant c2lpSqrtBeta = 1.224744871391589049e18;
    IGyro2CLPPool c2lpPool;

    function setUp() public override {
        TesterBase.setUp();

        updatableRateProvider = new UpdatableRateProviderBalV3(address(feed), false, address(this), updater);

        // Deploy 2CLP with the updatable rate provider for token0.
        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        tokenConfigs[0] = TokenConfig({token: tokens[0], tokenType: TokenType.WITH_RATE, rateProvider: updatableRateProvider, paysYieldFees: false});
        tokenConfigs[1] = TokenConfig({token: tokens[1], tokenType: TokenType.STANDARD, rateProvider: IRateProvider(address(0)), paysYieldFees: false});
        // poolCreator must be address(0) b/c this is a "standard pool" (from a factory I think). O/w we get error `StandardPoolWithCreator()`
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({pauseManager: address(this), swapFeeManager: address(this), poolCreator: address(0)});
        bytes32 salt = "foobar";
        c2lpPool = IGyro2CLPPool(c2lpFactory.create(
            "Test 2CLP",
            "T2CLP",
            tokenConfigs,
            c2lpSqrtAlpha,
            c2lpSqrtBeta,
            roleAccounts,
            // 1% swap fee to make things easy
            0.01e18,
            address(0),
            true,  // enable donation (let's set to true)
            false,  // don't disable unbalanced liquidity (let's not disable)
            salt
        ));

        // Register pool in the updatable rateprovider
        updatableRateProvider.setPool(address(vault), address(c2lpPool), BaseUpdatableRateProvider.PoolType.C2LP);
        
        // TODO set pool creator fees to nonzero.

        // Make the required approvals and initialize the pool.
        for (uint256 i=0; i < N_TOKENS; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(tokens[i]), address(router), type(uint160).max, type(uint48).max);
        }
        IERC20[] memory c2lpTokens = new IERC20[](2);
        c2lpTokens[0] = tokens[0];
        c2lpTokens[1] = tokens[1];
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 100e18;
        amountsIn[1] = 100e18;
        router.initialize(
            address(c2lpPool),
            c2lpTokens,
            amountsIn,
            0,
            false,
            ""
        );

        // TODO validate price. Should be around 1, but not exactly b/c the pool is not symmetric.
    }

    function testRevertIfNotUpdater() public {
        vm.expectRevert(
          abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), updatableRateProvider.UPDATER_ROLE()
          )
        );
        updatableRateProvider.updateToEdge();
    }

    function testRevertIfNotOutOfRange() public {
        // feed value didn't change, is still at 1 = in range.
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        updatableRateProvider.updateToEdge();
    }

    function testRevertIfNotOutOfRange2() public {
        // feed value did change, but is still at 1 = in range.
        feed.setRate(1.1e18);
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        updatableRateProvider.updateToEdge();
    }

    function testUpdateBelow() public {
        feed.setRate(0.4e18);

        // New value = 0.8 = 0.4 / alpha, plus a small rounding error.
        uint256 expectedNewValue = 0.8e18 + 1;

        vm.recordLogs();
        vm.expectEmit(true, false, false, true);
        emit BaseUpdatableRateProvider.ValueUpdated(expectedNewValue, BaseUpdatableRateProvider.OutOfRangeSide.BELOW);
        vm.prank(updater);
        updatableRateProvider.updateToEdge();

        vm.assertEq(updatableRateProvider.getRate(), expectedNewValue);
    }

    function testUpdateAbove() public {
        feed.setRate(1.6e18);

        // 1.6 / 1.5. This won't match exactly.
        uint256 expectedNewValue = 1.066666666666666725e18;

        // We don't check the new value (data) here but match approximately below.
        vm.expectEmit(true, false, false, false);
        emit BaseUpdatableRateProvider.ValueUpdated(expectedNewValue, BaseUpdatableRateProvider.OutOfRangeSide.ABOVE);
        vm.recordLogs();
        vm.prank(updater);
        updatableRateProvider.updateToEdge();

        vm.assertApproxEqAbs(updatableRateProvider.getRate(), expectedNewValue, 100);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 newValue) = abi.decode(logs[0].data, (uint256));
        vm.assertApproxEqAbs(newValue, expectedNewValue, 100);
    }
}
