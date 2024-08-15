// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

        vm.startPrank(owner);
        weETH.safeIncreaseAllowance(address(debtManager), collateralAmt);
        debtManager.depositCollateral(address(weETH), collateralAmt);
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

    function test_FundsManagementOnAave() public {
        vm.startPrank(owner);

        ///// SUPPLY
        uint256 totalCollateralInAaveBefore = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weETH));
        assertEq(totalCollateralInAaveBefore, 0);

        debtManager.fundManagementOperation(
            uint8(IL2DebtManager.MarketOperationType.Supply),
            abi.encode(address(weETH), collateralAmt)
        );

        uint256 totalCollateralInAaveAfter = aaveV3Adapter.getCollateralBalance(
            address(debtManager),
            address(weETH)
        );
        assertEq(totalCollateralInAaveAfter, collateralAmt);

        ///// BORROW
        uint256 totalBorrowInAaveBefore = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveBefore, 0);

        uint256 borrowAmt = 1e6;
        debtManager.fundManagementOperation(
            uint8(IL2DebtManager.MarketOperationType.Borrow),
            abi.encode(address(usdc), borrowAmt)
        );

        uint256 totalBorrowInAaveAfter = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveAfter, borrowAmt);

        ///// REPAY
        if (!isFork(chainId)) {
            usdc.safeTransfer(address(debtManager), 10e6);
        }

        uint256 totalBorrowInAaveBeforeRepay = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveBeforeRepay, borrowAmt);

        debtManager.fundManagementOperation(
            uint8(IL2DebtManager.MarketOperationType.Repay),
            abi.encode(address(usdc), totalBorrowInAaveBeforeRepay)
        );
        uint256 totalBorrowInAaveAfterRepay = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveAfterRepay, 0);

        ///// WITHDRAW
        uint256 totalCollateralInAaveBeforeWithdraw = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weETH));
        assertEq(totalCollateralInAaveBeforeWithdraw, collateralAmt);

        debtManager.fundManagementOperation(
            uint8(IL2DebtManager.MarketOperationType.Withdraw),
            abi.encode(address(weETH), totalCollateralInAaveBeforeWithdraw)
        );

        uint256 totalCollateralInAaveAfterWithdraw = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weETH));
        assertEq(totalCollateralInAaveAfterWithdraw, 0);

        ///// SUPPLY AND BORROW

        uint256 totalCollateralInAaveBeforeSupplyAndBorrow = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weETH));
        assertEq(totalCollateralInAaveBeforeSupplyAndBorrow, 0);
        uint256 totalBorrowInAaveBeforeSupplyAndBorrow = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveBeforeSupplyAndBorrow, 0);

        debtManager.fundManagementOperation(
            uint8(IL2DebtManager.MarketOperationType.SupplyAndBorrow),
            abi.encode(address(weETH), collateralAmt, address(usdc), 1e6)
        );

        uint256 totalCollateralInAaveAfterSupplyAndBorrow = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weETH));
        assertEq(totalCollateralInAaveAfterSupplyAndBorrow, collateralAmt);
        uint256 totalBorrowInAaveAfterSupplyAndBorrow = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveAfterSupplyAndBorrow, 1e6);

        vm.stopPrank();
    }

    function test_OnlyAdminCanManageFunds() public {
        vm.startPrank(notOwner);
        vm.expectRevert(
            buildAccessControlRevertData(notOwner, debtManager.ADMIN_ROLE())
        );
        debtManager.fundManagementOperation(
            uint8(IL2DebtManager.MarketOperationType.Supply),
            abi.encode(address(weETH), collateralAmt)
        );

        vm.stopPrank();
    }
}
