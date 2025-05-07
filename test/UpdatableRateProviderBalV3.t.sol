pragma solidity ^0.8.24;

import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {IRouter} from "balancer-v3-interfaces/vault/IRouter.sol";

import {TesterBase} from "./TesterBase.sol";
import {IGyro2CLPPoolFactory} from "./IGyro2CLPPoolFactoryBalV3.sol";
import {
    IGyro2CLPPool
} from "balancer-v3-interfaces/pool-gyro/IGyro2CLPPool.sol";

import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";

import "balancer-v3-interfaces/vault/VaultTypes.sol";

contract UpdatableRateProviderBalV3Test is TesterBase {
    UpdatableRateProviderBalV3 updatableRateProvider;

    // See https://github.com/balancer/balancer-deployments/tree/master/v3/tasks/00000000-permit2
    IPermit2 permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // See https://docs.balancer.fi/developer-reference/contracts/deployment-addresses/base.html#pool-factories
    IVault constant vault = IVault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    IGyro2CLPPoolFactory constant c2lpFactory = IGyro2CLPPoolFactory(0xf5CDdF6feD9C589f1Be04899F48f9738531daD59);
    IRouter constant router = IRouter(0x3f170631ed9821Ca51A59D996aB095162438DC10);

    // alpha = 0.5; beta = 1.5.
    uint256 constant c2lpSqrtAlpha = 0.707106781186547524e18;
    uint256 constant c2lpSqrtBeta = 1.224744871391589049e18;
    IGyro2CLPPool c2lpPool;

    function setUp() public override {
        TesterBase.setUp();

        updatableRateProvider = new UpdatableRateProviderBalV3(address(feed), false, address(this), updater);

        // Deploy 2CLP with the updatable rate provider for token0.
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({token: token0, tokenType: TokenType.WITH_RATE, rateProvider: updatableRateProvider, paysYieldFees: false});
        tokens[1] = TokenConfig({token: token1, tokenType: TokenType.STANDARD, rateProvider: IRateProvider(address(0)), paysYieldFees: false});
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({pauseManager: address(this), swapFeeManager: address(this), poolCreator: address(this)});
        bytes32 salt = "foobar";
        c2lpPool = IGyro2CLPPool(c2lpFactory.create(
            "Test 2CLP",
            "T2CLP",
            tokens,
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

        // TODO set pool creator fees to nonzero.

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = 100e18;
        maxAmountsIn[1] = 100e18;
        vault.addLiquidity(AddLiquidityParams({
            pool: address(c2lpPool),
            to: address(this),
            maxAmountsIn: maxAmountsIn,
            minBptAmountOut: 0,
            // TODO this working for initialize?
            kind: AddLiquidityKind.PROPORTIONAL,
            userData: ""
        }));
    }
}
