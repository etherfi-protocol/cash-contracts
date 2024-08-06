// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

error OwnableUnauthorizedAccount(address account);

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

    function test_UsdcTransferToCashMultiSig() public {
        uint256 amount = 1000e6;

        uint256 multiSigUsdcBalBefore = usdc.balanceOf(etherFiCashMultisig);

        vm.prank(etherFiCashMultisig);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.TransferUSDCForSpending(amount);
        aliceSafe.transfer(amount);

        uint256 multiSigUsdcBalAfter = usdc.balanceOf(etherFiCashMultisig);

        assertEq(
            aliceSafeUsdcBalanceBefore - usdc.balanceOf(address(aliceSafe)),
            amount
        );
        assertEq(multiSigUsdcBalAfter - multiSigUsdcBalBefore, amount);
    }

    function test_CannotTransferUsdcWhenBalanceIsInsufficient() public {
        uint256 amount = aliceSafeUsdcBalanceBefore + 1;
        vm.prank(alice);
        aliceSafe.updateSpendingLimit(amount);

        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.transfer(amount);
    }

    function test_OnlyCashMultiSigCanTransferUsdc() public {
        uint256 amount = 1000e6;
        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.transfer(amount);
    }

    function test_CannotTransferMoreUsdcThanSpendingLimit() public {
        uint256 amount = defaultSpendingLimit + 1;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(amount);
    }

    function test_SwapWeEthToUsdcAndTransfer() public {
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
            inputAmountWeETHToSwap,
            amountUsdcToSend
        );
        aliceSafe.swapAndTransfer(
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
        vm.expectRevert(IUserSafe.AmountGreaterThanUsdcReceived.selector);
        aliceSafe.swapAndTransfer(
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
            newInputAmt,
            outputMinUsdcAmount,
            newAmountUsdcToSend,
            swapData
        );
    }

    function test_CannotSwapWeEthToUsdcAndTransferIfBalanceIsInsufficient()
        public
    {
        uint256 inputAmountWeETHToSwap = aliceSafeWeETHBalanceBefore + 1 ether;
        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.swapAndTransfer(inputAmountWeETHToSwap, 0, 0, hex"");
    }

    function test_TransferWeETHToDebtManager() public {
        uint256 amount = 1 ether;

        uint256 debtManagerWeEthBalanceBefore = weETH.balanceOf(
            etherFiCashDebtManager
        );

        vm.prank(etherFiCashDebtManager);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.TransferWeETHAsCollateral(amount);
        aliceSafe.transferWeETHToDebtManager(amount);

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

    function test_CannotTransferWeETHToDebtManagerIfSpendingLimitIsBreached()
        public
    {
        uint256 amount = 10 ether;

        vm.prank(etherFiCashDebtManager);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transferWeETHToDebtManager(amount);
    }

    function test_OnlyDebtManagerCanTransferWeETHToDebtManager() public {
        uint256 amount = 1 ether;

        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.transferWeETHToDebtManager(amount);
    }

    function test_CannotTransferWeETHToDebtManagerIfBalanceIsInsufficient()
        public
    {
        uint256 amount = aliceSafeWeETHBalanceBefore + 1;
        vm.prank(alice);
        aliceSafe.updateSpendingLimit(aliceSafeWeETHBalanceBefore + 1);

        vm.prank(etherFiCashDebtManager);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.transferWeETHToDebtManager(amount);
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
