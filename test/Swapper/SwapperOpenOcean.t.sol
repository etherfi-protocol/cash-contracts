// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Utils, ChainConfig} from "../Utils.sol";
import {console} from "forge-std/console.sol";
import {SwapperOpenOcean} from "../../src/utils/SwapperOpenOcean.sol";

contract SwapperOpenOceanTest is Utils {
    SwapperOpenOcean swapperOpenOcean;
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
            address router = chainConfig.swapRouterOpenOcean;
            address[] memory assets = new address[](1);
            assets[0] = address(usdt);

            swapperOpenOcean = new SwapperOpenOcean(router, assets);
        }
    }
    
    function test_Swap() public {
        if (!isFork(chainId)) return;

        vm.startPrank(alice);
        deal(address(usdc), alice, 1 ether);
        deal(address(usdt), alice, 1 ether);
        uint256 aliceUsdcBalBefore = usdc.balanceOf(alice);
        usdt.transfer(address(swapperOpenOcean), 1000e6);

        bytes memory swapData = getQuoteOpenOcean(
            chainId,
            address(swapperOpenOcean),
            address(alice),
            address(usdt),
            address(usdc),
            1000e6,
            usdt.decimals()
        );

        swapperOpenOcean.swap(
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
