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

    address GnosisSafe = 0x1234567890123456789012345678901234567890;
    address eEthToken = 0x1234567890123456789012345678901234567890;

    string baseURI = "https://s3.amazonaws.com/preOrder-NFT-Bucket/";

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        PreOrderAddresses.implementation = address(new PreOrder());
        // Initialize the implementation contract for best practices
        PreOrder(payable(PreOrderAddresses.implementation)).initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            "",

            new PreOrder.TierConfig[](0)
        );

        // Configuring the tiers
        PreOrder.TierConfig memory whales = PreOrder.TierConfig({
            costWei: 1000 ether,
            maxSupply: 10
        });
        PreOrder.TierConfig memory eBeggars = PreOrder.TierConfig({
            costWei: 0.01 ether,
            maxSupply: 10000
        });

        // TODO: Add more tiers when the tiers are offically set
        PreOrder.TierConfig[] memory tiers = new PreOrder.TierConfig[](2);
        tiers[0] = whales;
        tiers[1] = eBeggars;
        
        // Deploy the proxy contract
        PreOrderAddresses.proxy = address(new TransparentUpgradeableProxy(
            PreOrderAddresses.implementation, 
            address(0), 
            abi.encodeWithSelector(
                PreOrder.initialize.selector,

                deployerAddress,
                GnosisSafe,
                deployerAddress,
                eEthToken,
                baseURI,

                tiers
            )
        ));
        vm.stopBroadcast();

        console.log("PreOrder implementation deployed at: ", PreOrderAddresses.implementation);
        console.log("PreOrder proxy deployed at: ", PreOrderAddresses.proxy);
        console.log("PreOrder owner: ", deployerAddress);
    }
}
