// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib, SpendingLimit, SpendingLimitLib} from "../../src/user-safe/UserSafeCore.sol";
import {TimeLib} from "../../src/libraries/TimeLib.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeSpendingLimitTest is UserSafeSetup {
    using MessageHashUtils for bytes32;
    using TimeLib for uint256;

    function test_UpdateSpendingLimit() public {
        vm.prank(alice);
        usdc.transfer(address(aliceSafe), 1000e6);

        uint256 dailySpendingLimitInUsd = 100e6;
        uint256 monthlySpendingLimitInUsd = 1000e6;
        uint256 transferAmount = 1e6;

        SpendingLimit memory spendingLimitBefore = aliceSafe.applicableSpendingLimit();
        assertEq(spendingLimitBefore.dailyLimit, defaultDailySpendingLimit);
        assertEq(spendingLimitBefore.monthlyLimit, defaultMonthlySpendingLimit);
        assertEq(spendingLimitBefore.spentToday, 0);
        assertEq(spendingLimitBefore.spentThisMonth, 0);

        assertEq(usdc.balanceOf(settlementDispatcher), 0);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), transferAmount);
        assertEq(usdc.balanceOf(settlementDispatcher), transferAmount);

        spendingLimitBefore = aliceSafe.applicableSpendingLimit();
        assertEq(spendingLimitBefore.spentToday, transferAmount);
        assertEq(spendingLimitBefore.spentThisMonth, transferAmount);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                dailySpendingLimitInUsd,
                monthlySpendingLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        SpendingLimit memory oldLimit = aliceSafe.applicableSpendingLimit();
        SpendingLimit memory newLimit = SpendingLimit({
            dailyLimit: oldLimit.dailyLimit,
            monthlyLimit: oldLimit.monthlyLimit,
            spentToday: oldLimit.spentToday,
            spentThisMonth: oldLimit.spentThisMonth,
            newDailyLimit: oldLimit.newDailyLimit,
            newMonthlyLimit: oldLimit.newMonthlyLimit,
            dailyRenewalTimestamp: oldLimit.dailyRenewalTimestamp,
            monthlyRenewalTimestamp: oldLimit.monthlyRenewalTimestamp,
            dailyLimitChangeActivationTime: oldLimit.dailyLimitChangeActivationTime,
            monthlyLimitChangeActivationTime: oldLimit.monthlyLimitChangeActivationTime,
            timezoneOffset: oldLimit.timezoneOffset
        });
        if (dailySpendingLimitInUsd < oldLimit.dailyLimit) {
            newLimit.newDailyLimit = dailySpendingLimitInUsd;
            newLimit.dailyLimitChangeActivationTime = uint64(block.timestamp) + delay;
        } else {
            newLimit.dailyLimit = dailySpendingLimitInUsd;
            newLimit.dailyRenewalTimestamp = uint256(block.timestamp).getStartOfNextDay(timezoneOffset);
            newLimit.newDailyLimit = 0;
            newLimit.dailyLimitChangeActivationTime = 0;
        }
        
        if (monthlySpendingLimitInUsd < oldLimit.monthlyLimit) {
            newLimit.newMonthlyLimit = monthlySpendingLimitInUsd;
            newLimit.monthlyLimitChangeActivationTime = uint64(block.timestamp) + delay;
        } else {
            newLimit.monthlyLimit = monthlySpendingLimitInUsd;
            newLimit.monthlyRenewalTimestamp = uint256(block.timestamp).getStartOfNextMonth(timezoneOffset);
            newLimit.newMonthlyLimit = 0;
            newLimit.monthlyLimitChangeActivationTime = 0;
        }
        
        vm.prank(notOwner);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.SpendingLimitChanged(address(aliceSafe), oldLimit, newLimit);
        aliceSafe.updateSpendingLimit(dailySpendingLimitInUsd, monthlySpendingLimitInUsd, signature);

        SpendingLimit memory spendingLimitAfterUpdate = aliceSafe.applicableSpendingLimit();
        
        assertEq(spendingLimitAfterUpdate.dailyLimit, spendingLimitBefore.dailyLimit);
        assertEq(spendingLimitAfterUpdate.monthlyLimit, spendingLimitBefore.monthlyLimit);
        assertEq(spendingLimitAfterUpdate.newDailyLimit, dailySpendingLimitInUsd);
        assertEq(spendingLimitAfterUpdate.newMonthlyLimit, monthlySpendingLimitInUsd);
        assertEq(spendingLimitAfterUpdate.spentToday, transferAmount);
        assertEq(spendingLimitAfterUpdate.spentThisMonth, transferAmount);
        assertEq(spendingLimitAfterUpdate.dailyLimitChangeActivationTime, block.timestamp + delay);
        assertEq(spendingLimitAfterUpdate.monthlyLimitChangeActivationTime, block.timestamp + delay);

        vm.warp(block.timestamp + delay + 1);
        SpendingLimit memory spendingLimitAfter = aliceSafe.applicableSpendingLimit();
        assertEq(spendingLimitAfter.dailyLimit, dailySpendingLimitInUsd);
        assertEq(spendingLimitAfter.monthlyLimit, monthlySpendingLimitInUsd);
        assertEq(spendingLimitAfter.newDailyLimit, 0);
        assertEq(spendingLimitAfter.newMonthlyLimit, 0);
        assertEq(spendingLimitAfter.spentToday, transferAmount);
        assertEq(spendingLimitAfter.spentThisMonth, transferAmount);
        assertEq(spendingLimitAfter.dailyLimitChangeActivationTime, 0);
        assertEq(spendingLimitAfter.monthlyLimitChangeActivationTime, 0);
    }

    function test_DailyLimitCannotBeGreaterThanMonthlyLimit() public {
        uint256 newDailyLimit = 100;
        uint256 newMonthlyLimit = newDailyLimit - 1;

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newDailyLimit,
                newMonthlyLimit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        vm.expectRevert(SpendingLimitLib.DailyLimitCannotBeGreaterThanMonthlyLimit.selector);
        aliceSafe.updateSpendingLimit(newDailyLimit, newMonthlyLimit, signature);
    }

    function test_UpdateDailySpendingLimitDoesNotDelayIfLimitIsGreater() public {
        uint256 newLimit = defaultDailySpendingLimit + 1;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newLimit,
                defaultMonthlySpendingLimit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        aliceSafe.updateSpendingLimit(newLimit, defaultMonthlySpendingLimit, signature);

        assertEq(aliceSafe.applicableSpendingLimit().dailyLimit, newLimit);
        assertEq(aliceSafe.applicableSpendingLimit().newDailyLimit, 0);
        assertEq(aliceSafe.applicableSpendingLimit().dailyLimitChangeActivationTime, 0);
    }

    function test_UpdateMonthlySpendingLimitDoesNotDelayIfLimitIsGreater() public {
        uint256 newLimit = defaultMonthlySpendingLimit + 1;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                defaultDailySpendingLimit,
                newLimit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        aliceSafe.updateSpendingLimit(defaultDailySpendingLimit, newLimit, signature);

        assertEq(aliceSafe.applicableSpendingLimit().monthlyLimit, newLimit);
        assertEq(aliceSafe.applicableSpendingLimit().newMonthlyLimit, 0);
        assertEq(aliceSafe.applicableSpendingLimit().monthlyLimitChangeActivationTime, 0);
    }

    function test_CannotSpendMoreThanDailyOrMonthlySpendingLimit() public {
        SpendingLimit memory limit = aliceSafe.applicableSpendingLimit();
        uint256 amount = limit.dailyLimit + 1;
        
        deal(address(usdc), address(aliceSafe), 1 ether);

        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.transfer(address(usdc), amount);

        // // so that daily limit should not throw error
        // _updateSpendingLimit(1 ether, defaultMonthlySpendingLimit);

        // amount = limit.monthlyLimit + 1;
        // vm.prank(etherFiWallet);
        // vm.expectRevert(SpendingLimitLib.ExceededMonthlySpendingLimit.selector);
        // aliceSafe.transfer(address(usdc), amount);
    }

    function test_DailySpendingLimitGetsRenewedAutomatically() public {
        SpendingLimit memory spendingLimit = aliceSafe.applicableSpendingLimit();

        uint256 dailyLimit = spendingLimit.dailyLimit;        
        uint256 amount = dailyLimit / 2;

        deal(address(usdc), address(aliceSafe), 1 ether);

        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        assertEq(aliceSafe.applicableSpendingLimit().spentToday, amount);
        assertEq(aliceSafe.applicableSpendingLimit().spentThisMonth, amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.transfer(address(usdc), dailyLimit - amount + 1);

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp);
        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.transfer(address(usdc), dailyLimit - amount + 1);

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);
        // Since the time for renewal is in the past, spentToday should be 0
        assertEq(aliceSafe.applicableSpendingLimit().spentToday, 0);
        assertEq(aliceSafe.applicableSpendingLimit().spentThisMonth, amount);

        // Since the time for renewal is in the past, we should be able to spend the whole spending limit again
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.TransferForSpending(address(aliceSafe), address(usdc), dailyLimit);
        aliceSafe.transfer(address(usdc), dailyLimit);
    }

    // function test_MonthlySpendingLimitGetsRenewedAutomatically() public {
    //     // done so that daily limit should not get exhausted
    //     _updateSpendingLimit(defaultMonthlySpendingLimit, defaultMonthlySpendingLimit);

    //     SpendingLimit memory spendingLimit = aliceSafe.applicableSpendingLimit();

    //     uint256 monthlyLimit = spendingLimit.monthlyLimit;        
    //     uint256 amount = monthlyLimit / 2;

    //     deal(address(usdc), address(aliceSafe), 1 ether);

    //     vm.prank(etherFiWallet);
    //     aliceSafe.transfer(address(usdc), amount);

    //     assertEq(aliceSafe.applicableSpendingLimit().spentToday, amount);
    //     assertEq(aliceSafe.applicableSpendingLimit().spentThisMonth, amount);

    //     vm.prank(etherFiWallet);
    //     vm.expectRevert(SpendingLimitLib.ExceededMonthlySpendingLimit.selector);
    //     aliceSafe.transfer(address(usdc), monthlyLimit - amount + 1);

    //     vm.warp(aliceSafe.applicableSpendingLimit().monthlyRenewalTimestamp);
    //     vm.prank(etherFiWallet);
    //     vm.expectRevert(SpendingLimitLib.ExceededMonthlySpendingLimit.selector);
    //     aliceSafe.transfer(address(usdc), monthlyLimit - amount + 1);

    //     vm.warp(aliceSafe.applicableSpendingLimit().monthlyRenewalTimestamp + 1);
    //     // Since the time for renewal is in the past, spentToday should be 0
    //     assertEq(aliceSafe.applicableSpendingLimit().spentToday, 0);
    //     assertEq(aliceSafe.applicableSpendingLimit().spentThisMonth, 0);

    //     // Since the time for renewal is in the past, we should be able to spend the whole spending limit again
    //     vm.prank(etherFiWallet);
    //     vm.expectEmit(true, true, true, true);
    //     emit UserSafeEventEmitter.TransferForSpending(address(aliceSafe), address(usdc), monthlyLimit);
    //     aliceSafe.transfer(address(usdc), monthlyLimit);
    // }

    function _updateSpendingLimit(uint256 dailyLimitInUsd, uint256 monthlyLimitInUsd) internal {
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                dailyLimitInUsd,
                monthlyLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.updateSpendingLimit(dailyLimitInUsd, monthlyLimitInUsd, signature);
    }
}