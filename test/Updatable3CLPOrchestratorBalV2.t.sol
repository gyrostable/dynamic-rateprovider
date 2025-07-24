pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20Mintable} from "./ERC20Mintable.sol";
import {ConstRateProvider} from "./ConstRateProvider.sol";

import {Updatable3CLPOrchestratorBalV2} from "src/Updatable3CLPOrchestratorBalV2.sol";

import {IGyroConfigManager} from "gyro-concentrated-lps-balv2/IGyroConfigManager.sol";
import {IGovernanceRoleManager} from "gyro-concentrated-lps-balv2/IGovernanceRoleManager.sol";
import {IGyroConfig} from "gyro-concentrated-lps-balv2/IGyroConfig.sol";
import {IGyroBasePool} from "gyro-concentrated-lps-balv2/IGyroBasePool.sol";

import {IGyro3CLPPool} from "gyro-concentrated-lps-balv2/IGyro3CLPPool.sol";
import {IGyro3CLPPoolFactory} from "./IGyro3CLPPoolFactoryBalV2.sol";

import {ICappedLiquidity} from "./ICappedLiquidity.sol";
import {ILocallyPausable} from "./ILocallyPausable.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IVault, IERC20 as IERC20Bal, IAsset} from "balancer-v2-interfaces/vault/IVault.sol";
import {WeightedPoolUserData} from "balancer-v2-interfaces/pool-weighted/WeightedPoolUserData.sol";

// NB the Bal V2 and V3 interfaces for IRateProvider are the same.
import {IRateProvider} from "balancer-v3-interfaces/solidity-utils/helpers/IRateProvider.sol";

import {IAccessControl} from "oz/access/IAccessControl.sol";

import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";
import {BalancerLPSharePricing} from "gyro-concentrated-lps-balv2/BalancerLPSharePricing.sol";

import "forge-std/console.sol";

contract Updatable3CLPOrchestratorBalV2Test is Test {
    using FixedPoint for uint256;

    string BASE_RPC_URL = vm.envString("BASE_RPC_URL");

    // address admin = makeAddr("admin");
    address updater = makeAddr("updater");

    uint256 constant public N_TOKENS = 3;
    ERC20Mintable[3] tokens;
    
    ConstRateProvider[3] feeds;

    Updatable3CLPOrchestratorBalV2 orchestrator;

    IVault constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IGyroConfigManager constant gyroConfigManager =
        IGyroConfigManager(0xCb5830e6dBaD1430D6902a846F1b37d4Cfe49b31);
    IGovernanceRoleManager constant governanceRoleManager =
        IGovernanceRoleManager(0x0B39C433F591f4faBa2a3E5B2d55ba05DBDEa392);
    IGyroConfig constant gyroConfig = IGyroConfig(0x8A5eB9A5B726583a213c7e4de2403d2DfD42C8a6);

    IGyro3CLPPoolFactory constant factory =
        IGyro3CLPPoolFactory(0xA74D5bB4AbE3cb874536AdcA265f166a059Cfa67);
    
    // The price range is [alpha, 1/alpha]. Different from the other pools.
    uint256 alpha = 0.7e18;
    uint256 root3Alpha = 0.887904001742600689e18;

    IGyro3CLPPool pool;

    function setUp() public virtual {
        vm.createSelectFork(BASE_RPC_URL, 33255559);

        // Tokens and feed
        
        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i] = new ERC20Mintable();
            tokens[i].mint(address(this), 10_000e18);
        }

        // Sort tokens so they can be used as balance pool tokens as-are.
        (address ta0, address ta1, address ta2) =
            sortAddresses(address(tokens[0]), address(tokens[1]), address(tokens[2]));
        tokens[0] = ERC20Mintable(ta0);
        tokens[1] = ERC20Mintable(ta1);
        tokens[2] = ERC20Mintable(ta2);

        // for (uint256 i=0; i < N_TOKENS; ++i) {
        //     feeds[i] = new ConstRateProvider();
        // }
        feeds[0] = new ConstRateProvider();
        feeds[1] = new ConstRateProvider();
        feeds[2] = ConstRateProvider(address(0));

        address[N_TOKENS] memory _feeds;
        for (uint256 i=0; i < N_TOKENS; ++i) {
            _feeds[i] = address(feeds[i]);
        }

        // Orchestrator
        orchestrator = new Updatable3CLPOrchestratorBalV2(
            _feeds,
            2,
            address(this),
            updater,
            address(gyroConfigManager),
            address(governanceRoleManager)
        );

        IERC20Bal[] memory poolTokens = new IERC20Bal[](3);
        for (uint256 i=0; i < N_TOKENS; ++i) {
            poolTokens[i] = IERC20Bal(address(tokens[i]));
        }

        address[] memory poolRateProviders = new address[](3);
        for (uint256 i=0; i < 3; ++i) {
            poolRateProviders[i] = address(orchestrator.childRateProviders(i));
        }

        // Pool
        pool = IGyro3CLPPool(
            factory.create(
                IGyro3CLPPoolFactory.NewPoolConfigParams(
                    "Test 3CLP",
                    "T3CLP",
                    poolTokens,
                    poolRateProviders,
                    0.01e18, // swap fee
                    root3Alpha,
                    address(this), // owner
                    address(this), // cap manager
                    mkCapParams(),
                    address(this), // pause manager
                    mkPauseParams()
                )
            )
        );

        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i].transfer(address(orchestrator), 2e18);
        }

        // Approve tokens for pool initialization
        // Make the required approvals and initialize the pool.
        for (uint256 i = 0; i < N_TOKENS; ++i) {
            tokens[i].approve(address(vault), type(uint256).max);
        }

        setGyroConfigPermissions(address(pool));
        orchestrator.setPool(address(pool));
        initializePool(pool.getPoolId(), 3);
    }

    function testCannotSetPoolTwice() public {
        vm.expectRevert("Pool already set");
        orchestrator.setPool(address(pool));
    }

    function testRevertIfNotUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                orchestrator.UPDATER_ROLE()
            )
        );
        orchestrator.updateToEdge();
    }

    function testRevertIfNotOutOfRange() public {
        // feed value didn't change, is still at 1 = in range.
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        orchestrator.updateToEdge();
    }

    function testRevertIfNotOutOfRange2() public {
        // feed value did change, but is still at 1 = in range.
        feeds[0].setRate(1.1e18);
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        orchestrator.updateToEdge();
    }

    function testGetRate() view public {
        uint256 rate;
        rate = orchestrator.childRateProviders(0).getRate();
        vm.assertEq(rate, 1e18);
        rate = orchestrator.childRateProviders(1).getRate();
        vm.assertEq(rate, 1e18);
        vm.assertEq(address(orchestrator.childRateProviders(2)), address(0));
    }

    function testUpdateAbove1() public {
        uint256 feedValue = 1.6e18;
        feeds[0].setRate(feedValue);

        // TODO these should NOT be 0!
        // WAITING to merge a fix into 3CLP (and upgrade factory).
        // Then re-enable and check and then delete.
        // (uint256 PXZ, uint256 PYZ) = pool.getPrices();
        // console.log(PXZ, PYZ);

        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        // NB only using 1e8 here b/c that's the precision and this check is more of a spot check anyways. The important one is `_assertInEquilibrium()`.
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), 1.3386560425e18, 1e8, 18);
        vm.assertEqDecimal(orchestrator.childRateProviders(1).getRate(), 1e18, 18);
    }

    function testUpdateAbove2() public {
        feeds[0].setRate(1.6e18);
        feeds[1].setRate(1.9e18);

        // TODO these should NOT be 0!
        // WAITING to merge a fix into 3CLP (and upgrade factory).
        // Then re-enable and check and then delete.
        // (uint256 PXZ, uint256 PYZ) = pool.getPrices();
        // console.log(PXZ, PYZ);

        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), 1.12e18, 1e8, 18);
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(1).getRate(), 1.33e18, 1e8, 18);
    }

    function testUpdateAbove3() public {
        feeds[0].setRate(0.88e18);
        feeds[1].setRate(1.65e18);

        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), 1e18, 0, 18);
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(1).getRate(), 1.4716062653e18, 1e8, 18);
    }

    function testUpdateBelow1() public {
        feeds[0].setRate(0.16e18);
        feeds[1].setRate(1.65e18);

        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), 0.2285714286e18, 1e8, 18);
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(1).getRate(), 1.6500000000e18, 1e8, 18);
    }

    function testUpdateBelow2() public {
        feeds[0].setRate(0.16e18);
        feeds[1].setRate(0.33e18);

        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), 0.2285714286e18, 1e8, 18);
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(1).getRate(), 0.3300000000e18, 1e8, 18);
    }

    function testUpdateBelow3() public {
        feeds[0].setRate(0.33e18);
        feeds[1].setRate(0.40e18);

        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), 0.4342481187e18, 1e8, 18);
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(1).getRate(), 0.4342481187e18, 1e8, 18);
    }

    // Assert that the pool is (1) arbitrage-free and (2) in range after its update.
    function _assertArbFreeAndEfficient() view internal {
        uint256 pXZdelta = feeds[0].getRate().divDown(_getRateProviderRate(feeds[2])).divDown(orchestrator.childRateProviders(0).getRate());
        uint256 pYZdelta = feeds[1].getRate().divDown(_getRateProviderRate(feeds[2])).divDown(orchestrator.childRateProviders(1).getRate());

        // Check against theory equilibrium. This checks that the pool is in range (i.e., efficiency).
        // NB the equilibrium computation may still yield "out of range" by a very slight margin b/c of rounding errors (when computing products / quotients to scale by, for example, or alpha vs root3Alpha^3). That is fine; what matters is that prices are very closely aligned so there's no realistic arbitrage opportunity.
        (uint256 PXZdelta, uint256 PYZdelta) = BalancerLPSharePricing.relativeEquilibriumPrices3CLP(alpha, pXZdelta, pYZdelta);
        // Comparing up to 1e-14 scaled.
        vm.assertApproxEqAbsDecimal(pXZdelta, PXZdelta, 1e4, 18);
        vm.assertApproxEqAbsDecimal(pYZdelta, PYZdelta, 1e4, 18);

        // Check against actual prices
        // TODO DISABLED until a fix to the 3CLP (and factory) is merged.
        // Then re-enable.
        // (uint256 PXZ, uint256 PYZ) = pool.getPrices();
        // vm.assertApproxEqAbsDecimal(PXZ, feeds[0].getRate().divDown(_getRateProviderRate(feeds[2])), 1e8, 18);
        // vm.assertApproxEqAbsDecimal(PYZ, feeds[1].getRate().divDown(_getRateProviderRate(feeds[2])), 1e8, 18);
    }

    function _getRateProviderRate(IRateProvider rp) view internal returns (uint256) {
        if (address(rp) == address(0)) {
            return 1e18;
        }
        return rp.getRate();
    }

    // TODO WIP test updates. Use my julia code to compute expected results.

    // Give the updatableRateProvider permission to set gyroconfig params on this specific pool.
    // (we don't condition on updating the protocol fee only, but this would also be possible.)
    function setGyroConfigPermissions(address _pool) internal {
        IGovernanceRoleManager.ParameterRequirement[] memory parameterRequirements =
            new IGovernanceRoleManager.ParameterRequirement[](1);
        parameterRequirements[0] = IGovernanceRoleManager.ParameterRequirement({
            index: 0,
            value: bytes32(abi.encode(_pool))
        });
        vm.startPrank(governanceRoleManager.owner());
        governanceRoleManager.addPermission(
            address(orchestrator),
            address(gyroConfigManager),
            gyroConfigManager.setPoolConfigUint.selector,
            parameterRequirements
        );
        governanceRoleManager.addPermission(
            address(orchestrator),
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

    function mkCapParams() internal pure returns (ICappedLiquidity.CapParams memory) {
        return ICappedLiquidity.CapParams({capEnabled: false, perAddressCap: 0, globalCap: 0});
    }

    function mkPauseParams() internal pure returns (ILocallyPausable.PauseParams memory) {
        return ILocallyPausable.PauseParams({
            pauseWindowDuration: 365 days,
            bufferPeriodDuration: 365 days
        });
    }

    function sortAddresses(address a, address b, address c)
        internal
        pure
        returns (address, address, address)
    {
        address temp;

        if (a > b) {
            temp = a;
            a = b;
            b = temp;
        }
        if (b > c) {
            temp = b;
            b = c;
            c = temp;
        }
        if (a > b) {
            temp = a;
            a = b;
            b = temp;
        }

        return (a, b, c);
    }
}


