// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, MockERC20} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract DebtManagerBorrowTest is DebtManagerSetup {
    using stdStorage for StdStorage;
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
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);
        vm.stopPrank();
    }

    function test_CanAddOrRemoveSupportedBorrowTokens() public {
        address newBorrowToken = address(new MockERC20("abc", "ABC", 12));
        uint64 borrowApy = 1e18;
        uint128 minShares = 1e12;

        IL2DebtManager.BorrowTokenConfig memory cfg = IL2DebtManager.BorrowTokenConfig({
            interestIndexSnapshot: 0,
            totalBorrowingAmount: 0,
            totalSharesOfBorrowTokens: 0,
            lastUpdateTimestamp: uint64(block.timestamp),
            borrowApy: borrowApy,
            minShares: minShares
        });

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.BorrowTokenAdded(newBorrowToken);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.BorrowTokenConfigSet(newBorrowToken, cfg);
        debtManager.supportBorrowToken(newBorrowToken, borrowApy, minShares);

        assertEq(debtManager.borrowApyPerSecond(newBorrowToken), borrowApy);

        assertEq(debtManager.getBorrowTokens().length, 2);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));
        assertEq(debtManager.getBorrowTokens()[1], newBorrowToken);
        

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.BorrowTokenRemoved(newBorrowToken);
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

        function test_SetBorrowApy() public {
        uint64 apy = 1e18;

        uint64 borrowApyBefore = debtManager.borrowApyPerSecond(address(usdc));
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.BorrowApySet(address(usdc), borrowApyBefore, apy);
        debtManager.setBorrowApy(address(usdc), apy);

        assertEq(debtManager.borrowApyPerSecond(address(usdc)), apy);
    }

    function test_OnlyAdminCanSetBorrowApy() public {
        uint64 apy = 1e18;
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setBorrowApy(address(usdc), apy);
    }

    function test_BorrowApyCannotBeZero() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.setBorrowApy(address(usdc), 0);
    }

    function test_BorrowApyCannotBeSetForUnsupportedBorrowToken() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.setBorrowApy(address(weETH), 1);
    }

    function test_SetMinBorrowShares() public {
        uint128 shares = uint128(100 * 10 ** usdc.decimals());
        uint128 sharesBefore = debtManager.borrowTokenMinShares(address(usdc));
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.MinSharesOfBorrowTokenSet(address(usdc), sharesBefore, shares);
        debtManager.setMinBorrowTokenShares(address(usdc), shares);

        assertEq(debtManager.borrowTokenMinShares(address(usdc)), shares);
    }

    function test_OnlyAdminCanSetMinBorrowShares() public {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setMinBorrowTokenShares(address(usdc), 1);
    }

    function test_MinBorrowSharesCannotBeZero() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.setMinBorrowTokenShares(address(usdc), 0);
    }

    function test_MinBorrowSharesCannotBeSetForUnsupportedBorrowToken() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.setMinBorrowTokenShares(address(weETH), 1);
    }

    function test_Borrow() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSDC(
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

        assertEq(aaveV3Adapter.getDebt(address(debtManager), address(usdc)), 0);

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

    function test_BorrowWithAave() public {
        if (!isScroll(chainId)) return;

        deal(address(usdc), address(debtManager), 0);

        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        );

        uint256 borrowAmt = totalCanBorrow / 2;

        (, uint256 totalBorrowingAmountBefore) = debtManager.totalBorrowingAmounts();
        assertEq(totalBorrowingAmountBefore, 0);

        bool isUserLiquidatableBefore = debtManager.liquidatable(alice);
        assertEq(isUserLiquidatableBefore, false);

        (, uint256 borrowingOfUserBefore) = debtManager.borrowingOf(alice);
        assertEq(borrowingOfUserBefore, 0);

        vm.startPrank(alice);
        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();

        assertApproxEqAbs(aaveV3Adapter.getDebt(address(debtManager), address(usdc)), borrowAmt, 1);

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

    function test_CannotBorrowWithAaveIfAaveAdapterNotSet() public {
        if (!isScroll(chainId)) return;

        deal(address(usdc), address(debtManager), 0);

        stdstore
            .target(address(cashDataProvider))
            .sig("aaveAdapter()")
            .checked_write(address(0));
        
        assertEq(cashDataProvider.aaveAdapter(), address(0));
        
        vm.prank(alice);
        vm.expectRevert(IL2DebtManager.AaveAdapterNotSet.selector);
        debtManager.borrow(address(usdc), 1e6);
    }

    function test_BorrowIncursInterestWithTime() public {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
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
            .remainingBorrowingCapacityInUSDC(alice);

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
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
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
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        );
        vm.startPrank(alice);
        debtManager.borrow(address(usdc), totalCanBorrow);

        vm.expectRevert(IL2DebtManager.AccountUnhealthy.selector);
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
