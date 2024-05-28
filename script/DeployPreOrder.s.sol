// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../src/PreOrder.sol";

struct Proxy {
    address admin;
    address implementation;
    address proxy;
}



contract DeployPreOrder is Script {

    // Storages the addresses for the proxy deploy of the PreOrder contract
    Proxy PreOrderAddresses;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        

        
    }
}
