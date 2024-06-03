// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PreOrder} from "../src/PreOrder.sol";

contract PreOrderTest is Test {
    // Default contract 
    PreOrder public preorder;

    // Default users
    address public whale;
    address public whale2;
    address public tuna;
    address public eBeggar;

    // Default contract inputs
    address public owner;
    address public admin;
    address public gnosis;
    address public eEthToken;
    PreOrder.TierConfig[] public tiers;

    function setUp() public {
        whale = vm.addr(0x111111);
        whale2 = vm.addr(0x222222);
        tuna = vm.addr(0x333333);
        eBeggar = vm.addr(0x444444);

        owner = vm.addr(0x12345678);
        admin = vm.addr(0x87654321);

        gnosis = address(0xbeef);
        eEthToken = address(0xdead);

        // Initialize a PreOrder contract
        tiers.push(PreOrder.TierConfig({
            costGwei: 1000 ether,
            maxSupply: 10
        }));
        tiers.push(PreOrder.TierConfig({
            costGwei: 1 ether,
            maxSupply: 100
        }));
        tiers.push(PreOrder.TierConfig({
            costGwei: 0.01 ether,
            maxSupply: 10000
        }));

        preorder = new PreOrder();
        preorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com",
            tiers
        );

        // Deal some tokens to the users
        vm.deal(whale, 10_000 ether);
        vm.deal(whale2, 10_000 ether);
        vm.deal(tuna, 10_000 ether);
        vm.deal(eBeggar, 1 ether);

    }

    function test_assemblyProperlySetsArrayLength() public view {
        // Assert the max supply is correctly set based on the tier configurations
        uint256 expectedMaxSupply = tiers[0].maxSupply + tiers[1].maxSupply + tiers[2].maxSupply;
        assertEq(preorder.maxSupply(), expectedMaxSupply);
    }

    function test_mint() public {
        // Mint increment test 
        vm.prank(whale);
        uint gnosisBalanceStart = gnosis.balance;
        preorder.mint{value: 1000 ether}(0);
        vm.prank(whale2);
        preorder.mint{value: 1000 ether}(0);
        uint gnosisBalanceEnd = gnosis.balance;

        // Ensure payment was recieved and the correct tokens were minted
        assertEq(gnosisBalanceEnd - gnosisBalanceStart, 2000 ether);
        assertEq(preorder.balanceOf(whale, 0), 1);
        assertEq(preorder.balanceOf(whale2, 1), 1);

        // Minting from different tiers
        // The mint ids are staggered by tier
        vm.prank(tuna);
        preorder.mint{value: 1 ether}(1);
        vm.prank(eBeggar);
        preorder.mint{value: 0.01 ether}(2);

        assertEq(preorder.balanceOf(tuna, 10), 1);
        assertEq(preorder.balanceOf(eBeggar, 110), 1);

        // Minting over the max supply
        vm.startPrank(tuna);
        // 99 more of the tuna tier can be minted
        for (uint256 i = 0; i < 99; i++) {
            preorder.mint{value: 1 ether}(1);
        }

        // Tuna user should have all of the tuna tier tokens
        for (uint256 i = 0; i < 100; i++) {
            assertEq(preorder.balanceOf(tuna, i + 10), 1);
        }

        // Tuna tier is now maxed out and payment should fail
        uint gnosisBalanceStart2 = gnosis.balance;
        vm.expectRevert();
        preorder.mint{value: 1 ether}(1);
        uint gnosisBalanceEnd2 = gnosis.balance;

        assertEq(gnosisBalanceEnd2 - gnosisBalanceStart2, 0);
    }

    function test_revert() public {
        // Revert on incorrect amount sent
        vm.startPrank(whale);
        vm.expectRevert("Incorrect amount sent");
        preorder.mint{value: 1001 ether}(0);
        vm.expectRevert("Incorrect amount sent");
        preorder.mint{value: 999 ether}(0);

        // Revert on ETH direct sends to the contract
        vm.expectRevert("Direct transfers allowed");
        (bool success, ) = address(preorder).call{value: 1 ether}("");
        assertEq(success, false);

        // revert on admin/owner functions
        vm.expectRevert();
        preorder.setAdmin(whale);
        vm.expectRevert("Not the admin");
        preorder.setTierData(0, 100 ether);
    }
}
