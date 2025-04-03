// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UserSafeCore, UserSafeLib, SpendingLimit, SpendingLimitLib} from "../../src/user-safe/UserSafeCore.sol";
import {Setup, IUserSafe, IL2DebtManager} from "../Setup.t.sol";

contract UserSafeMigrateTest is Setup {
    function test_CanMigrateFundsToNewSafe() public {
        address newSafe = makeAddr("newSafe");
        uint256 usdcBalance = 100e6;
        uint256 weETHBalance = 1 ether;
        uint256 ethBalance = 1 ether;

        deal(address(usdc), address(aliceSafe), usdcBalance);
        deal(address(weETH), address(aliceSafe), weETHBalance);
        deal(address(aliceSafe), ethBalance);

        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);
        tokens[2] = address(eth);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeCore.Migrate(newSafe);
        aliceSafe.migrate(tokens, newSafe);

        assertEq(usdc.balanceOf(address(aliceSafe)), 0);
        assertEq(weETH.balanceOf(address(aliceSafe)), 0);
        assertEq(address(aliceSafe).balance, 0);
        assertEq(usdc.balanceOf(newSafe), usdcBalance);
        assertEq(weETH.balanceOf(newSafe), weETHBalance);
        assertEq(newSafe.balance, ethBalance);
    }

    function test_MigrateWithZeroBalances() public {
        address newSafe = makeAddr("newSafe");
        
        // No funds in the safe
        assertEq(usdc.balanceOf(address(aliceSafe)), 0);
        assertEq(weETH.balanceOf(address(aliceSafe)), 0);
        assertEq(address(aliceSafe).balance, 0);

        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);
        tokens[2] = address(eth);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeCore.Migrate(newSafe);
        aliceSafe.migrate(tokens, newSafe);

        // Should complete without issues even with zero balances
        assertEq(usdc.balanceOf(newSafe), 0);
        assertEq(weETH.balanceOf(newSafe), 0);
        assertEq(newSafe.balance, 0);
    }

    function test_MigratePartialTokenList() public {
        address newSafe = makeAddr("newSafe");
        uint256 usdcBalance = 100e6;
        uint256 weETHBalance = 1 ether;
        uint256 ethBalance = 1 ether;

        // Set up balances for aliceSafe
        deal(address(usdc), address(aliceSafe), usdcBalance);
        deal(address(weETH), address(aliceSafe), weETHBalance);
        deal(address(aliceSafe), ethBalance);

        // Only migrate USDC and ETH, not weETH
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(eth);

        vm.prank(etherFiWallet);
        aliceSafe.migrate(tokens, newSafe);

        // weETH should remain in the original safe
        assertEq(usdc.balanceOf(address(aliceSafe)), 0);
        assertEq(weETH.balanceOf(address(aliceSafe)), weETHBalance);
        assertEq(address(aliceSafe).balance, 0);
        
        // Only USDC and ETH should be in the new safe
        assertEq(usdc.balanceOf(newSafe), usdcBalance);
        assertEq(weETH.balanceOf(newSafe), 0);
        assertEq(newSafe.balance, ethBalance);
    }

    function test_MigrateWithEmptyTokenList() public {
        address newSafe = makeAddr("newSafe");
        uint256 usdcBalance = 100e6;
        uint256 weETHBalance = 1 ether;
        uint256 ethBalance = 1 ether;

        // Set up balances for aliceSafe
        deal(address(usdc), address(aliceSafe), usdcBalance);
        deal(address(weETH), address(aliceSafe), weETHBalance);
        deal(address(aliceSafe), ethBalance);

        // Empty token list
        address[] memory tokens = new address[](0);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.InvalidInput.selector);
        aliceSafe.migrate(tokens, newSafe);

        // All funds should remain in the original safe
        assertEq(usdc.balanceOf(address(aliceSafe)), usdcBalance);
        assertEq(weETH.balanceOf(address(aliceSafe)), weETHBalance);
        assertEq(address(aliceSafe).balance, ethBalance);
        
        // New safe should have no funds
        assertEq(usdc.balanceOf(newSafe), 0);
        assertEq(weETH.balanceOf(newSafe), 0);
        assertEq(newSafe.balance, 0);
    }
    function test_RevertsWhenMigrateWithEmptyTokenList() public {
        address newSafe = makeAddr("newSafe");
        uint256 usdcBalance = 100e6;
        uint256 weETHBalance = 1 ether;
        uint256 ethBalance = 1 ether;

        // Set up balances for aliceSafe
        deal(address(usdc), address(aliceSafe), usdcBalance);
        deal(address(weETH), address(aliceSafe), weETHBalance);
        deal(address(aliceSafe), ethBalance);

        // Empty token list
        address[] memory tokens = new address[](0);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.InvalidInput.selector);
        aliceSafe.migrate(tokens, newSafe);

        // All funds should remain in the original safe
        assertEq(usdc.balanceOf(address(aliceSafe)), usdcBalance);
        assertEq(weETH.balanceOf(address(aliceSafe)), weETHBalance);
        assertEq(address(aliceSafe).balance, ethBalance);
        
        // New safe should have no funds
        assertEq(usdc.balanceOf(newSafe), 0);
        assertEq(weETH.balanceOf(newSafe), 0);
        assertEq(newSafe.balance, 0);
    }

    function test_RevertsWhenMigrateWithEmptyNewSafeAddress() public {
        uint256 usdcBalance = 100e6;
        uint256 weETHBalance = 1 ether;
        uint256 ethBalance = 1 ether;

        // Set up balances for aliceSafe
        deal(address(usdc), address(aliceSafe), usdcBalance);
        deal(address(weETH), address(aliceSafe), weETHBalance);
        deal(address(aliceSafe), ethBalance);

        // Empty token list
        address[] memory tokens = new address[](0);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.InvalidInput.selector);
        aliceSafe.migrate(tokens, address(0));
    }

    function test_RevertWhenNonEtherFiWalletCallsMigrate() public {
        address newSafe = makeAddr("newSafe");
        
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);
        tokens[2] = address(eth);

        vm.prank(alice);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.migrate(tokens, newSafe);
    }

    function test_RevertWhenBorrowingNotZero() public {
        address newSafe = makeAddr("newSafe");

        deal(address(usdc), address(aliceSafe), 1000e6);
        deal(address(usdc), address(debtManager), 1000e6);

        vm.prank(address(aliceSafe));        
        debtManager.borrow(address(usdc), 10e6);
                
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);
        tokens[2] = address(eth);

        vm.prank(etherFiWallet);
        vm.expectRevert(UserSafeCore.BorrowNotZero.selector);
        aliceSafe.migrate(tokens, newSafe);
    }
}
