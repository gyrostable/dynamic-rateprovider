pragma solidity ^0.8.24;

import {UpdatableRateProviderBalV2} from "src/UpdatableRateProviderBalV2.sol";
import {Deployment} from "./Deployment.sol";
import {console} from "forge-std/console.sol";

contract DeployUpdatableRateProviderBalV2 is Deployment {
    function run(address feed, bool invert, address admin, address updater, address gyroConfigManager, address governanceRoleManager) public {
        vm.startBroadcast(deployerPrivateKey);
        UpdatableRateProviderBalV2 urp = new UpdatableRateProviderBalV2(feed, invert, admin, updater, gyroConfigManager, governanceRoleManager);
        console.log("UpdatableRateProviderBalV2", address(urp));
    }
}
