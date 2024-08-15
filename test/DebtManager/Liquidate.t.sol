// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DebtManagerLiquidateTest is DebtManagerSetup {
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

        borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(alice);

        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();
    }

    function buildAccessControlRevertData(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                role
            );
    }

    function test_SetLiquidationThreshold() public {
        uint256 newThreshold = 70e18;
        vm.prank(owner);
        debtManager.setLiquidationThreshold(newThreshold);

        assertEq(debtManager.liquidationThreshold(), newThreshold);
    }

    function test_OnlyAdminCanSetLiquidationThreshold() public {
        uint256 newThreshold = 70e18;
        vm.startPrank(notOwner);
        vm.expectRevert(
            buildAccessControlRevertData(notOwner, debtManager.ADMIN_ROLE())
        );
        debtManager.setLiquidationThreshold(newThreshold);

        vm.stopPrank();
    }

    function test_Liquidate() public {
        vm.startPrank(owner);

        debtManager.setLiquidationThreshold(10e18);
        assertEq(debtManager.liquidatable(alice), true);
        debtManager.liquidate(alice);

        vm.stopPrank();

        uint256 aliceCollateralAfter = debtManager.getCollateralValueInUsdc(
            alice
        );
        uint256 aliceDebtAfter = debtManager.borrowingOf(alice);

        assertEq(aliceCollateralAfter, collateralValueInUsdc - borrowAmt);
        assertEq(aliceDebtAfter, 0);
    }

    function test_OnlyAdminCanLiquidate() public {
        vm.prank(owner);
        debtManager.setLiquidationThreshold(10e18);
        assertEq(debtManager.liquidatable(alice), true);
        vm.startPrank(notOwner);
        vm.expectRevert(
            buildAccessControlRevertData(notOwner, debtManager.ADMIN_ROLE())
        );
        debtManager.liquidate(alice);

        vm.stopPrank();
    }

    function test_CannotLiquidateIfNotLiquidatable() public {
        vm.startPrank(owner);
        assertEq(debtManager.liquidatable(alice), false);
        vm.expectRevert(IL2DebtManager.CannotLiquidateYet.selector);
        debtManager.liquidate(alice);

        vm.stopPrank();
    }
}
