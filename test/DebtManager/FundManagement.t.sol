// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, DebtManagerAdmin, PriceProvider, MockPriceProvider, MockERC20} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {AaveLib} from "../../src/libraries/AaveLib.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DebtManagerFundManagementTest is DebtManagerSetup {
    using SafeERC20 for IERC20;

    uint256 collateralAmt = 0.01 ether;

    function setUp() public override {
        super.setUp();

        deal(address(weETH), address(owner), 1000 ether);
        deal(address(usdc), address(owner), 1 ether);

        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(owner);

        vm.startPrank(owner);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmt);
        debtManager.depositCollateral(address(weETH), owner, collateralAmt);
        vm.stopPrank();
    }

    function test_SupplyAndWithdraw() public {
        uint256 principle = 0.01 ether;

        vm.startPrank(owner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(owner, owner, address(usdc), principle);
        debtManager.supply(owner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.withdrawableBorrowToken(owner, address(usdc)),
            principle
        );

        uint256 earnings = _borrowAndRepay(principle);

        assertEq(
            debtManager.withdrawableBorrowToken(owner, address(usdc)),
            principle + earnings
        );

        vm.prank(owner);
        debtManager.withdrawBorrowToken(address(usdc), earnings + principle);

        assertEq(debtManager.withdrawableBorrowToken(owner, address(usdc)), 0);
    }

    function test_CannotWithdrawLessThanMinShares() public {
        uint256 principle = debtManager.borrowTokenConfig(address(usdc)).minShares;

        vm.startPrank(owner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(owner, owner, address(usdc), principle);
        debtManager.supply(owner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.withdrawableBorrowToken(owner, address(usdc)),
            principle
        );

        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.SharesCannotBeLessThanMinShares.selector);
        debtManager.withdrawBorrowToken(address(usdc), principle - 1);
    }

    function test_SupplyTwice() public {
        uint256 principle = 0.01 ether;
        vm.startPrank(owner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(owner, owner, address(usdc), principle);
        debtManager.supply(owner, address(usdc), principle);
        vm.stopPrank();

        deal(address(usdc), alice, principle);
        
        vm.startPrank(alice);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(alice, alice, address(usdc), principle);
        debtManager.supply(alice, address(usdc), principle);
        vm.stopPrank();
    }

    function test_CanOnlySupplyBorrowTokens() public {
        vm.prank(alice);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.supply(owner, address(weETH), 1);
    }

    function test_CannotWithdrawTokenThatWasNotSupplied() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.ZeroTotalBorrowTokens.selector);
        debtManager.withdrawBorrowToken(address(weETH), 1 ether);
    }

    function _borrowAndRepay(
        uint256 collateralAmount
    ) internal returns (uint256) {
        deal(address(usdc), alice, 1 ether);
        deal(address(weETH), alice, 1000 ether);

        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);

        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        ) / 2;
        debtManager.borrow(address(usdc), borrowAmt);

        // 1 day after, there should be some interest accumulated
        vm.warp(block.timestamp + 24 * 60 * 60);
        uint256 repayAmt = debtManager.borrowingOf(alice, address(usdc));

        IERC20(address(usdc)).forceApprove(address(debtManager), repayAmt);
        debtManager.repay(alice, address(usdc), repayAmt);
        vm.stopPrank();

        return repayAmt - borrowAmt;
    }
}
