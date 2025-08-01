pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20Mintable} from "./ERC20Mintable.sol";
import {ConstRateProvider} from "./ConstRateProvider.sol";

import {Updatable3CLPOrchestratorBalV2} from "src/Updatable3CLPOrchestratorBalV2.sol";
import {BaseUpdatable3CLPOrchestrator} from "src/BaseUpdatable3CLPOrchestrator.sol";

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
import "forge-std/Vm.sol";

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

    // Make this very small so that rebalancing works well enough. Lol.
    uint256 constant internal swap_fee_percentage = 1e12;

    // Some aliases b/c I cannot possibly type this out each time.
    BaseUpdatable3CLPOrchestrator.OutOfRangeMarker constant OORM_IN_RANGE = BaseUpdatable3CLPOrchestrator.OutOfRangeMarker.IN_RANGE;
    BaseUpdatable3CLPOrchestrator.OutOfRangeMarker constant OORM_BELOW = BaseUpdatable3CLPOrchestrator.OutOfRangeMarker.BELOW;
    BaseUpdatable3CLPOrchestrator.OutOfRangeMarker constant OORM_ABOVE = BaseUpdatable3CLPOrchestrator.OutOfRangeMarker.ABOVE;

    bytes32 constant VALUES_UPDATED_SELECTOR = keccak256("ValuesUpdated(uint256,uint8,uint256,uint8,uint256,uint8)");

    function setUp() public virtual {
        vm.createSelectFork(BASE_RPC_URL, 33291652);

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
            [uint256(0),0,0],
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
                    swap_fee_percentage,
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

    function testPreUpdatePrices() view public {
        (uint256 PXZ, uint256 PYZ) = pool.getPrices();
        vm.assertEqDecimal(PXZ, 1e18, 18);
        vm.assertEqDecimal(PYZ, 1e18, 18);
    }

    function testUpdateAbove1() public {
        _testUpdate(
            [uint256(1.6e18), 1e18],
            [int256(-99.9999999999999005e18), 54.6391184140321116e18, 54.6391184140321116e18],
            1.3386560425e18, OORM_ABOVE, 1e18, OORM_IN_RANGE, 1e18, OORM_IN_RANGE
        );
    }

    function testUpdateAbove2() public {
        _testUpdate(
            [uint256(1.6e18), 1.9e18],
            [int256(-100e18), -100e18, 239.4682168647321987e18],
            1.12e18, OORM_ABOVE, 1.33e18, OORM_ABOVE, 1e18, OORM_IN_RANGE
        );
    }

    function testUpdateAbove3() public {
        _testUpdate(
            [uint256(0.88e18), 1.65e18],
            [int256(117.1267966090805430e18), -99.9999999999999005e18, -3.9795197061340701e18],
            1e18, OORM_IN_RANGE, 1.4716062653e18, OORM_ABOVE, 1e18, OORM_IN_RANGE
        );
    }

    function testUpdateBelow1() public {
        _testUpdate(
            [uint256(0.16e18), 1.65e18],
            [int256(239.4682168647321987e18), -100.0000000000000000e18, -100.0000000000000000e18],
            0.2285714286e18, OORM_BELOW, 1.6500000000e18, OORM_ABOVE, 1e18, OORM_IN_RANGE 
        );
    }

    function testUpdateBelow2() public {
        _testUpdate(
            [uint256(0.16e18), 0.33e18],
            [int256(239.4682168647321987e18), -100.0000000000000000e18, -100.0000000000000000e18],
            0.2285714286e18, OORM_BELOW, 0.3300000000e18, OORM_BELOW, 1e18, OORM_IN_RANGE 
        );
    }

    function testUpdateBelow3() public {
        _testUpdate(
            [uint256(0.33e18), 0.40e18],
            [int256(150.2247077808560505e18), -32.1808046338926914e18, -100.0000000000000000e18],
            0.4342481187e18, OORM_BELOW, 0.4342481187e18, OORM_BELOW, 1e18, OORM_IN_RANGE
        );
    }

    // deltas: if negative, this is bought from the pool; if positive, sold to the pool.
    // We support many-to-many swaps here.
    function _performTrade(int256[3] memory deltas) internal {
        // Figure out how many assets we're trading against each other and in which direction.
        
        // No dynamic resizing in memory!
        uint8[3] memory ixsIn;
        uint8[3] memory ixsOut;
        uint8 nIxsIn;
        uint8 nIxsOut;
        for (uint8 i = 0; i < 3; ++i) {
            if (deltas[i] > 0) {
                ixsIn[nIxsIn] = i;
                ++nIxsIn;
            } else if (deltas[i] < 0) {
                ixsOut[nIxsOut] = i;
                ++nIxsOut;
            }
        }

        if (nIxsIn == 0 && nIxsOut == 0) {
            return;
        }
        assert(nIxsIn > 0 && nIxsOut > 0);

        // Now do it.
        // We exploit that we have at most 3 trading assets, so one of them always must be absorbing all the volume in one of the two directions. Nice, lol.

        if (nIxsOut == 1) {
            uint8 ixOut = ixsOut[0];
            for (uint8 ii = 0; ii < nIxsIn; ++ii) {
                uint8 ixIn = ixsIn[ii];
                // uint256 amount = uint256(deltas[ixIn]).divDown(1e18 - swap_fee_percentage);
                uint256 amount = uint256(deltas[ixIn]);
                console.log("swap GIVEN_IN", amount);
                console.log("ixIn", ixIn);
                console.log("ixOut", ixOut);
                _performSingleSwap(ixIn, ixOut, amount, IVault.SwapKind.GIVEN_IN);
            }
        } else if (nIxsIn == 1) {
            uint8 ixIn = ixsIn[0];
            for (uint8 ii = 0; ii < nIxsOut; ++ii) {
                uint8 ixOut = ixsOut[ii];
                console.log("swap GIVEN_OUT", -deltas[ixOut]);
                console.log("ixIn", ixIn);
                console.log("ixOut", ixOut);
                _performSingleSwap(ixIn, ixOut, uint256(-deltas[ixOut]), IVault.SwapKind.GIVEN_OUT);
            }
        } else {
            assert(false);  // accounting broken
        }
    }

    function _performSingleSwap(uint8 tokenInIx, uint8 tokenOutIx, uint256 amount, IVault.SwapKind kind) internal {
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: pool.getPoolId(),
            kind: kind,
            assetIn: IAsset(address(tokens[tokenInIx])),
            assetOut: IAsset(address(tokens[tokenOutIx])),
            amount: amount,
            userData: bytes("")
        });
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        uint256 limit = kind == IVault.SwapKind.GIVEN_IN ? 0 : type(uint256).max;
        vault.swap(
            singleSwap,
            funds,
            limit,
            type(uint256).max
        );
    }

    function _assertArbFreeAndEfficient() view internal {
        _assertArbFreeAndEfficient(true);
    }

    function _assertArbFree() view internal {
        _assertArbFreeAndEfficient(false);
    }

    // Assert that the pool is (1) arbitrage-free and (2) in range after its update.
    function _assertArbFreeAndEfficient(bool checkEfficient) view internal {
        uint256 pXZdelta = feeds[0].getRate().divDown(_getRateProviderRate(feeds[2])).divDown(orchestrator.childRateProviders(0).getRate());
        uint256 pYZdelta = feeds[1].getRate().divDown(_getRateProviderRate(feeds[2])).divDown(orchestrator.childRateProviders(1).getRate());

        // Check against theory equilibrium. This checks that the pool is in range (i.e., efficiency).
        // NB the equilibrium computation may still yield "out of range" by a very slight margin
        // b/c of rounding errors (when computing products / quotients to scale by, for example,
        // or alpha vs root3Alpha^3). That is fine; what matters is that prices are very closely
        // aligned so there's no realistic arbitrage opportunity.
        (uint256 PXZdelta, uint256 PYZdelta) = BalancerLPSharePricing.relativeEquilibriumPrices3CLP(alpha, pXZdelta, pYZdelta);
        if (checkEfficient) {
            // Comparing up to 1e-14 scaled.
            vm.assertApproxEqAbsDecimal(pXZdelta, PXZdelta, 1e4, 18);
            vm.assertApproxEqAbsDecimal(pYZdelta, PYZdelta, 1e4, 18);
        }

        // Check against actual pool prices. This checks that the pool is in range (i.e.,
        // efficiency) and also that it's arbitrage-free.
        (uint256 PXZactual, uint256 PYZactual) = pool.getPrices();
        console.log("PXZactual", PXZactual);
        console.log("PYZactual", PYZactual);
        uint256 PXZactualdelta = PXZactual.divDown(orchestrator.childRateProviders(0).getRate());
        uint256 PYZactualdelta = PYZactual.divDown(orchestrator.childRateProviders(1).getRate());
        if (checkEfficient) {
            // NB 1e12 = 1e-6 is at most the minimum swap fee, so doesn't introduce an arbitrage opportunity.
            vm.assertApproxEqAbsDecimal(PXZactualdelta, pXZdelta, 1e12, 18);
            vm.assertApproxEqAbsDecimal(PYZactualdelta, pYZdelta, 1e12, 18);
        }

        // Also check the actual pool prices against equilibrium prices.
        // This *only* checks for arbitrage-freeness but not efficiency.

        // We give ourselves some leeway here b/c our arbitrage swap calculations and other things
        // may be a bit error bound. These are up to 1e-6, which is smaller than the minimum swap
        // fee, so still fine.
        vm.assertApproxEqAbsDecimal(PXZactualdelta, PXZdelta, 1e12, 18);
        vm.assertApproxEqAbsDecimal(PYZactualdelta, PYZdelta, 1e12, 18);
    }

    function _testUpdate(
        uint256[2] memory feedValues,
        int256[3] memory arbTrade,
        uint256 expectedValue0,
        Updatable3CLPOrchestratorBalV2.OutOfRangeMarker expectedWhy0,
        uint256 expectedValue1,
        Updatable3CLPOrchestratorBalV2.OutOfRangeMarker expectedWhy1,
        uint256 expectedValue2,
        Updatable3CLPOrchestratorBalV2.OutOfRangeMarker expectedWhy2
    ) internal {
        feeds[0].setRate(feedValues[0]);
        feeds[1].setRate(feedValues[1]);

        // This was computed separately and makes the pool arbitrage-free (but not efficient)
        // I haven't simulated fees so I don't know the right values all that precisely.
        _performTrade(arbTrade);
        _assertArbFree();

        vm.recordLogs();
        
        vm.prank(updater);
        orchestrator.updateToEdge();

        _assertArbFreeAndEfficient();

        _checkValueUpdatedEvent(expectedValue0, expectedWhy0, expectedValue1, expectedWhy1, expectedValue2, expectedWhy2);
        // NB only using 1e8 here b/c that's the precision and this check is more of a spot check anyways. The important one is `_assertInEquilibrium()`.
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(0).getRate(), expectedValue0, 1e8, 18);
        vm.assertApproxEqAbsDecimal(orchestrator.childRateProviders(1).getRate(), expectedValue1, 1e8, 18);
    }

    function _checkValueUpdatedEvent(
        uint256 value0,
        Updatable3CLPOrchestratorBalV2.OutOfRangeMarker why0,
        uint256 value1,
        Updatable3CLPOrchestratorBalV2.OutOfRangeMarker why1,
        uint256 value2,
        Updatable3CLPOrchestratorBalV2.OutOfRangeMarker why2
    ) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == VALUES_UPDATED_SELECTOR) {
                (uint256 actualValue0, uint256 actualValue1, uint256 actualValue2) = abi.decode(logs[i].data, (uint256, uint256, uint256));
                BaseUpdatable3CLPOrchestrator.OutOfRangeMarker actualWhy0 = BaseUpdatable3CLPOrchestrator.OutOfRangeMarker(uint8(uint256(logs[i].topics[1])));
                BaseUpdatable3CLPOrchestrator.OutOfRangeMarker actualWhy1 = BaseUpdatable3CLPOrchestrator.OutOfRangeMarker(uint8(uint256(logs[i].topics[2])));
                BaseUpdatable3CLPOrchestrator.OutOfRangeMarker actualWhy2 = BaseUpdatable3CLPOrchestrator.OutOfRangeMarker(uint8(uint256(logs[i].topics[3])));

                vm.assertEq(uint8(why0), uint8(actualWhy0));
                vm.assertApproxEqAbsDecimal(value0, actualValue0, 1e8, 18);
                vm.assertEq(uint8(why1), uint8(actualWhy1));
                vm.assertApproxEqAbsDecimal(value1, actualValue1, 1e8, 18);
                vm.assertEq(uint8(why2), uint8(actualWhy2));
                vm.assertApproxEqAbsDecimal(value2, actualValue2, 1e8, 18);

                return;
            }
        }
        revert("Bug in this test: ValuesUpdated event not found");
    }

    function _debugPrintBalances() view internal {
        (, uint256[] memory amounts,) = vault.getPoolTokens(pool.getPoolId());
        for (uint256 i=0; i < amounts.length; ++i) {
            console.log("pool balance", i, amounts[i]);
        }
    }

    function _getRateProviderRate(IRateProvider rp) view internal returns (uint256) {
        if (address(rp) == address(0)) {
            return 1e18;
        }
        return rp.getRate();
    }

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
        _debugPrintBalances();
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


