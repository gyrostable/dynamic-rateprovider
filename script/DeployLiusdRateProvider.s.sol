pragma solidity ^0.8.24;

import {Deployment} from "./Deployment.sol";
import {console} from "forge-std/console.sol";
import {LiusdRateProvider} from "src/LiusdRateProvider.sol";

contract DeployLiusdRateProvider is Deployment {
    function run(address lpt, uint32 lockWeeks) public {
        vm.startBroadcast(deployerPrivateKey);
        LiusdRateProvider lrp = new LiusdRateProvider(lpt, lockWeeks);
        console.log("LiusdRateProvider", address(lrp));
    }
}
