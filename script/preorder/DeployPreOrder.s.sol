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

contract DeployPreOrder is Script {
    // Storages the addresses for the proxy deploy of the PreOrder contract
    Proxy PreOrderAddresses;

    // TODO: This is the mainnet contract controller gnosis. Be sure to change to the pre-order gnosis  address
    address GnosisSafe = 0xe61B416113292696f9d4e4f7c1d42d5B2FB8BE79;
    address eEthToken = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;

    string baseURI = "https://etherfi-membership-metadata.s3.ap-southeast-1.amazonaws.com/cash-metadata/";

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract

        // Configuring the tiers
        PreOrder.TierConfig memory whales = PreOrder.TierConfig({
            costWei: 10 ether,
            maxSupply: 200
        });
        PreOrder.TierConfig memory chads = PreOrder.TierConfig({
            costWei: 1 ether,
            maxSupply: 2000
        });
        PreOrder.TierConfig memory wojak = PreOrder.TierConfig({
            costWei: 0.1 ether,
            maxSupply: 20_000
        }); 
        PreOrder.TierConfig memory pepe = PreOrder.TierConfig({
            costWei: 0.01 ether,
            maxSupply: 200_000
        });

        // TODO: Add more tiers when the tiers are offically set
        PreOrder.TierConfig[] memory tiers = new PreOrder.TierConfig[](4);
        tiers[0] = whales;
        tiers[1] = chads;
        tiers[2]= wojak;
        tiers[3] = pepe;

        // Deploy the implementation contract
        PreOrderAddresses.implementation = address(new PreOrder());
        PreOrderAddresses.proxy = address(new ERC1967Proxy(PreOrderAddresses.implementation, ""));

        PreOrder preOrder = PreOrder(payable(PreOrderAddresses.proxy));
        preOrder.initialize(
            deployerAddress,
            GnosisSafe,
            deployerAddress,
            eEthToken,
            baseURI,
            tiers
        );
        vm.stopBroadcast();

        console.log("PreOrder implementation deployed at: ", PreOrderAddresses.implementation);
        console.log("PreOrder proxy deployed at: ", PreOrderAddresses.proxy);
        console.log("PreOrder owner: ", deployerAddress);
    }
}
