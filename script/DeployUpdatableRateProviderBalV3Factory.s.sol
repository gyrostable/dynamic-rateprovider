// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/dynamic-rateprovider>.

pragma solidity ^0.8.24;

import {Deployment} from "./Deployment.sol";
import {console} from "forge-std/console.sol";
import {UpdatableRateProviderBalV3Factory} from "src/UpdatableRateProviderBalV3Factory.sol";

contract DeployUpdatableRateProviderBalV3Factory is Deployment {
    function run(address owner, string memory factoryVersion, uint256 rateProviderVersion) public {
        vm.startBroadcast(deployerPrivateKey);
        UpdatableRateProviderBalV3Factory factory =
            new UpdatableRateProviderBalV3Factory(owner, factoryVersion, rateProviderVersion);
        console.log("UpdatableRateProviderBalV3Factory", address(factory));
        vm.stopBroadcast();
    }
}
