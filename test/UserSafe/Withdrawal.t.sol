// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafe} from "../../src/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

error OwnableUnauthorizedAccount(address account);
error CannotWithdrawYet();

event WithdrawalRequested(
    address[] tokens,
    uint256[] amounts,
    address recipient,
    uint256 finalizeTimestamp
);
event WithdrawalProcessed(
    address[] tokens,
    uint256[] amounts,
    address recipient
);

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
        emit WithdrawalRequested(tokens, amounts, recipient, finalizeTime);
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
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
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
        emit WithdrawalRequested(tokens, amounts, recipient, finalizeTime);
        aliceSafe.requestWithdrawalWithPermit(
            tokens,
            amounts,
            recipient,
            nonce,
            r,
            s,
            v
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
        emit WithdrawalProcessed(tokens, amounts, recipient);
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
        vm.expectRevert(CannotWithdrawYet.selector);
        aliceSafe.processWithdrawal();

        vm.stopPrank();
    }
}
