// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
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
        debtManager.depositCollateral(address(weETH), collateralAmount);
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
