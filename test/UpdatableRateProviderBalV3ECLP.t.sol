pragma solidity ^0.8.24;

import {TesterBaseBalV3} from "./TesterBaseBalV3.sol";
import {IGyroECLPPoolFactory} from "./IGyroECLPPoolFactoryBalV3.sol";
import {IGyroECLPPool} from "balancer-v3-interfaces/pool-gyro/IGyroECLPPool.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";

contract UpdatableRateProviderBalV2TestECLP is TesterBaseBalV3 {
    // See
    // https://docs.balancer.fi/developer-reference/contracts/deployment-addresses/base.html#core-contracts
    IGyroECLPPoolFactory constant factory =
        IGyroECLPPoolFactory(0x5F6848976C2914403B425F18B589A65772F082E3);

    IGyroECLPPool pool;

    function setUp() public override {
        TesterBaseBalV3.setUp();

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
                x: 70710678118654752400000000000000000000,
                y: 70710678118654752400000000000000000000
            }),
            u: 78229985344954585431664174165955016000,
            v: 61080126830703701722964730015379048042,
            w: 9630551287951050596866397563651144168,
            z: -7519307226299833111833046586924823789,
            dSq: 99999999999999999886624093342106115200
        });

        bytes32 salt = "foobar";
        pool = IGyroECLPPool(
            factory.create(
                "Test ECLP",
                "TECLP",
                mkTokenConfigs(2),
                eclpParams,
                derivedEclpParams,
                mkRoleAccounts(),
                0.01e18, // 1% swap fee to make things easy
                address(0),
                true, // enable donation (let's set to true)
                false, // don't disable unbalanced liquidity (let's not disable)
                salt
            )
        );

        updatableRateProvider.setPool(
            address(vault), address(pool), BaseUpdatableRateProvider.PoolType.ECLP
        );
        initializePool(address(pool), 2);
    }
}
