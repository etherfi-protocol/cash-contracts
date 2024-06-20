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

    // TODO: This is the mainnet contract controller gnosis. Be sure to change to the pre-order gnosis  address
    address GnosisSafe = 0x2aCA71020De61bb532008049e1Bd41E451aE8AdC;
    address eEthToken = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;

    string baseURI = "https://api.pudgypenguins.io/lil/";

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
