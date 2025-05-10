pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "oz/utils/Strings.sol";
import {IAccessControl} from "oz/access/IAccessControl.sol";

import {ERC20Mintable} from "./ERC20Mintable.sol";
import {ConstRateProvider} from "./ConstRateProvider.sol";

/// @notice Base contract for tests. Tests of the UpgradableRateProvider's are derived from this.
contract TesterBase is Test {
    using SafeERC20 for IERC20;

    string BASE_RPC_URL = vm.envString("BASE_RPC_URL");

    // address admin = makeAddr("admin");
    address updater = makeAddr("updater");

    ERC20Mintable[3] tokens;
    uint256 constant N_TOKENS = 3;

    ConstRateProvider feed;

    function setUp() public virtual {
        vm.createSelectFork(BASE_RPC_URL, 30049898);

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
}
