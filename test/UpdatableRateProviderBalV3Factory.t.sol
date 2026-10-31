// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "oz/access/Ownable.sol";

import {UpdatableRateProviderBalV3Factory} from "src/UpdatableRateProviderBalV3Factory.sol";
import {UpdatableRateProviderBalV3} from "src/UpdatableRateproviderBalV3.sol";
import {ConstRateProvider} from "./ConstRateProvider.sol";

contract UpdatableRateProviderBalV3FactoryTest is Test {
    address internal owner = makeAddr("owner");
    address internal admin = makeAddr("admin");
    address internal updater = makeAddr("updater");
    address internal stranger = makeAddr("stranger");

    ConstRateProvider internal feed;
    UpdatableRateProviderBalV3Factory internal factory;

    uint256 internal constant INITIAL_RATE = 2e18;
    string internal constant FACTORY_VERSION = "UpdatableRateProviderBalV3Factory v1";
    uint256 internal constant RATE_PROVIDER_VERSION = 1;

    function setUp() public {
        feed = new ConstRateProvider();
        feed.setRate(INITIAL_RATE);

        factory = new UpdatableRateProviderBalV3Factory(owner, FACTORY_VERSION, RATE_PROVIDER_VERSION);
    }

    function test_create_deploysWorkingRateProvider() public {
        UpdatableRateProviderBalV3 urp =
            factory.create(address(feed), false, 0, admin, updater);

        assertEq(address(urp.feed()), address(feed));
        assertFalse(urp.invert());
        assertEq(urp.getRate(), INITIAL_RATE);
        assertTrue(urp.hasRole(urp.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(urp.hasRole(urp.UPDATER_ROLE(), updater));
        assertTrue(factory.isRateProviderFromFactory(address(urp)));
    }

    function test_create_respectsInvertAndInitialValue() public {
        uint256 initialValue = 1.5e18;
        UpdatableRateProviderBalV3 urp =
            factory.create(address(feed), true, initialValue, admin, updater);

        assertTrue(urp.invert());
        assertEq(urp.getRate(), initialValue);
    }

    function test_create_allowsDuplicateParams() public {
        UpdatableRateProviderBalV3 urp1 =
            factory.create(address(feed), false, 0, admin, updater);
        UpdatableRateProviderBalV3 urp2 =
            factory.create(address(feed), false, 0, admin, updater);

        assertTrue(address(urp1) != address(urp2));
        assertTrue(factory.isRateProviderFromFactory(address(urp1)));
        assertTrue(factory.isRateProviderFromFactory(address(urp2)));
    }

    function test_isRateProviderFromFactory_falseForForeign() public view {
        assertFalse(factory.isRateProviderFromFactory(address(feed)));
        assertFalse(factory.isRateProviderFromFactory(address(0)));
    }

    function test_getRateProviderVersion() public view {
        assertEq(factory.getRateProviderVersion(), RATE_PROVIDER_VERSION);
        assertEq(factory.version(), FACTORY_VERSION);
    }

    function test_disable_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        factory.disable();

        vm.prank(owner);
        factory.disable();

        vm.expectRevert(UpdatableRateProviderBalV3Factory.RateProviderFactoryIsDisabled.selector);
        factory.create(address(feed), false, 0, admin, updater);
    }

    function test_disable_isOneWay() public {
        vm.prank(owner);
        factory.disable();

        vm.prank(owner);
        vm.expectRevert(UpdatableRateProviderBalV3Factory.RateProviderFactoryIsDisabled.selector);
        factory.disable();
    }
}
