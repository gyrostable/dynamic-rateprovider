pragma solidity ^0.8.24;

import {Deployment} from "./Deployment.sol";
import {console} from "forge-std/console.sol";
import {QuotientRateProvider} from "src/QuotientRateProvider.sol";

contract DeployQuotientRateProvider is Deployment {
    function run(address rp1, address rp2) public {
        vm.startBroadcast(deployerPrivateKey);
        QuotientRateProvider qrp = new QuotientRateProvider(rp1, rp2);
        console.log("QuotientRateProvider", address(qrp));
    }
}
