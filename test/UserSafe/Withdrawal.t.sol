// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

contract UserSafeWithdrawalTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_RequestWithdrawal() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        weETH.transfer(address(aliceSafe), amounts[1]);

        uint256 finalizeTime = block.timestamp +
            cashDataProvider.withdrawalDelay();

        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawalRequested(
            tokens,
            amounts,
            recipient,
            finalizeTime
        );
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);

        UserSafe.WithdrawalData memory pendingWithdrawalRequest = aliceSafe
            .pendingWithdrawalRequest();
        assertEq(pendingWithdrawalRequest.tokens.length, 2);
        assertEq(pendingWithdrawalRequest.tokens[0], tokens[0]);
        assertEq(pendingWithdrawalRequest.tokens[1], tokens[1]);

        assertEq(pendingWithdrawalRequest.amounts.length, 2);
        assertEq(pendingWithdrawalRequest.amounts[0], amounts[0]);
        assertEq(pendingWithdrawalRequest.amounts[1], amounts[1]);

        assertEq(pendingWithdrawalRequest.recipient, recipient);
        assertEq(pendingWithdrawalRequest.finalizeTime, finalizeTime);

        vm.stopPrank();
    }

    function test_OnlyOwnerCanRequestWithdrawal() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerLib.OnlyOwner.selector));
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);
    }

    function test_RequestWithdrawalWithPermit() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        weETH.transfer(address(aliceSafe), amounts[1]);
        vm.stopPrank();

        uint256 finalizeTime = block.timestamp +
            cashDataProvider.withdrawalDelay();
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.REQUEST_WITHDRAWAL_METHOD(),
                block.chainid,
                address(aliceSafe),
                tokens,
                amounts,
                recipient,
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        UserSafe.WithdrawalData
            memory pendingWithdrawalRequestBefore = aliceSafe
                .pendingWithdrawalRequest();
        assertEq(pendingWithdrawalRequestBefore.tokens.length, 0);

        vm.prank(notOwner);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawalRequested(
            tokens,
            amounts,
            recipient,
            finalizeTime
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.requestWithdrawalWithPermit(
            tokens,
            amounts,
            recipient,
            nonce,
            signature
        );

        UserSafe.WithdrawalData memory pendingWithdrawalRequestAfter = aliceSafe
            .pendingWithdrawalRequest();

        assertEq(pendingWithdrawalRequestAfter.tokens.length, 2);
        assertEq(pendingWithdrawalRequestAfter.tokens[0], tokens[0]);
        assertEq(pendingWithdrawalRequestAfter.tokens[1], tokens[1]);

        assertEq(pendingWithdrawalRequestAfter.amounts.length, 2);
        assertEq(pendingWithdrawalRequestAfter.amounts[0], amounts[0]);
        assertEq(pendingWithdrawalRequestAfter.amounts[1], amounts[1]);

        assertEq(pendingWithdrawalRequestAfter.recipient, recipient);
        assertEq(pendingWithdrawalRequestAfter.finalizeTime, finalizeTime);
    }

    function test_ProcessWithdrawals() external {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        weETH.transfer(address(aliceSafe), amounts[1]);

        uint256 finalizeTime = block.timestamp +
            cashDataProvider.withdrawalDelay();
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);

        uint256 recipientUsdcBalBefore = usdc.balanceOf(recipient);
        uint256 recipientWeETHBalBefore = usdc.balanceOf(recipient);

        vm.warp(finalizeTime);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawalProcessed(tokens, amounts, recipient);
        aliceSafe.processWithdrawal();

        uint256 recipientUsdcBalAfter = usdc.balanceOf(recipient);
        uint256 recipientWeETHBalAfter = usdc.balanceOf(recipient);

        assertEq(recipientUsdcBalAfter - recipientUsdcBalBefore, amounts[0]);
        assertEq(recipientWeETHBalAfter - recipientWeETHBalBefore, amounts[0]);

        vm.stopPrank();
    }

    function test_CannotProcessWithdrawalsBeforeTime() external {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        weETH.transfer(address(aliceSafe), amounts[1]);

        uint256 finalizeTime = block.timestamp +
            cashDataProvider.withdrawalDelay();
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);

        vm.warp(finalizeTime - 1);
        vm.expectRevert(IUserSafe.CannotWithdrawYet.selector);
        aliceSafe.processWithdrawal();

        vm.stopPrank();
    }

    function test_CanResetWithdrawalWithNewRequest() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        weETH.transfer(address(aliceSafe), amounts[1]);

        uint256 finalizeTime = block.timestamp +
            cashDataProvider.withdrawalDelay();

        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawalRequested(
            tokens,
            amounts,
            recipient,
            finalizeTime
        );
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);

        IUserSafe.WithdrawalData memory pendingWithdrawalRequest = aliceSafe
            .pendingWithdrawalRequest();
        assertEq(pendingWithdrawalRequest.tokens.length, 2);
        assertEq(pendingWithdrawalRequest.tokens[0], tokens[0]);
        assertEq(pendingWithdrawalRequest.tokens[1], tokens[1]);

        assertEq(pendingWithdrawalRequest.amounts.length, 2);
        assertEq(pendingWithdrawalRequest.amounts[0], amounts[0]);
        assertEq(pendingWithdrawalRequest.amounts[1], amounts[1]);

        assertEq(pendingWithdrawalRequest.recipient, recipient);
        assertEq(pendingWithdrawalRequest.finalizeTime, finalizeTime);

        address[] memory newTokens = new address[](1);
        newTokens[0] = address(usdc);

        uint256[] memory newAmounts = new uint256[](1);
        newAmounts[0] = 10e6;

        address newRecipient = owner;

        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawalCancelled(tokens, amounts, recipient);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.WithdrawalRequested(
            newTokens,
            newAmounts,
            newRecipient,
            finalizeTime
        );
        aliceSafe.requestWithdrawal(newTokens, newAmounts, newRecipient);

        UserSafe.WithdrawalData memory newWithdrawalRequest = aliceSafe
            .pendingWithdrawalRequest();
        assertEq(newWithdrawalRequest.tokens.length, 1);
        assertEq(newWithdrawalRequest.tokens[0], newTokens[0]);

        assertEq(newWithdrawalRequest.amounts.length, 1);
        assertEq(newWithdrawalRequest.amounts[0], newAmounts[0]);

        assertEq(newWithdrawalRequest.recipient, newRecipient);
        assertEq(newWithdrawalRequest.finalizeTime, finalizeTime);

        vm.stopPrank();
    }

    function test_CannotRequestWithdrawalWhenFundsAreInsufficient() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 1 ether;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);

        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);
        vm.stopPrank();
    }

    function test_CannotTransferIfAmountIsBlockedByWithdrawal() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e6;

        address recipient = notOwner;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient);
        vm.stopPrank();

        vm.prank(etherFiCashMultisig);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.transfer(address(usdc), 1);
    }
}
