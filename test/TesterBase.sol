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

    ERC20Mintable token0;
    ERC20Mintable token1;
    ERC20Mintable token2;

    ConstRateProvider feed;

    function setUp() virtual public {
        // TODO needs bumping when we deployed the contracts we need.
        vm.createSelectFork(BASE_RPC_URL, 29914982);

        token0 = new ERC20Mintable();
        token1 = new ERC20Mintable();
        token2 = new ERC20Mintable();

        token0.mint(address(this), 10_000e18);
        token1.mint(address(this), 10_000e18);
        token2.mint(address(this), 10_000e18);

        feed = new ConstRateProvider();
    }
}

