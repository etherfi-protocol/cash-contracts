// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/preorder/PreOrder.sol";

contract DeployPreOrderImpl is Script {
    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract

        // Deploy the implementation contract
        address preOrderImpl = address(new PreOrder());
        
        vm.stopBroadcast();

        console.log(
            "PreOrder implementation deployed at: ",
            preOrderImpl
        );
    }
}
