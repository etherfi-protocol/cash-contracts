// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/preorder/PreOrder.sol";

struct Proxy {
    address admin;
    address implementation;
    address proxy;
}

contract UpdatePreOrder is Script {
    // includ the address of the proxy contract to be upgraded
    address constant PROXY_ADDRESS = 0x4E9fA586862183a944AA8A6E158af47CCaE544E2;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        address impl = address(new PreOrder());

        PreOrder proxy = PreOrder(payable(PROXY_ADDRESS));

        bytes memory data = "";

        proxy.upgradeToAndCall(impl, data);
        PreOrder(proxy).setFiatMinter(deployerAddress);

        vm.stopBroadcast();
    }
}
