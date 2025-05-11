pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "oz/utils/Strings.sol";
import {IAccessControl} from "oz/access/IAccessControl.sol";

import {ERC20Mintable} from "./ERC20Mintable.sol";
import {ConstRateProvider} from "./ConstRateProvider.sol";

import {BaseUpdatableRateProvider} from "src/BaseUpdatableRateProvider.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

// Little ad-hoc interface
interface IUpdatableRateProvider {
    function updateToEdge() external;
}

/// @notice Base contract for tests. Tests of the UpgradableRateProvider's are derived from this.
abstract contract TesterBase is Test {
    using SafeERC20 for IERC20;

    bytes32 constant VALUE_UPDATED_SELECTOR = keccak256("ValueUpdated(uint256,uint8)");

    string BASE_RPC_URL = vm.envString("BASE_RPC_URL");

    // address admin = makeAddr("admin");
    address updater = makeAddr("updater");

    ERC20Mintable[3] tokens;
    uint256 constant N_TOKENS = 3;

    ConstRateProvider feed;

    // must be overridden
    function getUpdatableRateProvider() internal view virtual returns (BaseUpdatableRateProvider);

    function setUp() public virtual {
        vm.createSelectFork(BASE_RPC_URL, 30082694);

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

        feed = new ConstRateProvider();
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

    function testRevertIfNotUpdater() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                getUpdatableRateProvider().UPDATER_ROLE()
            )
        );
        IUpdatableRateProvider(address(getUpdatableRateProvider())).updateToEdge();
    }

    // For these tests to work, pools need to be set up such that the range:
    // - includes [0.9, 1.1]
    // - excludes 0.4 and 1.6
    // The default range is [0.5, 1.5], which satisfies both of course.

    function testRevertIfNotOutOfRange() public {
        // feed value didn't change, is still at 1 = in range.
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        IUpdatableRateProvider(address(getUpdatableRateProvider())).updateToEdge();
    }

    function testRevertIfNotOutOfRange2() public {
        // feed value did change, but is still at 1 = in range.
        feed.setRate(1.1e18);
        vm.expectRevert(bytes("Pool not out of range"));
        vm.prank(updater);
        IUpdatableRateProvider(address(getUpdatableRateProvider())).updateToEdge();
    }

    function testUpdateBelow() public {
        uint256 feedValue = 0.4e18;
        feed.setRate(feedValue);

        // New value = 0.8 = 0.4 / alpha, plus a small rounding error.
        uint256 expectedNewValue = getExpectedNewValueFor(feedValue);

        // Because of the small rounding error, we don't check the value (data), but do it below,
        // approximately.
        vm.expectEmit(true, false, false, false);
        emit BaseUpdatableRateProvider.ValueUpdated(
            expectedNewValue, BaseUpdatableRateProvider.OutOfRangeSide.BELOW
        );
        vm.recordLogs();
        vm.prank(updater);
        IUpdatableRateProvider(address(getUpdatableRateProvider())).updateToEdge();

        vm.assertApproxEqAbs(getUpdatableRateProvider().getRate(), expectedNewValue, 100);
        checkValueUpdatedEventValue(expectedNewValue, 100);
    }

    function testUpdateAbove() public {
        uint256 feedValue = 1.6e18;
        feed.setRate(feedValue);

        uint256 expectedNewValue = getExpectedNewValueFor(feedValue);

        // Because of the small rounding error, we don't check the value (data), but do it below,
        // approximately.
        vm.expectEmit(true, false, false, false);
        emit BaseUpdatableRateProvider.ValueUpdated(
            expectedNewValue, BaseUpdatableRateProvider.OutOfRangeSide.ABOVE
        );
        vm.recordLogs();
        vm.prank(updater);
        IUpdatableRateProvider(address(getUpdatableRateProvider())).updateToEdge();

        vm.assertApproxEqAbs(getUpdatableRateProvider().getRate(), expectedNewValue, 100);
        checkValueUpdatedEventValue(expectedNewValue, 100);
    }

    // Map a feedValue to expected rateprovider value. The default implementation is for a price
    // range of [0.5, 1.5] with the updatable rateprovider on the token0.
    // This is intentionally *not* a calculation so we don't create our own bug.
    function getExpectedNewValueFor(uint256 feedValue) internal virtual returns (uint256) {
        if (feedValue == 0.4e18) {
            // 0.4 / 0.5
            return 0.8e18;
        } else if (feedValue == 1.6e18) {
            // 1.6 / 1.5
            return 1.066666666666666725e18;
        } else {
            revert("Bug in this test: feedValue not found.");
        }
    }

    function checkValueUpdatedEventValue(uint256 expectedNewValue, uint256 absTol) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // The Bal V2 version emits a bunch of events for joins/exits, setting config keys etc. We
        // find the right one by selector.
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == VALUE_UPDATED_SELECTOR) {
                (uint256 newValue) = abi.decode(logs[i].data, (uint256));
                vm.assertApproxEqAbs(newValue, expectedNewValue, absTol);
                return;
            }
        }
        revert("Bug in this test: ValueUpdated event not found");
    }
}
