pragma solidity ^0.8.24;

import {IVault} from "balancer-v3-interfaces/vault/IVault.sol";
import {IRouter} from "balancer-v3-interfaces/vault/IRouter.sol";

import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {IAccessControl} from "oz/access/IAccessControl.sol";
import "balancer-v3-interfaces/vault/VaultTypes.sol";

import {TesterBase} from "./TesterBase.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";
import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";

import "forge-std/Vm.sol";

abstract contract TesterBaseBalV3 is TesterBase {
    UpdatableRateProviderBalV3 updatableRateProvider;

    function getUpdatableRateProvider()
        internal
        view
        override
        returns (BaseUpdatableRateProvider)
    {
        return updatableRateProvider;
    }

    // See https://github.com/balancer/balancer-deployments/tree/master/v3/tasks/00000000-permit2
    IPermit2 permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // See
    // https://docs.balancer.fi/developer-reference/contracts/deployment-addresses/base.html#pool-factories
    IVault constant vault = IVault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    IRouter constant router = IRouter(0x3f170631ed9821Ca51A59D996aB095162438DC10);

    function setUp() public virtual override {
        TesterBase.setUp();

        updatableRateProvider =
            new UpdatableRateProviderBalV3(address(feed), false, 0, address(this), updater);

        // Approve the tokens for pool initialization.
        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(
                address(tokens[i]), address(router), type(uint160).max, type(uint48).max
            );
        }
    }

    // Standard initialization procedure for use in setUp()
    function initializePool(address pool, uint256 n_tokens) internal {
        // Initialize pools. Approvals have been made in setUp() already.
        IERC20[] memory poolTokens = new IERC20[](n_tokens);
        poolTokens[0] = tokens[0];
        poolTokens[1] = tokens[1];
        uint256[] memory amountsIn = new uint256[](n_tokens);
        amountsIn[0] = 100e18;
        amountsIn[1] = 100e18;
        router.initialize(pool, poolTokens, amountsIn, 0, false, "");
    }

    // Our rateprovider is the one for token0 here.
    function mkTokenConfigs(uint256 n_tokens)
        internal
        view
        returns (TokenConfig[] memory tokenConfigs)
    {
        tokenConfigs = new TokenConfig[](n_tokens);
        tokenConfigs[0] = TokenConfig({
            token: tokens[0],
            tokenType: TokenType.WITH_RATE,
            rateProvider: updatableRateProvider,
            paysYieldFees: false
        });
        for (uint256 i = 1; i < n_tokens; ++i) {
            tokenConfigs[i] = TokenConfig({
                token: tokens[i],
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                // NB this *must* be false for the update to go through!
                paysYieldFees: false
            });
        }
    }

    function mkRoleAccounts() internal view returns (PoolRoleAccounts memory roleAccounts) {
        return PoolRoleAccounts({
            pauseManager: address(this),
            swapFeeManager: address(this),
            poolCreator: address(0)
        });
    }
}
