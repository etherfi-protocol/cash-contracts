// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Utils, ChainConfig} from "../Utils.sol";
import {console} from "forge-std/console.sol";
import {Swapper1InchV6} from "../../src/utils/Swapper1InchV6.sol";

contract Swapper1InchV6Test is Utils {
    Swapper1InchV6 swapper1InchV6;
    string chainId;
    ERC20 usdt;
    ERC20 usdc;
    address alice = makeAddr("alice");
    
    function setUp() public {
        chainId = vm.envString("TEST_CHAIN");

        if (isFork(chainId)) {
            ChainConfig memory chainConfig = getChainConfig(chainId);
            vm.createSelectFork(chainConfig.rpc);

            usdt = ERC20(chainConfig.usdt);
            usdc = ERC20(chainConfig.usdc);
            address router = chainConfig.swapRouter1InchV6;
            address[] memory assets = new address[](1);
            assets[0] = address(usdt);

            swapper1InchV6 = new Swapper1InchV6(router, assets);
        }
    }
    
    function test_Swap() public {
        if (!isFork(chainId) || isScroll(chainId)) return;

        vm.startPrank(alice);
        deal(address(usdc), alice, 1 ether);
        deal(address(usdt), alice, 1 ether);
        uint256 aliceUsdcBalBefore = usdc.balanceOf(alice);
        usdt.transfer(address(swapper1InchV6), 1000e6);

        bytes memory swapData = getQuoteOneInch(
            chainId,
            address(swapper1InchV6),
            address(alice),
            address(usdt),
            address(usdc),
            1000e6,
            usdt.decimals()
        );

        swapper1InchV6.swap(
            address(usdt),
            address(usdc),
            1000e6,
            1,
            1,
            swapData
        );

        uint256 aliceUsdcBalAfter = usdc.balanceOf(alice);
        assertGt(aliceUsdcBalAfter - aliceUsdcBalBefore, 0);

        vm.stopPrank();
    }
}
