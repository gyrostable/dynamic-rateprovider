pragma solidity ^0.8.24;

import {UpdatableRateProviderBalV2} from "src/UpdatableRateProviderBalV2.sol";
import {Deployment} from "./Deployment.sol";
import {console} from "forge-std/console.sol";

contract DeployUpdatableRateProviderBalV2 is Deployment {
    // Version without the initialValue argument, for backwards-compat.
    function run(address feed, bool invert, address admin, address updater, address gyroConfigManager, address governanceRoleManager) public {
        vm.startBroadcast(deployerPrivateKey);
        UpdatableRateProviderBalV2 urp = new UpdatableRateProviderBalV2(feed, invert, 0, admin, updater, gyroConfigManager, governanceRoleManager);
        console.log("UpdatableRateProviderBalV2", address(urp));
    }

    // Version that has the initialValue argument.
    function run(address feed, bool invert, uint256 initialValue, address admin, address updater, address gyroConfigManager, address governanceRoleManager) public {
        vm.startBroadcast(deployerPrivateKey);
        UpdatableRateProviderBalV2 urp = new UpdatableRateProviderBalV2(feed, invert, initialValue, admin, updater, gyroConfigManager, governanceRoleManager);
        console.log("UpdatableRateProviderBalV2", address(urp));
    }
}
