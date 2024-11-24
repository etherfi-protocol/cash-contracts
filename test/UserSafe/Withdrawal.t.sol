// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib, ArrayDeDupTransient} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup} from "../Setup.t.sol";

contract UserSafeWithdrawalTest is Setup {
    using MessageHashUtils for bytes32;

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

        uint256 finalizeTime = block.timestamp + cashDataProvider.delay();
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                tokens,
                amounts,
                recipient
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        IUserSafe.WithdrawalRequest
            memory pendingWithdrawalRequestBefore = aliceSafe
                .pendingWithdrawalRequest();
        assertEq(pendingWithdrawalRequestBefore.tokens.length, 0);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.WithdrawalRequested(
            address(aliceSafe),
            tokens,
            amounts,
            recipient,
            finalizeTime
        );
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);

        IUserSafe.WithdrawalRequest memory pendingWithdrawalRequestAfter = aliceSafe.pendingWithdrawalRequest();

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

        uint256 finalizeTime = block.timestamp + cashDataProvider.delay();
        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);

        uint256 recipientUsdcBalBefore = usdc.balanceOf(recipient);
        uint256 recipientWeETHBalBefore = usdc.balanceOf(recipient);

        vm.warp(finalizeTime);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.WithdrawalProcessed(address(aliceSafe), tokens, amounts, recipient);
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

        uint256 finalizeTime = block.timestamp + cashDataProvider.delay();
        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);

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

        uint256 finalizeTime = block.timestamp + cashDataProvider.delay();

        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.WithdrawalRequested(
            address(aliceSafe),
            tokens,
            amounts,
            recipient,
            finalizeTime
        );
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);

        IUserSafe.WithdrawalRequest memory pendingWithdrawalRequest = aliceSafe
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

        signature = _requestWithdrawal(newTokens, newAmounts, newRecipient);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.WithdrawalCancelled(address(aliceSafe), tokens, amounts, recipient);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.WithdrawalRequested(
            address(aliceSafe),
            newTokens,
            newAmounts,
            newRecipient,
            finalizeTime
        );
        aliceSafe.requestWithdrawal(
            newTokens,
            newAmounts,
            newRecipient,
            signature
        );

        IUserSafe.WithdrawalRequest memory newWithdrawalRequest = aliceSafe
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

        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);
        vm.stopPrank();
    }

    function test_CanTransferEvenIfAmountIsBlockedByWithdrawal() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e6;

        address recipient = notOwner;

        uint256 amountToTransfer = 1;

        vm.startPrank(alice);
        usdc.transfer(address(aliceSafe), amounts[0]);
        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);
        vm.stopPrank();

        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), amountToTransfer);

        IUserSafe.WithdrawalRequest memory withdrawalData = aliceSafe
            .pendingWithdrawalRequest();
        assertEq(withdrawalData.tokens[0], address(usdc));
        assertEq(withdrawalData.amounts[0], amounts[0] - amountToTransfer);
    }  

    function test_CannotRequestWithdrawalIfArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e6;

        address recipient = notOwner;
        
        vm.startPrank(alice);
        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        vm.expectRevert(IUserSafe.ArrayLengthMismatch.selector);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);
        vm.stopPrank();
    }

    function test_CannotRequestWithdrawalWithDuplicateTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);
        tokens[2] = address(usdc);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e6;
        amounts[1] = 100e6;
        amounts[2] = 100e6;

        address recipient = notOwner;

        vm.startPrank(alice);
        bytes memory signature = _requestWithdrawal(tokens, amounts, recipient);
        vm.expectRevert(ArrayDeDupTransient.DuplicateTokenFound.selector);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);
        vm.stopPrank();
    }

    function _requestWithdrawal(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) internal view returns (bytes memory) {
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                tokens,
                amounts,
                recipient
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
