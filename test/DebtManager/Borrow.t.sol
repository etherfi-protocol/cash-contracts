// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, MockERC20} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract DebtManagerBorrowTest is DebtManagerSetup {
    using SafeERC20 for IERC20;

    uint256 collateralAmount = 0.01 ether;
    uint256 collateralValueInUsdc;

    function setUp() public override {
        super.setUp();

        collateralValueInUsdc = debtManager.convertCollateralTokenToUsdc(
            address(weETH),
            collateralAmount
        );

        deal(address(usdc), alice, 1 ether);
        deal(address(weETH), alice, 1000 ether);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);

        vm.startPrank(alice);
        weETH.safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);
        vm.stopPrank();
    }

    function test_CanAddOrRemoveSupportedBorrowTokens() public {
        address newBorrowToken = address(weETH);

        vm.startPrank(owner);
        debtManager.supportBorrowToken(newBorrowToken);

        assertEq(debtManager.getBorrowTokens().length, 2);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));
        assertEq(debtManager.getBorrowTokens()[1], newBorrowToken);

        debtManager.unsupportBorrowToken(address(usdc));
        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], newBorrowToken);

        vm.stopPrank();
    }

    function test_OnlyAdminCanSupportOrUnsupportBorrowTokens() public {
        address newBorrowToken = address(weETH);

        vm.startPrank(alice);
        vm.expectRevert(
            buildAccessControlRevertData(alice, debtManager.ADMIN_ROLE())
        );
        debtManager.supportBorrowToken(newBorrowToken);
        vm.expectRevert(
            buildAccessControlRevertData(alice, debtManager.ADMIN_ROLE())
        );
        debtManager.unsupportBorrowToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotAddBorrowTokenIfAlreadySupported() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.AlreadyBorrowToken.selector);
        debtManager.supportBorrowToken(address(usdc));
        vm.stopPrank();
    }

    function test_CannotAddNullAddressAsBorrowToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.supportBorrowToken(address(0));
        vm.stopPrank();
    }

    function test_CannotUnsupportTokenForBorrowIfItIsNotABorrowTokenAlready()
        public
    {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NotABorrowToken.selector);
        debtManager.unsupportBorrowToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotUnsupportAllTokensAsBorrowTokens() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NoBorrowTokenLeft.selector);
        debtManager.unsupportBorrowToken(address(usdc));
        vm.stopPrank();
    }

    function test_CannotUnsupportAddressZeroAsBorrowToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.unsupportBorrowToken(address(0));
        vm.stopPrank();
    }

    function test_Borrow() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        );

        uint256 borrowAmt = totalCanBorrow / 2;

        uint256 totalBorrowingAmountBefore = debtManager.totalBorrowingAmount();
        assertEq(totalBorrowingAmountBefore, 0);

        bool isUserLiquidatableBefore = debtManager.liquidatable(alice);
        assertEq(isUserLiquidatableBefore, false);

        uint256 borrowingOfUserBefore = debtManager.borrowingOf(alice);
        assertEq(borrowingOfUserBefore, 0);

        uint256 debtRatioOfBefore = debtManager.debtRatioOf(alice);
        assertEq(debtRatioOfBefore, 0);

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();

        uint256 expectedDebtRatio = (borrowAmt * 1e20) / collateralValueInUsdc;

        uint256 totalBorrowingAmountAfter = debtManager.totalBorrowingAmount();
        assertEq(totalBorrowingAmountAfter, borrowAmt);

        bool isUserLiquidatableAfter = debtManager.liquidatable(alice);
        assertEq(isUserLiquidatableAfter, false);

        uint256 borrowingOfUserAfter = debtManager.borrowingOf(alice);
        assertEq(borrowingOfUserAfter, borrowAmt);

        uint256 debtRatioOfAfter = debtManager.debtRatioOf(alice);
        assertEq(debtRatioOfAfter, expectedDebtRatio);
    }

    function test_BorrowIncursInterestWithTime() public {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        ) / 2;

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();

        assertEq(debtManager.borrowingOf(alice), borrowAmt);

        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        assertEq(debtManager.borrowingOf(alice), borrowAmt + expectedInterest);
    }

    function test_BorrowTokenWithDecimalsOtherThanSix() public {
        MockERC20 newToken = new MockERC20("mockToken", "MTK", 12);
        deal(address(newToken), address(debtManager), 1 ether);

        vm.prank(owner);
        debtManager.supportBorrowToken(address(newToken));

        uint256 remainingBorrowCapacityInUsdc = debtManager
            .remainingBorrowingCapacityInUSDC(alice);

        assertEq(debtManager.borrowingOf(alice), 0);

        vm.prank(alice);
        debtManager.borrow(
            address(newToken),
            (remainingBorrowCapacityInUsdc * 1e12) / 1e6
        );

        assertEq(debtManager.borrowingOf(alice), remainingBorrowCapacityInUsdc);
    }

    function test_NextBorrowAutomaticallyAddsInterestToThePreviousBorrows()
        public
    {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        ) / 4;

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);

        assertEq(debtManager.borrowingOf(alice), borrowAmt);

        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        uint256 expectedTotalBorrowWithInterest = borrowAmt + expectedInterest;

        assertEq(
            debtManager.borrowingOf(alice),
            expectedTotalBorrowWithInterest
        );

        debtManager.borrow(address(usdc), borrowAmt);

        assertEq(
            debtManager.borrowingOf(alice),
            expectedTotalBorrowWithInterest + borrowAmt
        );

        vm.stopPrank();
    }

    function test_CannotBorrowIfTokenIsNotSupported() public {
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.borrow(address(weETH), 1);
    }

    function test_CannotBorrowIfDebtRatioGreaterThanThreshold() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        );
        vm.startPrank(alice);
        debtManager.borrow(address(usdc), totalCanBorrow);

        vm.expectRevert(IL2DebtManager.InsufficientCollateral.selector);
        debtManager.borrow(address(usdc), 1);

        vm.stopPrank();
    }

    function test_CannotBorrowIfUsdcBalanceInsufficientInDebtManager() public {
        deal(address(usdc), address(debtManager), 0);
        vm.startPrank(alice);
        vm.expectRevert(IL2DebtManager.InsufficientLiquidity.selector);
        debtManager.borrow(address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotBorrowIfNoCollateral() public {
        vm.startPrank(notOwner);
        vm.expectRevert(IL2DebtManager.ZeroCollateralValue.selector);
        debtManager.borrow(address(usdc), 1);
        vm.stopPrank();
    }
}
