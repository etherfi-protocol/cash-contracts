// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe, UserSafeLib} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeSpendingLimitTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_UpdateSpendingLimit() public {
        vm.prank(alice);
        usdc.transfer(address(aliceSafe), 1000e6);

        uint256 spendingLimitInUsd = 1000000000;
        uint256 transferAmount = 1e6;

        UserSafe.SpendingLimitData memory spendingLimitBefore = aliceSafe
            .applicableSpendingLimit();
        assertEq(spendingLimitBefore.spendingLimit, defaultSpendingLimit);
        assertEq(spendingLimitBefore.usedUpAmount, 0);

        assertEq(usdc.balanceOf(etherFiCashMultisig), 0);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), transferAmount);
        assertEq(usdc.balanceOf(etherFiCashMultisig), transferAmount);

        spendingLimitBefore = aliceSafe.applicableSpendingLimit();
        assertEq(spendingLimitBefore.usedUpAmount, transferAmount);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                spendingLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        aliceSafe.updateSpendingLimit(spendingLimitInUsd, signature);

        UserSafe.SpendingLimitData memory spendingLimitAfterUpdate = aliceSafe
            .applicableSpendingLimit();
        assertEq(
            spendingLimitAfterUpdate.spendingLimit,
            spendingLimitBefore.spendingLimit
        );

        vm.warp(block.timestamp + delay + 1);
        UserSafe.SpendingLimitData memory spendingLimitAfter = aliceSafe
            .applicableSpendingLimit();
        assertEq(spendingLimitAfter.spendingLimit, spendingLimitInUsd);
        assertEq(spendingLimitAfter.usedUpAmount, transferAmount);
    }

    function test_UpdateSpendingLimitDoesNotDelayIfLimitIsGreater() public {
        uint256 newLimit = defaultSpendingLimit + 1;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newLimit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        aliceSafe.updateSpendingLimit(newLimit, signature);

        assertEq(aliceSafe.applicableSpendingLimit().spendingLimit, newLimit);
    }

    function test_CannotSpendMoreThanSpendingLimit() public {
        uint256 spendingLimit = aliceSafe
            .applicableSpendingLimit()
            .spendingLimit;
        uint256 amount = spendingLimit + 1;
        vm.prank(alice);
        usdc.transfer(address(aliceSafe), amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_SpendingLimitGetsRenewedAutomatically() public {
        uint256 spendingLimit = aliceSafe
            .applicableSpendingLimit()
            .spendingLimit;
        uint256 amount = spendingLimit / 2;

        deal(address(usdc), address(aliceSafe), 1 ether);

        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        uint256 usedUpAmount = aliceSafe.applicableSpendingLimit().usedUpAmount;
        assertEq(usedUpAmount, amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), spendingLimit - amount + 1);

        vm.warp(aliceSafe.applicableSpendingLimit().renewalTimestamp);
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), spendingLimit - amount + 1);

        vm.warp(aliceSafe.applicableSpendingLimit().renewalTimestamp + 1);

        // Since the time for renewal is in the past, usedUpAmount should be 0
        assertEq(aliceSafe.applicableSpendingLimit().usedUpAmount, 0);

        // Since the time for renewal is in the past, we should be able to spend the whole spending limit again
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.TransferForSpending(address(usdc), spendingLimit);
        aliceSafe.transfer(address(usdc), spendingLimit);
    }
}