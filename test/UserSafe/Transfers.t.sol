// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC20, UserSafeSetup} from "./UserSafeSetup.sol";

contract UserSafeTransfersTest is UserSafeSetup {
    uint256 aliceSafeUsdcBalanceBefore;
    uint256 aliceSafeWeETHBalanceBefore;
    function setUp() public override {
        super.setUp();

        aliceSafeUsdcBalanceBefore = 1 ether;
        aliceSafeWeETHBalanceBefore = 100 ether;

        deal(address(usdc), address(aliceSafe), aliceSafeUsdcBalanceBefore);
        deal(address(weETH), address(aliceSafe), aliceSafeWeETHBalanceBefore);
    }

    function test_TransferForSpendingToCashMultiSig() public {
        uint256 amount = 1000e6;

        uint256 multiSigUsdcBalBefore = usdc.balanceOf(etherFiCashMultisig);

        vm.prank(etherFiCashMultisig);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.TransferForSpending(address(usdc), amount);
        aliceSafe.transfer(address(usdc), amount);

        uint256 multiSigUsdcBalAfter = usdc.balanceOf(etherFiCashMultisig);

        assertEq(
            aliceSafeUsdcBalanceBefore - usdc.balanceOf(address(aliceSafe)),
            amount
        );
        assertEq(multiSigUsdcBalAfter - multiSigUsdcBalBefore, amount);
    }

    function test_CannotTransferForSpendingWhenBalanceIsInsufficient() public {
        uint256 amount = aliceSafeUsdcBalanceBefore + 1;
        vm.prank(alice);
        aliceSafe.updateSpendingLimit(amount);

        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_OnlyCashMultiSigCanTransferForSpending() public {
        uint256 amount = 1000e6;
        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_CannotTransferMoreThanSpendingLimit() public {
        uint256 amount = defaultSpendingLimit + 1;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_SwapAndTransferForSpending() public {
        uint256 inputAmountWeETHToSwap = 1 ether;
        uint256 outputMinUsdcAmount = 1000e6;
        uint256 amountUsdcToSend = 100e6;
        bytes memory swapData = getQuoteOneInch(
            address(swapper),
            address(aliceSafe),
            address(weETH),
            address(usdc),
            inputAmountWeETHToSwap
        );

        uint256 cashMultiSigUsdcBalBefore = usdc.balanceOf(etherFiCashMultisig);

        vm.prank(etherFiCashMultisig);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.SwapTransferForSpending(
            address(weETH),
            inputAmountWeETHToSwap,
            address(usdc),
            amountUsdcToSend
        );
        aliceSafe.swapAndTransfer(
            address(weETH),
            address(usdc),
            inputAmountWeETHToSwap,
            outputMinUsdcAmount,
            amountUsdcToSend,
            swapData
        );

        uint256 cashMultiSigUsdcBalAfter = usdc.balanceOf(etherFiCashMultisig);

        assertEq(
            cashMultiSigUsdcBalAfter - cashMultiSigUsdcBalBefore,
            amountUsdcToSend
        );
        assertEq(
            aliceSafeWeETHBalanceBefore - weETH.balanceOf(address(aliceSafe)),
            inputAmountWeETHToSwap
        );

        // test_CannotSwapWeEthToUsdcAndTransferIfAmountReceivedIsLess
        vm.prank(alice);
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Monthly),
            100000e6
        );

        uint256 newAmountUsdcToSend = 10000e6;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.TransferAmountGreaterThanReceived.selector);
        aliceSafe.swapAndTransfer(
            address(weETH),
            address(usdc),
            inputAmountWeETHToSwap,
            outputMinUsdcAmount,
            newAmountUsdcToSend,
            swapData
        );

        // test_CannotGoOverSpendingLimit
        vm.prank(alice);
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Monthly),
            1000e6
        );

        uint256 newInputAmt = 5 ether;
        newAmountUsdcToSend = aliceSafe.spendingLimit().spendingLimit + 1;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.swapAndTransfer(
            address(weETH),
            address(usdc),
            newInputAmt,
            outputMinUsdcAmount,
            newAmountUsdcToSend,
            swapData
        );
    }

    function test_CannotSwapAndTransferIfBalanceIsInsufficient() public {
        uint256 inputAmountWeETHToSwap = aliceSafeWeETHBalanceBefore + 1 ether;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.swapAndTransfer(
            address(weETH),
            address(usdc),
            inputAmountWeETHToSwap,
            0,
            0,
            hex""
        );
    }

    function test_TransferFundsToDebtManager() public {
        uint256 amount = 1 ether;

        uint256 debtManagerWeEthBalanceBefore = weETH.balanceOf(
            etherFiCashDebtManager
        );

        vm.prank(etherFiCashDebtManager);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.TransferCollateral(address(weETH), amount);
        aliceSafe.transferFundsToDebtManager(address(weETH), amount);

        uint256 debtManagerWeEthBalanceAfter = weETH.balanceOf(
            etherFiCashDebtManager
        );

        assertEq(
            aliceSafeWeETHBalanceBefore - weETH.balanceOf(address(aliceSafe)),
            amount
        );
        assertEq(
            debtManagerWeEthBalanceAfter - debtManagerWeEthBalanceBefore,
            amount
        );
    }

    function test_CannotTransferFundsToDebtManagerIfSpendingLimitIsBreached()
        public
    {
        uint256 amount = 10 ether;

        vm.prank(etherFiCashDebtManager);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transferFundsToDebtManager(address(weETH), amount);
    }

    function test_OnlyDebtManagerCanTransferFundsForCollateral() public {
        uint256 amount = 1 ether;

        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.transferFundsToDebtManager(address(weETH), amount);
    }

    function test_CannotTransferFundsToDebtManagerIfBalanceIsInsufficient()
        public
    {
        uint256 amount = aliceSafeWeETHBalanceBefore + 1;
        vm.prank(alice);
        aliceSafe.updateSpendingLimit(aliceSafeWeETHBalanceBefore + 1);

        vm.prank(etherFiCashDebtManager);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.transferFundsToDebtManager(address(weETH), amount);
    }

    function test_CannotTransferUnsupportedTokensForSpending() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        uint256 amount = 1 ether;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.transfer(unsupportedToken, amount);
    }

    function test_CannotSwapAndTransferUnsupportedTokensForSpending() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        uint256 amount = 1 ether;

        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.swapAndTransfer(
            unsupportedToken,
            address(usdc),
            amount,
            0,
            0,
            hex""
        );
    }

    function test_CannotTransferUnsupportedTokensForCollateral() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        uint256 amount = 1 ether;
        vm.prank(etherFiCashDebtManager);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.transferFundsToDebtManager(unsupportedToken, amount);
    }

    function getQuoteOneInch(
        address from,
        address to,
        address srcToken,
        address dstToken,
        uint256 amount
    ) internal returns (bytes memory data) {
        string[] memory inputs = new string[](8);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/getQuote1Inch.ts";
        inputs[3] = vm.toString(from);
        inputs[4] = vm.toString(to);
        inputs[5] = vm.toString(srcToken);
        inputs[6] = vm.toString(dstToken);
        inputs[7] = vm.toString(amount);

        return vm.ffi(inputs);
    }
}
