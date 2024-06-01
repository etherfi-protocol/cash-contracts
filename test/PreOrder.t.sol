// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PreOrder} from "../src/PreOrder.sol";

contract PreOrderTest is Test {
    PreOrder public preorder;
    address public whale;
    address public whale2;
    address public tuna;
    address public eBeggar;

    function setUp() public {
        preorder = new PreOrder();

        whale = vm.addr(0x111111);
        whale2 = vm.addr(0x222222);
        tuna = vm.addr(0x333333);
        eBeggar = vm.addr(0x444444);

        vm.deal(whale, 10_000 ether);
        vm.deal(whale2, 10_000 ether);
        vm.deal(tuna, 1_000 ether);
        vm.deal(eBeggar, 1 ether);
    }

    function test_assemblyProperlySetsArrayLength() public {
        PreOrder.TierConfig memory whales = PreOrder.TierConfig({
            costGwei: 1000 ether,
            maxSupply: 10
        });
        PreOrder.TierConfig memory eBeggars = PreOrder.TierConfig({
            costGwei: 0.01 ether,
            maxSupply: 10000
        });
        PreOrder.TierConfig[] memory tiers = new PreOrder.TierConfig[](2);
        tiers[0] = whales;
        tiers[1] = eBeggars;


        address owner = vm.addr(0x12345678);
        address admin = vm.addr(0x87654321);

        address gnosis = address(0xbeef);
        address eEthToken = address(0xdead);

        preorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com",
            tiers
        );

        assertEq(preorder.maxSupply(), whales.maxSupply + eBeggars.maxSupply);
    }

    function test_mint() public {
        PreOrder.TierConfig memory whales = PreOrder.TierConfig({
            costGwei: 1000 ether,
            maxSupply: 10
        });
        PreOrder.TierConfig memory tunas = PreOrder.TierConfig({
            costGwei: 1 ether,
            maxSupply: 100
        });
        PreOrder.TierConfig memory eBeggars = PreOrder.TierConfig({
            costGwei: 0.01 ether,
            maxSupply: 10000
        });
        PreOrder.TierConfig[] memory tiers = new PreOrder.TierConfig[](3);
        tiers[0] = whales;
        tiers[1] = tunas;
        tiers[2] = eBeggars;


        address owner = vm.addr(0x12345678);
        address admin = vm.addr(0x87654321);

        address gnosis = address(0xbeef);
        address eEthToken = address(0xdead);

        preorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com",
            tiers
        );

        // mint increment test 
        vm.prank(whale);
        preorder.mint{value: 1000 ether}(0);
        vm.prank(whale2);
        preorder.mint{value: 1000 ether}(0);

        assertEq(preorder.balanceOf(whale, 0), 1);
        assertEq(preorder.balanceOf(whale2, 1), 1);


        // minting from different tiers
        // the mint ids are staggered by tier
        vm.prank(tuna);
        preorder.mint{value: 1 ether}(1);
        vm.prank(eBeggar);
        preorder.mint{value: 0.01 ether}(2);

        assertEq(preorder.balanceOf(tuna, 10), 1);
        assertEq(preorder.balanceOf(eBeggar, 110), 1);


    }
}
