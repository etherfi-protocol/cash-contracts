// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeSetup} from "../UserSafe/UserSafeSetup.t.sol";

contract SwapperOpenOceanTest is UserSafeSetup {
    function test_Swap() public {
        vm.startPrank(alice);
        uint256 aliceUsdcBalBefore = usdc.balanceOf(alice);
        weETH.transfer(address(swapper), 1 ether);

        if (!isFork(chainId)) {
            swapper.swap(address(weETH), address(usdc), 1 ether, 1, 0, "");
        } else {
            bytes memory swapData = getQuoteOpenOcean(
                chainId,
                address(swapper),
                address(alice),
                address(weETH),
                address(usdc),
                1 ether
            );

            swapper.swap(
                address(weETH),
                address(usdc),
                1 ether,
                1,
                1,
                swapData
            );
        }

        uint256 aliceUsdcBalAfter = usdc.balanceOf(alice);
        assertGt(aliceUsdcBalAfter - aliceUsdcBalBefore, 0);

        vm.stopPrank();
    }
}
