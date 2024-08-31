// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
// import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
// import {AaveLib} from "../../src/libraries/AaveLib.sol";
// import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
// import {stdStorage, StdStorage} from "forge-std/Test.sol";
// import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

// contract DebtManagerFundManagementTest is DebtManagerSetup {
//     using SafeERC20 for IERC20;

//     uint256 collateralAmt = 0.01 ether;

//     function setUp() public override {
//         super.setUp();

//         deal(address(weETH), address(owner), 1000 ether);
//         deal(address(usdc), address(owner), 1 ether);

//         vm.startPrank(owner);
//         weETH.safeIncreaseAllowance(address(debtManager), collateralAmt);
//         debtManager.depositCollateral(address(weETH), owner, collateralAmt);
//         vm.stopPrank();
//     }

//     function test_supplier() public {
//         uint256 principle = 0.01 ether;

//         vm.startPrank(owner);
//         usdc.forceApprove(address(debtManager), principle);

//         vm.expectEmit(true, true, true, true);
//         emit IL2DebtManager.Supplied(owner, owner, address(usdc), principle);
//         debtManager.supply(owner, address(usdc), principle);
//         vm.stopPrank();

//         assertEq(
//             debtManager.withdrawableBorrowToken(owner, address(usdc)),
//             principle
//         );

//         uint256 earnings = _borrowAndRepay(principle);

//         assertEq(
//             debtManager.withdrawableBorrowToken(owner, address(usdc)),
//             principle + earnings
//         );

//         vm.startPrank(owner);
//         debtManager.withdrawBorrowToken(address(usdc), earnings + principle);

//         assertEq(debtManager.withdrawableBorrowToken(owner, address(usdc)), 0);
//     }

//     function test_FundsManagementOnAave() public {
//         vm.startPrank(owner);

//         ///// SUPPLY
//         uint256 totalCollateralInAaveBefore = aaveV3Adapter
//             .getCollateralBalance(address(debtManager), address(weETH));
//         assertEq(totalCollateralInAaveBefore, 0);

//         debtManager.fundManagementOperation(
//             uint8(AaveLib.MarketOperationType.Supply),
//             abi.encode(address(weETH), collateralAmt)
//         );

//         uint256 totalCollateralInAaveAfter = aaveV3Adapter.getCollateralBalance(
//             address(debtManager),
//             address(weETH)
//         );
//         assertEq(totalCollateralInAaveAfter, collateralAmt);

//         ///// BORROW
//         uint256 totalBorrowInAaveBefore = aaveV3Adapter.getDebt(
//             address(debtManager),
//             address(usdc)
//         );
//         assertEq(totalBorrowInAaveBefore, 0);

//         uint256 borrowAmt = 1e6;
//         debtManager.fundManagementOperation(
//             uint8(AaveLib.MarketOperationType.Borrow),
//             abi.encode(address(usdc), borrowAmt)
//         );

//         uint256 totalBorrowInAaveAfter = aaveV3Adapter.getDebt(
//             address(debtManager),
//             address(usdc)
//         );
//         assertEq(totalBorrowInAaveAfter, borrowAmt);

//         ///// REPAY
//         if (!isFork(chainId)) {
//             usdc.safeTransfer(address(debtManager), 10e6);
//         }

//         uint256 totalBorrowInAaveBeforeRepay = aaveV3Adapter.getDebt(
//             address(debtManager),
//             address(usdc)
//         );
//         assertEq(totalBorrowInAaveBeforeRepay, borrowAmt);

//         debtManager.fundManagementOperation(
//             uint8(AaveLib.MarketOperationType.Repay),
//             abi.encode(address(usdc), totalBorrowInAaveBeforeRepay)
//         );
//         uint256 totalBorrowInAaveAfterRepay = aaveV3Adapter.getDebt(
//             address(debtManager),
//             address(usdc)
//         );
//         assertEq(totalBorrowInAaveAfterRepay, 0);

//         ///// WITHDRAW
//         uint256 totalCollateralInAaveBeforeWithdraw = aaveV3Adapter
//             .getCollateralBalance(address(debtManager), address(weETH));
//         assertEq(totalCollateralInAaveBeforeWithdraw, collateralAmt);

//         debtManager.fundManagementOperation(
//             uint8(AaveLib.MarketOperationType.Withdraw),
//             abi.encode(address(weETH), totalCollateralInAaveBeforeWithdraw)
//         );

//         uint256 totalCollateralInAaveAfterWithdraw = aaveV3Adapter
//             .getCollateralBalance(address(debtManager), address(weETH));
//         assertEq(totalCollateralInAaveAfterWithdraw, 0);

//         ///// SUPPLY AND BORROW

//         uint256 totalCollateralInAaveBeforeSupplyAndBorrow = aaveV3Adapter
//             .getCollateralBalance(address(debtManager), address(weETH));
//         assertEq(totalCollateralInAaveBeforeSupplyAndBorrow, 0);
//         uint256 totalBorrowInAaveBeforeSupplyAndBorrow = aaveV3Adapter.getDebt(
//             address(debtManager),
//             address(usdc)
//         );
//         assertEq(totalBorrowInAaveBeforeSupplyAndBorrow, 0);

//         debtManager.fundManagementOperation(
//             uint8(AaveLib.MarketOperationType.SupplyAndBorrow),
//             abi.encode(address(weETH), collateralAmt, address(usdc), 1e6)
//         );

//         uint256 totalCollateralInAaveAfterSupplyAndBorrow = aaveV3Adapter
//             .getCollateralBalance(address(debtManager), address(weETH));
//         assertEq(totalCollateralInAaveAfterSupplyAndBorrow, collateralAmt);
//         uint256 totalBorrowInAaveAfterSupplyAndBorrow = aaveV3Adapter.getDebt(
//             address(debtManager),
//             address(usdc)
//         );
//         assertEq(totalBorrowInAaveAfterSupplyAndBorrow, 1e6);

//         vm.stopPrank();
//     }

//     function test_OnlyAdminCanManageFunds() public {
//         vm.startPrank(notOwner);
//         vm.expectRevert(
//             buildAccessControlRevertData(notOwner, debtManager.ADMIN_ROLE())
//         );
//         debtManager.fundManagementOperation(
//             uint8(AaveLib.MarketOperationType.Supply),
//             abi.encode(address(weETH), collateralAmt)
//         );

//         vm.stopPrank();
//     }

//     function _borrowAndRepay(
//         uint256 collateralAmount
//     ) internal returns (uint256) {
//         deal(address(usdc), alice, 1 ether);
//         deal(address(weETH), alice, 1000 ether);

//         vm.startPrank(alice);
//         weETH.safeIncreaseAllowance(address(debtManager), collateralAmount);
//         debtManager.depositCollateral(address(weETH), alice, collateralAmount);

//         uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
//             alice
//         ) / 2;
//         debtManager.borrow(address(usdc), borrowAmt);

//         // 1 day after, there should be some interest accumulated
//         vm.warp(block.timestamp + 24 * 60 * 60);
//         uint256 repayAmt = debtManager.borrowingOf(alice, address(usdc));

//         usdc.forceApprove(address(debtManager), repayAmt);
//         debtManager.repay(alice, address(usdc), repayAmt);
//         vm.stopPrank();

//         return repayAmt - borrowAmt;
//     }

//     function _convertBorrowToShare(
//         address borrowToken,
//         uint256 amount
//     ) internal view returns (uint256) {
//         return
//             (amount * debtManager.ONE_SHARE()) /
//             IERC20Metadata(borrowToken).decimals();
//     }

//     function _convertShareToBorrow(
//         address borrowToken,
//         uint256 amount
//     ) internal view returns (uint256) {
//         return
//             (amount * IERC20Metadata(borrowToken).decimals()) /
//             debtManager.ONE_SHARE();
//     }
// }
