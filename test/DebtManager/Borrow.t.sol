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

        collateralValueInUsdc = debtManager.convertCollateralTokenToUsd(
            address(weETH),
            collateralAmount
        );

        deal(address(usdc), alice, 1 ether);
        deal(address(weETH), alice, 1000 ether);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);

        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);
        vm.stopPrank();
    }

    function test_CanAddOrRemoveSupportedBorrowTokens() public {
        address newBorrowToken = address(new MockERC20("abc", "ABC", 12));
        uint64 borrowApy = 1e18;
        uint128 _minShares = 1e12;

        vm.startPrank(owner);
        debtManager.supportBorrowToken(newBorrowToken, borrowApy, _minShares);

        assertEq(debtManager.borrowApyPerSecond(newBorrowToken), borrowApy);

        assertEq(debtManager.getBorrowTokens().length, 2);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));
        assertEq(debtManager.getBorrowTokens()[1], newBorrowToken);

        debtManager.unsupportBorrowToken(newBorrowToken);
        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));

        vm.stopPrank();
    }

    function test_CannotRemoveSupportIfBorrowTokenIsStillInTheSystem() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.BorrowTokenStillInTheSystem.selector);
        debtManager.unsupportBorrowToken(address(usdc));

        vm.stopPrank();
    }

    function test_OnlyAdminCanSupportOrUnsupportBorrowTokens() public {
        address newBorrowToken = address(new MockERC20("abc", "ABC", 12));

        vm.startPrank(alice);
        vm.expectRevert(
            buildAccessControlRevertData(alice, ADMIN_ROLE)
        );
        debtManager.supportBorrowToken(newBorrowToken, 1, 1);
        vm.expectRevert(
            buildAccessControlRevertData(alice, ADMIN_ROLE)
        );
        debtManager.unsupportBorrowToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotAddBorrowTokenIfAlreadySupported() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.AlreadyBorrowToken.selector);
        debtManager.supportBorrowToken(address(usdc), 1, 1);
        vm.stopPrank();
    }

    function test_CannotAddNullAddressAsBorrowToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.supportBorrowToken(address(0), 1, 1);
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
        deal(address(usdc), address(debtManager), 0);
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NoBorrowTokenLeft.selector);
        debtManager.unsupportBorrowToken(address(usdc));
        vm.stopPrank();
    }

    function test_CanSetBorrowApy() public {
        uint64 apy = 1;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.BorrowApySet(address(usdc), borrowApyPerSecond, apy);
        debtManager.setBorrowApy(address(usdc), apy);

        IL2DebtManager.BorrowTokenConfig memory config = debtManager.borrowTokenConfig(address(usdc));
        assertEq(config.borrowApy, apy);
        vm.stopPrank();
    }

    function test_OnlyAdminCanSetBorrowApy() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setBorrowApy(address(usdc), 1);
        vm.stopPrank();
    }

    function test_BorrowApyCannotBeZero() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.setBorrowApy(address(usdc), 0);
        vm.stopPrank();
    }

    function test_CannotSetBorrowApyForUnsupportedToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.setBorrowApy(address(weETH), 1);
        vm.stopPrank();
    }

    function test_CanSetMinBorrowTokenShares() public {
        uint128 shares = 100;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.MinSharesOfBorrowTokenSet(address(usdc), minShares, shares);
        debtManager.setMinBorrowTokenShares(address(usdc), shares);

        IL2DebtManager.BorrowTokenConfig memory config = debtManager.borrowTokenConfig(address(usdc));
        assertEq(config.minShares, shares);
    }

    function test_OnlyAdminCanSetBorrowTokenMinShares() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setMinBorrowTokenShares(address(usdc), 1);
        vm.stopPrank();
    }


    function test_BorrowTokenMinSharesCannotBeZero() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.setMinBorrowTokenShares(address(usdc), 0);
        vm.stopPrank();
    }

    function test_CannotSetBorrowTokenMinSharesForUnsupportedToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.setMinBorrowTokenShares(address(weETH), 1);
        vm.stopPrank();
    }

    function test_Borrow() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSD(
            alice
        );

        uint256 borrowAmt = totalCanBorrow / 2;

        (, uint256 totalBorrowingAmountBefore) = debtManager
            .totalBorrowingAmounts();
        assertEq(totalBorrowingAmountBefore, 0);

        bool isUserLiquidatableBefore = debtManager.liquidatable(alice);
        assertEq(isUserLiquidatableBefore, false);

        (, uint256 borrowingOfUserBefore) = debtManager.borrowingOf(alice);
        assertEq(borrowingOfUserBefore, 0);

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();

        uint256 borrowInUsdc = debtManager.borrowingOf(alice, address(usdc));
        assertEq(borrowInUsdc, borrowAmt);

        (, uint256 totalBorrowingAmountAfter) = debtManager
            .totalBorrowingAmounts();
        assertEq(totalBorrowingAmountAfter, borrowAmt);

        bool isUserLiquidatableAfter = debtManager.liquidatable(alice);
        assertEq(isUserLiquidatableAfter, false);

        (, uint256 borrowingOfUserAfter) = debtManager.borrowingOf(alice);
        assertEq(borrowingOfUserAfter, borrowAmt);
    }

    function test_BorrowIncursInterestWithTime() public {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(
            alice
        ) / 2;

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();

        assertEq(debtManager.borrowingOf(alice, address(usdc)), borrowAmt);

        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        assertEq(
            debtManager.borrowingOf(alice, address(usdc)),
            borrowAmt + expectedInterest
        );
    }

    function test_BorrowTokenWithDecimalsOtherThanSix() public {
        MockERC20 newToken = new MockERC20("mockToken", "MTK", 12);
        deal(address(newToken), address(debtManager), 1 ether);
        uint64 borrowApy = 1e18;

        vm.prank(owner);
        debtManager.supportBorrowToken(address(newToken), borrowApy, 1);

        uint256 remainingBorrowCapacityInUsdc = debtManager
            .remainingBorrowingCapacityInUSD(alice);

        (, uint256 totalBorrowingsOfAlice) = debtManager.borrowingOf(alice);
        assertEq(totalBorrowingsOfAlice, 0);

        vm.prank(alice);
        debtManager.borrow(
            address(newToken),
            (remainingBorrowCapacityInUsdc * 1e12) / 1e6
        );

        (, totalBorrowingsOfAlice) = debtManager.borrowingOf(alice);
        assertEq(totalBorrowingsOfAlice, remainingBorrowCapacityInUsdc);
    }

    function test_NextBorrowAutomaticallyAddsInterestToThePreviousBorrows()
        public
    {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(
            alice
        ) / 4;

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);

        assertEq(debtManager.borrowingOf(alice, address(usdc)), borrowAmt);

        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        uint256 expectedTotalBorrowWithInterest = borrowAmt + expectedInterest;

        assertEq(
            debtManager.borrowingOf(alice, address(usdc)),
            expectedTotalBorrowWithInterest
        );

        debtManager.borrow(address(usdc), borrowAmt);

        assertEq(
            debtManager.borrowingOf(alice, address(usdc)),
            expectedTotalBorrowWithInterest + borrowAmt
        );

        vm.stopPrank();
    }

    function test_CannotBorrowIfTokenIsNotSupported() public {
        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(notOwner);

        vm.startPrank(notOwner);        
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.borrow(address(weETH), 1);
    }

    function test_CannotBorrowIfDebtRatioGreaterThanThreshold() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSD(
            alice
        );
        vm.startPrank(alice);
        debtManager.borrow(address(usdc), totalCanBorrow);

        vm.expectRevert(IL2DebtManager.AccountUnhealthy.selector);
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
        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(notOwner);

        vm.startPrank(notOwner);
        vm.expectRevert(IL2DebtManager.AccountUnhealthy.selector);
        debtManager.borrow(address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotBorrowIfNotUserSafe() public {
        vm.expectRevert(IL2DebtManager.OnlyUserSafe.selector);
        debtManager.borrow(address(usdc), 1);
    }
}
