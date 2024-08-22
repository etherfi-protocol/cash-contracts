// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {Test, console, stdError} from "forge-std/Test.sol";

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// import {L2DebtManager} from "../src/L2DebtManager.sol";

// contract USDC is ERC20 {
//     constructor(string memory name, string memory symbol) ERC20(name, symbol) {
//         _mint(msg.sender, 1000000 * 10 ** decimals());
//     }

//     function decimals() public view virtual override returns (uint8) {
//         return 6;
//     }
// }

// contract EETH is ERC20 {
//     constructor(string memory name, string memory symbol) ERC20(name, symbol) {
//         _mint(msg.sender, 1000000 * 10 ** decimals());
//     }

//     function decimals() public view virtual override returns (uint8) {
//         return 18;
//     }
// }

// contract L2DebtManagerTest is Test {
//     ERC20 public eEth;
//     ERC20 public usdc;

//     L2DebtManager public l2DebtManager;
//     address public etherFiCashSafe = vm.addr(100000);

//     address owner = vm.addr(1);
//     address alice = vm.addr(2);
//     address bob = vm.addr(3);

//     function setUp() public {
//         vm.startPrank(owner);

//         eEth = ERC20(new EETH("EETH", "EETH"));
//         usdc = ERC20(new USDC("USDC", "USDC"));
//         eEth.transfer(alice, 1000 ether);
//         usdc.transfer(alice, 1000 * 1e6);

//         l2DebtManager = new L2DebtManager(
//             address(eEth),
//             address(usdc),
//             etherFiCashSafe
//         );
//         l2DebtManager.setLiquidationThreshold(60_00); // 60%
//         l2DebtManager.setEEthPriceInUSDC(2000 * 1e6); // 2000 USDC
//         vm.stopPrank();
//     }

//     function test_depositEETH() public {
//         vm.startPrank(alice);

//         assertEq(l2DebtManager.totalCollateralAmount(), 0);
//         assertEq(eEth.balanceOf(address(l2DebtManager)), 0);
//         assertEq(l2DebtManager.collateralOf(alice), 0);

//         eEth.approve(address(l2DebtManager), 1 ether);
//         l2DebtManager.depositEETH(alice, 1 ether);

//         assertEq(l2DebtManager.totalCollateralAmount(), 1 ether);
//         assertEq(eEth.balanceOf(address(l2DebtManager)), 1 ether);
//         assertEq(l2DebtManager.collateralOf(alice), 1 ether);

//         vm.stopPrank();
//     }

//     function test_supplyUSDC() public {
//         vm.startPrank(owner);

//         assertEq(usdc.balanceOf(address(l2DebtManager)), 0);

//         usdc.approve(address(l2DebtManager), 100000 * 1e6);
//         l2DebtManager.supplyUSDC(100000 * 1e6);

//         assertEq(usdc.balanceOf(address(l2DebtManager)), 100000 * 1e6);
//         vm.stopPrank();
//     }

//     function test_borrowUSDC() public {
//         test_depositEETH();
//         test_supplyUSDC();

//         vm.startPrank(alice);

//         assertEq(l2DebtManager.totalBorrowingAmount(), 0);
//         assertEq(l2DebtManager.borrowingOf(alice), 0);

//         uint256 beforeUsdcBalance = usdc.balanceOf(address(l2DebtManager));
//         uint256 beforeEtherFiCashSafeBalance = usdc.balanceOf(etherFiCashSafe);
//         uint256 beforeRemainingBorrowingCapacity = l2DebtManager
//             .remainingBorrowingCapacityInUSDC(alice);

//         // Alice spents 1000 USDC, which borrows 1000 USDC and transfers it to the etherFiCashSafe
//         uint256 borrowAmount = 1000 * 1e6;
//         l2DebtManager.borrowUSDC(borrowAmount);

//         assertEq(l2DebtManager.totalBorrowingAmount(), borrowAmount);
//         assertEq(
//             usdc.balanceOf(address(l2DebtManager)),
//             beforeUsdcBalance - borrowAmount
//         );
//         assertEq(l2DebtManager.borrowingOf(alice), borrowAmount);
//         assertEq(
//             usdc.balanceOf(etherFiCashSafe),
//             beforeEtherFiCashSafeBalance + borrowAmount
//         );
//         assertEq(
//             l2DebtManager.remainingBorrowingCapacityInUSDC(alice),
//             beforeRemainingBorrowingCapacity - borrowAmount
//         );
//     }

//     // Borrow 1000 USDC
//     // Repay it with 500 USDC
//     function test_repayWithUSDC() public {
//         test_borrowUSDC();

//         vm.startPrank(alice);
//         uint256 beforeLiquidUsdcAmount = l2DebtManager.liquidUsdcAmount();
//         uint256 beforeLiquidEEthAmount = l2DebtManager.liquidEEthAmount();
//         uint256 beforeBorrowing = l2DebtManager.borrowingOf(alice);
//         uint256 beforeUsdcBalance = usdc.balanceOf(address(l2DebtManager));

//         uint256 repayAmount = 500 * 1e6; // 500 USDC
//         usdc.approve(address(l2DebtManager), repayAmount);
//         l2DebtManager.repayWithUSDC(repayAmount);

//         assertEq(
//             l2DebtManager.liquidUsdcAmount(),
//             beforeLiquidUsdcAmount + 2 * repayAmount
//         );
//         assertEq(l2DebtManager.liquidEEthAmount(), beforeLiquidEEthAmount);

//         assertEq(
//             l2DebtManager.totalBorrowingAmount(),
//             beforeBorrowing - repayAmount
//         );
//         assertEq(
//             usdc.balanceOf(address(l2DebtManager)),
//             beforeUsdcBalance + repayAmount
//         );
//         assertEq(
//             l2DebtManager.borrowingOf(alice),
//             beforeBorrowing - repayAmount
//         );
//     }

//     // Borrow 1000 USDC
//     // Repay it with the equivalent amount of eETH
//     function test_repayWithEETH() public {
//         test_borrowUSDC();

//         vm.startPrank(alice);
//         uint256 beforeLiquidUsdcAmount = l2DebtManager.liquidUsdcAmount();
//         uint256 beforeLiquidEEthAmount = l2DebtManager.liquidEEthAmount();
//         uint256 beforeBorrowing = l2DebtManager.borrowingOf(alice);
//         uint256 beforeCollateral = l2DebtManager.collateralOf(alice);
//         uint256 beforeUsdcBalance = usdc.balanceOf(address(l2DebtManager));

//         uint256 repayAmount = 500 * 1e6; // 500 USDC
//         uint256 repayAmountInEEth = l2DebtManager.getCollateralAmountForDebt(
//             repayAmount
//         );
//         l2DebtManager.repayWithEETH(repayAmount);

//         assertEq(
//             l2DebtManager.liquidUsdcAmount(),
//             beforeLiquidUsdcAmount + repayAmount
//         );
//         assertEq(
//             l2DebtManager.liquidEEthAmount(),
//             beforeLiquidEEthAmount + repayAmountInEEth
//         );

//         assertEq(
//             l2DebtManager.totalBorrowingAmount(),
//             beforeBorrowing - repayAmount
//         );
//         assertEq(usdc.balanceOf(address(l2DebtManager)), beforeUsdcBalance);
//         assertEq(
//             l2DebtManager.borrowingOf(alice),
//             beforeBorrowing - repayAmount
//         );
//         assertEq(
//             l2DebtManager.collateralOf(alice),
//             beforeCollateral - repayAmountInEEth
//         );
//     }

//     function test_liquidation() public {
//         // Alice deposits 1 eETH
//         // and borrows 1000 USDC
//         test_borrowUSDC();

//         // Suddenly, the price of eETH changed from 2000 USDC to 1500 USDC
//         // Alice is in trouble
//         vm.startPrank(owner);
//         l2DebtManager.setEEthPriceInUSDC(1500 * 1e6);
//         vm.stopPrank();

//         assertEq(l2DebtManager.collateralOf(alice), 1 ether);
//         assertEq(l2DebtManager.borrowingOf(alice), 1000 * 1e6);
//         assertEq(l2DebtManager.debtRatioOf(alice), 66_66); // 66.66 % = borrowed 1000 USDC with 1500 USDC worth eETH
//         assertEq(l2DebtManager.remainingBorrowingCapacityInUSDC(alice), 0);
//         assertEq(l2DebtManager.liquidatable(alice), true);

//         l2DebtManager.liquidate(alice);

//         assertEq(l2DebtManager.collateralOf(alice), 0.333333333333333334 ether); // 0.3333333 ether is left
//         assertEq(l2DebtManager.borrowingOf(alice), 0); // cleaned
//         assertEq(l2DebtManager.debtRatioOf(alice), 0);
//         assertEq(
//             l2DebtManager.remainingBorrowingCapacityInUSDC(alice),
//             300 * 1e6
//         ); // 60% of 500 USDC = 300 USDC
//         assertEq(l2DebtManager.liquidatable(alice), false);
//     }

//     function test_borrow_above_liquidation_threshold_fails() public {
//         test_depositEETH();
//         test_supplyUSDC();

//         vm.startPrank(alice);

//         // Alice borrows 10000 USDC
//         uint256 borrowAmount = 10000 * 1e6;

//         // that is above the max borrowing capacity
//         assertGt(
//             borrowAmount,
//             l2DebtManager.remainingBorrowingCapacityInUSDC(alice)
//         );

//         vm.expectRevert("NOT_ENOUGH_COLLATERAL");
//         l2DebtManager.borrowUSDC(borrowAmount);
//     }
// }
