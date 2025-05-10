pragma solidity ^0.8.24;

import {TesterBaseBalV2} from "./TesterBaseBalV2.sol";
import {IGyroECLPPool} from "gyro-concentrated-lps-balv2/IGyroECLPPool.sol";
import {IGyroECLPPoolFactory} from "./IGyroECLPPoolFactoryBalV2.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";

contract UpdatableRateProviderBalV2TestECLP is TesterBaseBalV2 {
    IGyroECLPPoolFactory constant factory = IGyroECLPPoolFactory(0x15e86Be6084C6A5a8c17732D398dFbC2Ec574CEC);

    IGyroECLPPool pool;

    function setUp() public override {
        TesterBaseBalV2.setUp();

        // Corresponds to alpha=0.5, beta=1.5, peg=1, lambda=5. Computed separately.
        IGyroECLPPoolFactory.Params memory eclpParams = IGyroECLPPoolFactory.Params({
            alpha: 500000000000000000,
            beta: 1500000000000000000,
            c: 707106781186547524,
            s: 707106781186547524,
            lambda: 5000000000000000000
        });
        IGyroECLPPoolFactory.DerivedParams memory derivedECLPParams = IGyroECLPPoolFactory.DerivedParams({
            tauAlpha: IGyroECLPPoolFactory.Vector2({x:-85749292571254418640716258658269584574, y:51449575542752651184429755194961750744}),
            tauBeta: IGyroECLPPoolFactory.Vector2({x: 70710678118654752400000000000000000000, y: 70710678118654752400000000000000000000}),
            u: 78229985344954585431664174165955016000,
            v: 61080126830703701722964730015379048042,
            w: 9630551287951050596866397563651144168,
            z: -7519307226299833111833046586924823789,
            dSq: 99999999999999999886624093342106115200
        });

        pool = IGyroECLPPool(factory.create(
            "Test ECLP",
            "TECLP",
            mkPoolTokens(2),
            eclpParams,
            derivedECLPParams,
            mkRateProviders(2),
            0.01e18,  // swap fee
            address(this),  // owner
            address(this),  // cap manager
            mkCapParams(),
            address(this),  // pause manager
            mkPauseParams()
        ));

        setGyroConfigPermissions(address(pool));
        updatableRateProvider.setPool(
            address(pool), BaseUpdatableRateProvider.PoolType.ECLP
        );
        initializePool(pool.getPoolId(), 2);
    }
}

