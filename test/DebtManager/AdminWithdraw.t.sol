// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, MockERC20} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DebtManagerAdminWithdrawTest is DebtManagerSetup {
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
        deal(address(weETH), address(debtManager), 100 ether);

        vm.startPrank(alice);
        weETH.safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);
        vm.stopPrank();
    }

    function test_AdminWithdrawCollateralToken() public {
        uint256 withdrawAmt = 1 ether;

        uint256 etherFiCashSafeBalBefore = weETH.balanceOf(etherFiCashSafe);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.AdminWithdrawFunds(address(weETH), withdrawAmt);
        debtManager.adminWithdrawFunds(address(weETH), withdrawAmt);

        uint256 etherFiCashSafeBalAfter = weETH.balanceOf(etherFiCashSafe);

        assertEq(
            etherFiCashSafeBalAfter - etherFiCashSafeBalBefore,
            withdrawAmt
        );
    }

    function test_AdminWithdrawBorrowToken() public {
        uint256 withdrawAmt = 100e6;

        uint256 etherFiCashSafeBalBefore = usdc.balanceOf(etherFiCashSafe);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.AdminWithdrawFunds(address(usdc), withdrawAmt);
        debtManager.adminWithdrawFunds(address(usdc), withdrawAmt);

        uint256 etherFiCashSafeBalAfter = usdc.balanceOf(etherFiCashSafe);

        assertEq(
            etherFiCashSafeBalAfter - etherFiCashSafeBalBefore,
            withdrawAmt
        );
    }

    function test_CannotWithdrawMoreThanLiquidCollateralToken() public {
        IL2DebtManager.TokenData[] memory tokenData = debtManager
            .liquidCollateralAmounts();

        address tokenToWithdraw = tokenData[0].token;
        uint256 amountToWithdraw = tokenData[0].amount + 1;

        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.LiquidAmountLesserThanRequired.selector);
        debtManager.adminWithdrawFunds(tokenToWithdraw, amountToWithdraw);
    }

    function test_OnlyDefaultAdminCanWithdraw() public {
        vm.startPrank(alice);
        vm.expectRevert(
            buildAccessControlRevertData(
                alice,
                debtManager.DEFAULT_ADMIN_ROLE()
            )
        );
        debtManager.adminWithdrawFunds(address(usdc), 1);
        vm.stopPrank();
    }
}
