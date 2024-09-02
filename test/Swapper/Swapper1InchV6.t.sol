// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeSetup} from "../UserSafe/UserSafeSetup.t.sol";
import {Swapper1InchV6} from "../../src/utils/Swapper1InchV6.sol";
import {ChainConfig} from "../Utils.sol";

contract Swapper1InchV6Test is UserSafeSetup {
    Swapper1InchV6 swapper1Inch;

    function setUp() public override {
        super.setUp();
        if (!isFork(chainId)) {
            swapper1Inch = Swapper1InchV6(address(swapper));
        } else {
            address router = chainConfig.swapRouter1InchV6;
            address[] memory assets = new address[](1);
            assets[0] = address(weETH);

            swapper1Inch = new Swapper1InchV6(router, assets);
        }
    }

    function test_Swap() public {
        vm.startPrank(alice);

        uint256 aliceUsdcBalBefore = usdc.balanceOf(alice);

        weETH.transfer(address(swapper), 1 ether);

        if (!isFork(chainId)) {
            swapper1Inch.swap(address(weETH), address(usdc), 1 ether, 1, 0, "");
        } else {
            bytes memory swapData = getQuoteOneInch(
                chainId,
                address(swapper1Inch),
                address(alice),
                address(weETH),
                address(usdc),
                1 ether
            );

            swapper1Inch.swap(
                address(weETH),
                address(usdc),
                1 ether,
                1,
                0,
                swapData
            );
        }

        uint256 aliceUsdcBalAfter = usdc.balanceOf(alice);
        assertGt(aliceUsdcBalAfter - aliceUsdcBalBefore, 0);

        vm.stopPrank();
    }
}
