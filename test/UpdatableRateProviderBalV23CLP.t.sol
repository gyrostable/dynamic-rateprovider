pragma solidity ^0.8.24;

import {TesterBaseBalV2, IGyroBasePool} from "./TesterBaseBalV2.sol";
import {IGyro3CLPPool} from "gyro-concentrated-lps-balv2/IGyro3CLPPool.sol";
import {IGyro3CLPPoolFactory} from "./IGyro3CLPPoolFactoryBalV2.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";

contract UpdatableRateProviderBalV2Test3CLP is TesterBaseBalV2 {
    // Test version with rateprovider support
    IGyro3CLPPoolFactory constant factory =
        IGyro3CLPPoolFactory(0x4Ac5000Fa00E31B587f1B50D596B40b52e9c6C24);

    IGyro3CLPPool pool;

    // The price range is [alpha, 1/alpha]. Different from the other pools.
    uint256 alpha = 0.7e18;
    uint256 root3Alpha = 0.887904001742600689e18;

    function setUp() public override {
        TesterBaseBalV2.setUp();

        pool = IGyro3CLPPool(
            factory.create(
                IGyro3CLPPoolFactory.NewPoolConfigParams(
                    "Test 3CLP",
                    "T3CLP",
                    mkPoolTokens(3),
                    mkRateProviders(3),
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

        setGyroConfigPermissions(address(pool));
        updatableRateProvider.setPool(address(pool), BaseUpdatableRateProvider.PoolType.C3LP);
        initializePool(pool.getPoolId(), 3);
        poolBase = IGyroBasePool(pool);
    }

    // Override b/c of different price range
    function getExpectedNewValueFor(uint256 feedValue)
        internal
        virtual
        override
        returns (uint256)
    {
        if (feedValue == 0.4e18) {
            // 0.4 / 0.7
            return 0.571428571428571496e18;
        } else if (feedValue == 1.6e18) {
            // 1.6 / (1/0.7) = 1.6 * 0.7
            return 1.119999999999999991e18;
        } else {
            revert("Bug in this test: feedValue not found.");
        }
    }
}
