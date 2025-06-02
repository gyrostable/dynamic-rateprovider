pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract Deployment is Script {
    uint256 public deployerPrivateKey;

    function setUp() public virtual {
        deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
    }
}
