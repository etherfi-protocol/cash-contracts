// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


import "../src/PreOrder.sol";

struct Proxy {
    address admin;
    address implementation;
    address proxy;
}

contract Update is Script {
    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        address impl = address(new PreOrder());

        PreOrder proxy = PreOrder(payable(0x9F3c2Bbe5D94AB9d176394F840c4eA90F2cb6A41));

        bytes memory data = "";

        proxy.upgradeToAndCall(impl, data);

        vm.stopBroadcast();
    }
}
