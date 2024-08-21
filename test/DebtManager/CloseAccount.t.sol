// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract DebtManagerCloseAccountTest is DebtManagerSetup {
    using SafeERC20 for IERC20;

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
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);

        borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(alice) / 2;

        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();
    }

    function test_CloseAccount() public {
        IL2DebtManager.TokenData[]
            memory tokenData = new IL2DebtManager.TokenData[](1);
        tokenData[0] = IL2DebtManager.TokenData({
            token: address(weETH),
            amount: debtManager.convertUsdcToCollateralToken(
                address(weETH),
                (debtManager.getCollateralValueInUsdc(alice) - borrowAmt)
            )
        });

        uint256 aliceDebtBefore = debtManager.borrowingOf(alice);
        uint256 aliceCollateralBefore = debtManager.getCollateralValueInUsdc(
            alice
        );

        // Can easily withdraw the amount till liquidation threshold
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.AccountClosed(alice, borrowAmt, tokenData);
        debtManager.closeAccount();

        uint256 aliceDebtAfter = debtManager.borrowingOf(alice);
        uint256 aliceCollateralAfter = debtManager.getCollateralValueInUsdc(
            alice
        );
        assertEq(aliceDebtBefore, borrowAmt);
        assertEq(aliceDebtAfter, 0);
        assertEq(
            aliceCollateralBefore,
            debtManager.convertCollateralTokenToUsdc(
                address(weETH),
                collateralAmount
            )
        );
        assertEq(
            aliceCollateralAfter,
            debtManager.convertCollateralTokenToUsdc(
                address(weETH),
                collateralAmount
            ) - borrowAmt
        );
    }
}
