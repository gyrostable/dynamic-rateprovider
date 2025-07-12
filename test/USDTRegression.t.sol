pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UpdatableRateProviderBalV2} from "src/UpdatableRateProviderBalV2.sol";

// Regression where the UpdatableRateProviderBalV2.updateToEdge() reverted b/c of an ABI mismatch:
// In ERC20, .approve() returns a bool, but in USDT on Ethereum it doesn't return anything, and then
// the call fails on decoding the non-existent return value.
// We test this in a fork while replacing with the new code using vm.etch(), mainly for convenience.
// NB This doesn't affect USDT on Base, which is actually standard-compliant; I didn't check the
// other L2s.
contract USDTRegressionTest is Test {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    UpdatableRateProviderBalV2 public urp;

    address admin = 0xd096c2eBE242801466e6f1aC2BF5228cE1Fd445C;
    address updater = 0x8bc920001949589258557412A32F8d297A74F244;

    // UpdatableRateProviderBalV2 for WETH/USDT
    address urp_address = 0x5Dd35d893341a9Da2a94569d4369D2d29c34CaAe;

    function setUp() public virtual {
        vm.createSelectFork(MAINNET_RPC_URL, 22895440);

        UpdatableRateProviderBalV2 urp0 = UpdatableRateProviderBalV2(urp_address);

        // Replace the code with the code of a new deployment from this repo that has the bug fixed.
        UpdatableRateProviderBalV2 replacement = new UpdatableRateProviderBalV2(
            address(urp0.feed()),
            false,
            admin,
            updater,
            address(urp0.gyroConfigManager()),
            address(urp0.governanceRoleManager())
        );
        vm.etch(address(urp0), address(replacement).code);

        // I can probably re-use urp0 but let's play it safe.
        urp = UpdatableRateProviderBalV2(urp_address);
    }

    function testUpdateToEdge() public {
        vm.prank(updater);
        urp.updateToEdge();
    }
}


