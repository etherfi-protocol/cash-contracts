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

contract DebtManagerSupplyAndWithdrawTest is DebtManagerSetup {
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
        deal(address(usdc), notOwner, 1 ether);
        vm.startPrank(notOwner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), principle);
        debtManager.supply(notOwner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.supplierBalance(notOwner, address(usdc)),
            principle
        );

        uint256 earnings = _borrowAndRepay(principle);

        assertEq(
            debtManager.supplierBalance(notOwner, address(usdc)),
            principle + earnings
        );

        vm.prank(notOwner);
        debtManager.withdrawBorrowToken(address(usdc), earnings + principle);

        assertEq(debtManager.supplierBalance(notOwner, address(usdc)), 0);
    }

    function test_IssuesCorrectNumberOfSharesIfBorrowingFromAave() public {
        deal(address(usdc), alice, 1 ether);
        deal(address(usdc), notOwner, 1 ether);
        deal(address(weETH), alice, 1000 ether);

        uint256 collateralAmount = 0.01 ether;
        
        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);

        // All this is being borrowed from Aave since there is no supply in the contract
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(alice) / 2;
        debtManager.borrow(address(usdc), borrowAmt);

        uint256 supplyAmt = 1000e6;
        vm.startPrank(notOwner);
        usdc.approve(address(debtManager), supplyAmt);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), supplyAmt);
        debtManager.supply(notOwner, address(usdc), supplyAmt);
        vm.stopPrank();

        address newSupplier = makeAddr("newSupplier");
        deal(address(usdc), newSupplier, 1 ether);

        uint256 newSupplyAmt = 10000e6;
        vm.startPrank(newSupplier);
        usdc.approve(address(debtManager), newSupplyAmt);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(newSupplier, newSupplier, address(usdc), newSupplyAmt);
        debtManager.supply(newSupplier, address(usdc), newSupplyAmt);
        vm.stopPrank();
    }

    function test_CannotWithdrawLessThanMinShares() public {
        uint256 principle = debtManager.borrowTokenConfig(address(usdc)).minShares;

        deal(address(usdc), notOwner, 1 ether);

        vm.startPrank(notOwner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), principle);
        debtManager.supply(notOwner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.supplierBalance(notOwner, address(usdc)),
            principle
        );

        vm.prank(notOwner);
        vm.expectRevert(IL2DebtManager.SharesCannotBeLessThanMinShares.selector);
        debtManager.withdrawBorrowToken(address(usdc), principle - 1);
    }

    function test_SupplyTwice() public {
        uint256 principle = 0.01 ether;
        deal(address(usdc), notOwner, 1 ether);

        vm.startPrank(notOwner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), principle);
        debtManager.supply(notOwner, address(usdc), principle);
        vm.stopPrank();

        address newSupplier = makeAddr("newSupplier");

        deal(address(usdc), newSupplier, principle);
        
        vm.startPrank(newSupplier);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(newSupplier, newSupplier, address(usdc), principle);
        debtManager.supply(newSupplier, address(usdc), principle);
        vm.stopPrank();
    }

    function test_CanOnlySupplyBorrowTokens() public {
        vm.prank(alice);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.supply(owner, address(weETH), 1);
    }

    function test_UserSafeCannotSupply() public {
        address safe = makeAddr("safe");
        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(safe);

        vm.prank(alice);
        vm.expectRevert(IL2DebtManager.UserSafeCannotSupplyDebtTokens.selector);
        debtManager.supply(owner, address(usdc), 1);
    }

    function test_CannotWithdrawTokenThatWasNotSupplied() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.ZeroTotalBorrowTokensExcludingAave.selector);
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

        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(
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
