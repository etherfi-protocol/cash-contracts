// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PreOrder} from "../src/PreOrder.sol";

contract PreOrderTest is Test {
    PreOrder public preorder;

    function setUp() public {
        preorder = new PreOrder();

    }

    function test_assemblyProperlySetsArrayLength() public {

        PreOrder.TierData memory jacobs = PreOrder.TierData({
            costWei: 1000 ether,
            maxSupply: 10,
            minted: 0
        });
        PreOrder.TierData memory eBeggars = PreOrder.TierData({
            costWei: 0.01 ether,
            maxSupply: 10000,
            minted: 0
        });
        PreOrder.TierData[] memory tiers = new PreOrder.TierData[](2);
        tiers[0] = jacobs;
        tiers[1] = eBeggars;


        address owner = vm.addr(0x12345678);
        address admin = vm.addr(0x87654321);

        address gnosis = address(0xbeef); // TODO
        address eEthToken = address(0xdead); // TODO

        preorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com",
            tiers
        );

        assertEq(preorder.maxSupply(), jacobs.maxSupply + eBeggars.maxSupply);
    }
}
