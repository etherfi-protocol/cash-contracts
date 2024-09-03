// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe, UserSafeLib} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup, MockPriceProvider, PriceProvider, MockERC20} from "./UserSafeSetup.t.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";

contract UserSafeAaveInteractionsTest is UserSafeSetup {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    IERC20 weth;

    function setUp() public override {
        super.setUp();

        if (!isFork(chainId))
            weth = IERC20(address(new MockERC20("WETH", "WETH", 18)));
        else weth = IERC20(chainConfig.weth);

        vm.prank(owner);
        cashDataProvider.supportCollateralToken(address(weth));
        deal(address(weth), address(aliceSafe), 100 ether);

        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd))
        );

        vm.prank(owner);
        cashDataProvider.setPriceProvider(address(priceProvider));
    }

    function test_AddCollateralAndBorrow() public {
        if (isFork(chainId)) {
            address collateralToken = address(weth);
            uint256 collateralAmount = 0.01 ether;

            address borrowToken = address(usdc);
            uint256 borrowAmount = 1e6;

            uint256 collateralTokenBalBefore = IERC20(collateralToken)
                .balanceOf(address(aliceSafe));
            uint256 borrowTokenBalBefore = IERC20(borrowToken).balanceOf(
                address(aliceSafe)
            );

            vm.prank(etherFiWallet);
            vm.expectEmit(true, true, true, true);
            emit IUserSafe.AddCollateral(collateralToken, collateralAmount);
            vm.expectEmit(true, true, true, true);
            emit IUserSafe.Borrow(borrowToken, borrowAmount);
            aliceSafe.addCollateralAndBorrow(
                collateralToken,
                collateralAmount,
                borrowToken,
                borrowAmount
            );

            uint256 collateralTokenBalAfter = IERC20(collateralToken).balanceOf(
                address(aliceSafe)
            );
            uint256 borrowTokenBalAfter = IERC20(borrowToken).balanceOf(
                address(aliceSafe)
            );

            assertEq(
                collateralTokenBalBefore - collateralTokenBalAfter,
                collateralAmount
            );
            assertEq(borrowTokenBalAfter - borrowTokenBalBefore, borrowAmount);
        }
    }

    function test_FullFlow() public {
        if (isFork(chainId)) {
            test_AddCollateral();

            vm.warp(block.timestamp + 10000);
            test_Borrow();

            vm.warp(block.timestamp + 10000);
            test_Repay();

            vm.warp(block.timestamp + 10000);
            test_WithdrawCollateral();
        }
    }

    function test_CannotAddCollateralIfCollateralLimitIsBreached() public {
        address collateralToken = address(weth);
        uint256 collateralAmount = ((collateralLimit + 1e6) * 1 ether) /
            priceProvider.price(address(weth));

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededCollateralLimit.selector);
        aliceSafe.addCollateral(collateralToken, collateralAmount);
    }

    function test_CannotAddCollateralIfTokenIsNotACollateralToken() public {
        address collateralToken = address(usdc);
        uint256 collateralAmount = 1;

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.addCollateral(collateralToken, collateralAmount);
    }

    function test_CannotBorrowIfSpendingLimitIsBreached() public {
        address borrowToken = address(usdc);
        uint256 borrowAmount = defaultSpendingLimit + 1;

        test_AddCollateral();

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.borrow(borrowToken, borrowAmount);
    }

    function test_CannotBorrowIfTokenIsNotABorrowToken() public {
        address borrowToken = address(weth);
        uint256 borrowAmount = 1;

        test_AddCollateral();

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.borrow(borrowToken, borrowAmount);
    }

    function test_AddCollateral() internal {
        address collateralToken = address(weth);
        uint256 collateralAmount = 0.01 ether;

        uint256 collateralTokenBalBefore = IERC20(collateralToken).balanceOf(
            address(aliceSafe)
        );

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.AddCollateral(collateralToken, collateralAmount);
        aliceSafe.addCollateral(collateralToken, collateralAmount);

        uint256 collateralTokenBalAfter = IERC20(collateralToken).balanceOf(
            address(aliceSafe)
        );

        if (isFork(chainId)) {
            assertEq(
                collateralTokenBalBefore - collateralTokenBalAfter,
                collateralAmount
            );

            (, uint256 totalCollateral) = aliceSafe.getTotalCollateral();
            assertGt(totalCollateral, 0);
        }
    }

    function test_Borrow() internal {
        address borrowToken = address(usdc);
        uint256 borrowAmount = 1e6;

        uint256 borrowTokenBalBefore = IERC20(borrowToken).balanceOf(
            address(aliceSafe)
        );

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.Borrow(borrowToken, borrowAmount);
        aliceSafe.borrow(borrowToken, borrowAmount);

        uint256 borrowTokenBalAfter = IERC20(borrowToken).balanceOf(
            address(aliceSafe)
        );

        assertEq(borrowTokenBalAfter - borrowTokenBalBefore, borrowAmount);
    }

    function test_Repay() internal {
        address repayToken = address(usdc);
        uint256 repayAmount = aaveV3Adapter.getDebt(
            address(aliceSafe),
            repayToken
        );
        deal(repayToken, address(aliceSafe), repayAmount);

        uint256 repayTokenBalBefore = IERC20(repayToken).balanceOf(
            address(aliceSafe)
        );

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.Repay(repayToken, repayAmount);
        aliceSafe.repay(repayToken, repayAmount);

        uint256 repayTokenBalAfter = IERC20(repayToken).balanceOf(
            address(aliceSafe)
        );

        assertEq(repayTokenBalBefore - repayTokenBalAfter, repayAmount);
    }

    function test_WithdrawCollateral() internal {
        address collateralToken = address(weth);
        uint256 collateralAmount = aaveV3Adapter.getCollateralBalance(
            address(aliceSafe),
            collateralToken
        );

        uint256 collateralTokenBalBefore = IERC20(collateralToken).balanceOf(
            address(aliceSafe)
        );

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawCollateral(collateralToken, collateralAmount);
        aliceSafe.withdrawCollateral(collateralToken, collateralAmount);

        uint256 collateralTokenBalAfter = IERC20(collateralToken).balanceOf(
            address(aliceSafe)
        );

        assertEq(
            collateralTokenBalAfter - collateralTokenBalBefore,
            collateralAmount
        );

        (, uint256 totalCollateral) = aliceSafe.getTotalCollateral();
        assertEq(totalCollateral, 0);
    }
}
