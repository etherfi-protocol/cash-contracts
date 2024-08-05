// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Swapper1InchV6} from "../../src/Swapper1InchV6.sol";

contract SwapperTest is Test {
    ERC20 usdc = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    ERC20 weETH = ERC20(0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe);
    Swapper1InchV6 swapper;
    address oneInchV6Router = 0x111111125421cA6dc452d289314280a0f8842A65;

    address alice = makeAddr("alice");

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/arbitrum");
        address[] memory assets = new address[](1);
        assets[0] = address(weETH);

        swapper = new Swapper1InchV6(oneInchV6Router, assets);
        deal(address(weETH), alice, 1000 ether);
    }

    function test_swap() public {
        vm.startPrank(alice);

        uint256 aliceUsdcBalBefore = usdc.balanceOf(alice);
        assertEq(aliceUsdcBalBefore, 0);

        weETH.transfer(address(swapper), 1 ether);
        bytes memory swapData = getQuoteOneInch(
            address(swapper),
            address(alice),
            address(weETH),
            address(usdc),
            1 ether
        );

        swapper.swap(address(weETH), address(usdc), 1 ether, 1, swapData);

        uint256 aliceUsdcBalAfter = usdc.balanceOf(alice);
        assertGt(aliceUsdcBalAfter, 0);

        vm.stopPrank();
    }

    function getQuoteOneInch(
        address from,
        address to,
        address srcToken,
        address dstToken,
        uint256 amount
    ) internal returns (bytes memory data) {
        string[] memory inputs = new string[](8);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/getQuote1Inch.ts";
        inputs[3] = vm.toString(from);
        inputs[4] = vm.toString(to);
        inputs[5] = vm.toString(srcToken);
        inputs[6] = vm.toString(dstToken);
        inputs[7] = vm.toString(amount);

        return vm.ffi(inputs);
    }
}
