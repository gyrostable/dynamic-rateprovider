pragma solidity ^0.8.24;

import {TesterBaseBalV3} from "./TesterBaseBalV3.sol";
import {ConstRateProvider} from "./ConstRateProvider.sol";
import {IGyro2CLPPoolFactory} from "./IGyro2CLPPoolFactoryBalV3.sol";
import {IGyroECLPPoolFactory} from "./IGyroECLPPoolFactoryBalV3.sol";
import {IGyroECLPPool} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";
import {FixedPoint} from "balancer-v3/pkg/solidity-utils/contracts/math/FixedPoint.sol";
import "balancer-v3-interfaces/vault/VaultTypes.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";
import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";
import {BoostedUpdatableRateProviderBalV3} from "src/BoostedUpdatableRateProviderBalV3.sol";

/// @notice Tests for `BoostedUpdatableRateProviderBalV3`. Token0 is the boosted token (e.g.
/// waBasWETH) using the boosted updatable rateprovider; token1 is the paired yield-bearing token
/// (e.g. waBasUSDC) with its own live rateprovider and `paysYieldFees = true`.
abstract contract BoostedTesterBaseBalV3 is TesterBaseBalV3 {
    using FixedPoint for uint256;

    ConstRateProvider yieldRateProvider0;
    ConstRateProvider yieldRateProvider1;

    uint256 constant YIELD_RATE_0 = 1.05e18;
    uint256 constant YIELD_RATE_1 = 1.02e18;

    address pool;

    function createPool(TokenConfig[] memory tokenConfigs, bytes32 salt)
        internal
        virtual
        returns (address);

    function getPoolType() internal pure virtual returns (BaseUpdatableRateProvider.PoolType);

    function setUp() public override {
        TesterBaseBalV3.setUp();

        yieldRateProvider0 = new ConstRateProvider();
        yieldRateProvider0.setRate(YIELD_RATE_0);
        yieldRateProvider1 = new ConstRateProvider();
        yieldRateProvider1.setRate(YIELD_RATE_1);

        updatableRateProvider = newBoosted(address(yieldRateProvider0));

        pool = createPool(mkBoostedTokenConfigs(), "foobar");
        updatableRateProvider.setPool(address(vault), pool, getPoolType());
        initializePool(pool, 2);
    }

    function newBoosted(address _yieldRateProvider) internal returns (UpdatableRateProviderBalV3) {
        return UpdatableRateProviderBalV3(
            address(
                new BoostedUpdatableRateProviderBalV3(
                    address(feed), false, 0, address(this), updater, _yieldRateProvider
                )
            )
        );
    }

    function mkBoostedTokenConfigs() internal view returns (TokenConfig[] memory tokenConfigs) {
        tokenConfigs = new TokenConfig[](2);
        tokenConfigs[0] = TokenConfig({
            token: tokens[0],
            tokenType: TokenType.WITH_RATE,
            rateProvider: updatableRateProvider,
            paysYieldFees: false
        });
        tokenConfigs[1] = TokenConfig({
            token: tokens[1],
            tokenType: TokenType.WITH_RATE,
            rateProvider: yieldRateProvider1,
            paysYieldFees: true
        });
    }

    function boosted() internal view returns (BoostedUpdatableRateProviderBalV3) {
        return BoostedUpdatableRateProviderBalV3(address(updatableRateProvider));
    }

    function testGetRateIncludesYield() public view {
        assertEq(boosted().value(), 1e18);
        assertEq(boosted().getRate(), YIELD_RATE_0);
        assertEq(address(boosted().yieldRateProvider()), address(yieldRateProvider0));
    }

    function testGetRateTracksYield() public {
        yieldRateProvider0.setRate(1.1e18);
        assertEq(boosted().getRate(), uint256(1.1e18));
        assertEq(boosted().value(), 1e18);
    }

    function testGetRateWithoutYieldRateProvider() public {
        UpdatableRateProviderBalV3 plain = newBoosted(address(0));
        assertEq(plain.getRate(), plain.value());
        assertEq(plain.getRate(), 1e18);
    }

    // Yield accrual on either leg must not make the pool "out of range" for the update routine.
    function testRevertIfOnlyYieldChanged() public {
        yieldRateProvider0.setRate(1.5e18);
        yieldRateProvider1.setRate(1.3e18);
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        updatableRateProvider.updateToEdge();
    }

    // The inherited tests compare against `getRate()`, which here includes the yield rate. Check
    // `value` instead, and that `getRate()` composes it with the yield rate.
    function testUpdateBelow() public override {
        _testUpdate(0.4e18, YIELD_RATE_0, YIELD_RATE_1);
    }

    function testUpdateAbove() public override {
        _testUpdate(1.6e18, YIELD_RATE_0, YIELD_RATE_1);
    }

    // The ERC-4626 rates of both legs cancel out in `_updateToEdge()`: the resulting `value` is the
    // same regardless of how much yield has accrued.
    function testUpdateBelowAfterYieldAccrual() public {
        _testUpdate(0.4e18, 1.2e18, 1.1e18);
    }

    function testUpdateAboveAfterYieldAccrual() public {
        _testUpdate(1.6e18, 1.2e18, 1.1e18);
    }

    function _testUpdate(uint256 feedValue, uint256 yieldRate0, uint256 yieldRate1) internal {
        yieldRateProvider0.setRate(yieldRate0);
        yieldRateProvider1.setRate(yieldRate1);
        feed.setRate(feedValue);

        uint256 expectedNewValue = getExpectedNewValueFor(feedValue);
        vm.recordLogs();
        vm.prank(updater);
        updatableRateProvider.updateToEdge();

        vm.assertApproxEqAbs(boosted().value(), expectedNewValue, 100);
        assertEq(boosted().getRate(), boosted().value().mulDown(yieldRate0));
        checkValueUpdatedEventValue(expectedNewValue, 100);
    }

    function testCannotSetPoolTwice() public {
        vm.expectRevert("Pool already set");
        updatableRateProvider.setPool(address(vault), pool, getPoolType());
    }

    function testRevertOnYieldFeesOnOurToken() public {
        updatableRateProvider = newBoosted(address(yieldRateProvider0));

        TokenConfig[] memory tokenConfigs = mkBoostedTokenConfigs();
        tokenConfigs[0].paysYieldFees = true;
        address pool2 = createPool(tokenConfigs, "foobar123");

        vm.expectRevert("Pool token yield fees configured on our token");
        updatableRateProvider.setPool(address(vault), pool2, getPoolType());
    }
}

contract BoostedUpdatableRateProviderBalV3Test2CLP is BoostedTesterBaseBalV3 {
    IGyro2CLPPoolFactory constant factory =
        IGyro2CLPPoolFactory(0xf5CDdF6feD9C589f1Be04899F48f9738531daD59);

    // alpha = 0.5; beta = 1.5.
    uint256 constant sqrtAlpha = 0.707106781186547524e18;
    uint256 constant sqrtBeta = 1.224744871391589049e18;

    function getPoolType() internal pure override returns (BaseUpdatableRateProvider.PoolType) {
        return BaseUpdatableRateProvider.PoolType.C2LP;
    }

    function createPool(TokenConfig[] memory tokenConfigs, bytes32 salt)
        internal
        override
        returns (address)
    {
        return factory.create(
            "Test Boosted 2CLP",
            "TB2CLP",
            tokenConfigs,
            sqrtAlpha,
            sqrtBeta,
            mkRoleAccounts(),
            0.01e18,
            address(0),
            true,
            false,
            salt
        );
    }
}

contract BoostedUpdatableRateProviderBalV3TestECLP is BoostedTesterBaseBalV3 {
    IGyroECLPPoolFactory constant factory =
        IGyroECLPPoolFactory(0x5F6848976C2914403B425F18B589A65772F082E3);

    function getPoolType() internal pure override returns (BaseUpdatableRateProvider.PoolType) {
        return BaseUpdatableRateProvider.PoolType.ECLP;
    }

    function createPool(TokenConfig[] memory tokenConfigs, bytes32 salt)
        internal
        override
        returns (address)
    {
        IGyroECLPPool.EclpParams memory eclpParams = IGyroECLPPool.EclpParams({
            alpha: 500000000000000000,
            beta: 1500000000000000000,
            c: 707106781186547524,
            s: 707106781186547524,
            lambda: 5000000000000000000
        });
        IGyroECLPPool.DerivedEclpParams memory derivedEclpParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2({
                x: -85749292571254418640716258658269584574,
                y: 51449575542752651184429755194961750744
            }),
            tauBeta: IGyroECLPPool.Vector2({
                x: 70710678118654752400000000000000000000, y: 70710678118654752400000000000000000000
            }),
            u: 78229985344954585431664174165955016000,
            v: 61080126830703701722964730015379048042,
            w: 9630551287951050596866397563651144168,
            z: -7519307226299833111833046586924823789,
            dSq: 99999999999999999886624093342106115200
        });

        return factory.create(
            "Test Boosted ECLP",
            "TBECLP",
            tokenConfigs,
            eclpParams,
            derivedEclpParams,
            mkRoleAccounts(),
            0.01e18,
            address(0),
            true,
            false,
            salt
        );
    }
}
