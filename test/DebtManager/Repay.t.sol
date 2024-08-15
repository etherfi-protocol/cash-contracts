// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract DebtManagerRepayTest is DebtManagerSetup {
    using SafeERC20 for IERC20;
    using stdStorage for StdStorage;

    uint256 collateralAmount = 0.01 ether;
    uint256 collateralValueInUsdc;
    uint256 borrowAmt;

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

        borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(alice) / 2;

        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();
    }

    function test_RepayWithUsdc() public {
        uint256 debtAmtBefore = debtManager.borrowingOf(alice);
        assertGt(debtAmtBefore, 0);

        uint256 repayAmt = debtAmtBefore;

        vm.startPrank(alice);
        usdc.forceApprove(address(debtManager), repayAmt);
        debtManager.repay(alice, address(usdc), repayAmt);
        vm.stopPrank();

        uint256 debtAmtAfter = debtManager.borrowingOf(alice);
        assertEq(debtAmtBefore - debtAmtAfter, repayAmt);
    }

    function test_RepayWithWeETH() public {
        uint256 debtAmtBefore = debtManager.borrowingOf(alice);
        assertGt(debtAmtBefore, 0);

        uint256 collateralBefore = debtManager.getCollateralValueInUsdc(alice);
        assertEq(collateralBefore, collateralValueInUsdc);

        uint256 repayAmt = debtAmtBefore;

        vm.startPrank(alice);
        debtManager.repay(alice, address(weETH), repayAmt);
        vm.stopPrank();

        uint256 debtAmtAfter = debtManager.borrowingOf(alice);
        assertEq(debtAmtBefore - debtAmtAfter, repayAmt);

        uint256 collateralAfter = debtManager.getCollateralValueInUsdc(alice);
        assertEq(collateralAfter, collateralValueInUsdc - repayAmt);
    }

    function test_CannotRepayMoreThanDebtIncurred() public {
        uint256 totalDebt = debtManager.borrowingOf(alice);

        vm.startPrank(alice);
        vm.expectRevert(IL2DebtManager.CannotPayMoreThanDebtIncurred.selector);
        debtManager.repay(alice, address(weETH), totalDebt + 1);

        vm.expectRevert(IL2DebtManager.CannotPayMoreThanDebtIncurred.selector);
        debtManager.repay(alice, address(usdc), totalDebt + 1);
        vm.stopPrank();
    }

    function test_CannotRepayWithUsdcIfAllowanceIsInsufficient() public {
        vm.startPrank(alice);
        usdc.forceApprove(address(debtManager), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(debtManager),
                0,
                1
            )
        );
        debtManager.repay(alice, address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotRepayWithUsdcIfBalanceIsInsufficient() public {
        deal(address(usdc), alice, 0);

        vm.startPrank(alice);
        usdc.forceApprove(address(debtManager), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                alice,
                0,
                1
            )
        );
        debtManager.repay(alice, address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotPayWithWeEthIfCollateralIsInsufficient() public {
        stdstore
            .target(address(debtManager))
            .sig("borrowingOf(address)")
            .with_key(alice)
            .checked_write(collateralValueInUsdc + 1);

        uint256 totalDebt = debtManager.borrowingOf(alice);
        assertEq(totalDebt, collateralValueInUsdc + 1);

        vm.startPrank(alice);
        vm.expectRevert(IL2DebtManager.InsufficientCollateralToRepay.selector);
        debtManager.repay(alice, address(weETH), totalDebt);
        vm.stopPrank();
    }

    function test_CannotPayWithWeEthIfDebtRatioIsTooHighAfterPayment() public {
        vm.prank(owner);
        debtManager.setLiquidationThreshold(10e18);

        uint256 repayDebt = debtManager.borrowingOf(alice) / 2;

        vm.startPrank(alice);
        vm.expectRevert(IL2DebtManager.InsufficientCollateral.selector);
        debtManager.repay(alice, address(weETH), repayDebt);
        vm.stopPrank();
    }

    function test_CanRepayForOtherUser() public {
        uint256 debtAmtBefore = debtManager.borrowingOf(alice);
        assertGt(debtAmtBefore, 0);

        uint256 repayAmt = debtAmtBefore;

        vm.startPrank(notOwner);
        deal(address(usdc), notOwner, repayAmt);
        usdc.forceApprove(address(debtManager), repayAmt);
        debtManager.repay(alice, address(usdc), repayAmt);
        vm.stopPrank();

        uint256 debtAmtAfter = debtManager.borrowingOf(alice);
        assertEq(debtAmtBefore - debtAmtAfter, repayAmt);
    }

    function test_CanRepayForOtherUserWithCollateral() public {
        vm.startPrank(notOwner);
        vm.expectRevert(IL2DebtManager.OnlyUserCanRepayWithCollateral.selector);
        debtManager.repay(alice, address(weETH), 1);
        vm.stopPrank();
    }
}
