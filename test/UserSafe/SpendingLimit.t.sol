// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeSpendingLimitTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_SetSpendingLimit() public {
        uint256 dailySpendingLimit = 1000000;
        uint256 weeklySpendingLimit = 10000000;
        uint256 monthlySpendingLimit = 100000000;
        uint256 yearlySpendingLimit = 100000000;

        vm.prank(alice);
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Daily),
            dailySpendingLimit
        );

        vm.warp(block.timestamp + delay + 1);
        UserSafe.SpendingLimitData memory spendingLimitData = aliceSafe
            .applicableSpendingLimit();

        assertEq(
            spendingLimitData.renewalTimestamp,
            (block.timestamp - 1) + 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, dailySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(IUserSafe.SpendingLimitTypes.Daily)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);

        vm.prank(alice);
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Weekly),
            weeklySpendingLimit
        );

        vm.warp(block.timestamp + delay + 1);
        spendingLimitData = aliceSafe.applicableSpendingLimit();
        assertEq(
            spendingLimitData.renewalTimestamp,
            (block.timestamp - 1) + 7 * 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, weeklySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(IUserSafe.SpendingLimitTypes.Weekly)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);

        vm.prank(alice);
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Monthly),
            monthlySpendingLimit
        );

        vm.warp(block.timestamp + delay + 1);
        spendingLimitData = aliceSafe.applicableSpendingLimit();
        assertEq(
            spendingLimitData.renewalTimestamp,
            (block.timestamp - 1) + 30 * 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, monthlySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(IUserSafe.SpendingLimitTypes.Monthly)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);

        vm.prank(alice);
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Yearly),
            yearlySpendingLimit
        );

        vm.warp(block.timestamp + delay + 1);
        spendingLimitData = aliceSafe.applicableSpendingLimit();
        assertEq(
            spendingLimitData.renewalTimestamp,
            (block.timestamp - 1) + 365 * 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, yearlySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(IUserSafe.SpendingLimitTypes.Yearly)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);
    }

    function test_OnlyOwnerCanSetSpendingLimits() public {
        uint256 spendingLimit = 1000000;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerLib.OnlyOwner.selector));
        aliceSafe.resetSpendingLimit(
            uint8(IUserSafe.SpendingLimitTypes.Daily),
            spendingLimit
        );
    }

    function test_SetSpendingLimitWithPermit() public {
        uint8 spendingLimitType = uint8(IUserSafe.SpendingLimitTypes.Monthly);
        uint256 spendingLimitInUsd = 1000000000;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RESET_SPENDING_LIMIT_METHOD(),
                block.chainid,
                address(aliceSafe),
                nonce,
                spendingLimitType,
                spendingLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        UserSafe.SpendingLimitData memory spendingLimitBefore = aliceSafe
            .spendingLimit();
        assertEq(spendingLimitBefore.spendingLimit, defaultSpendingLimit);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(notOwner);
        aliceSafe.resetSpendingLimitWithPermit(
            spendingLimitType,
            spendingLimitInUsd,
            signature
        );

        vm.warp(block.timestamp + delay + 1);
        UserSafe.SpendingLimitData memory spendingLimitAfter = aliceSafe
            .applicableSpendingLimit();
        assertEq(spendingLimitAfter.spendingLimit, spendingLimitInUsd);
    }

    function test_UpdateSpendingLimit() public {
        vm.prank(alice);
        usdc.transfer(address(aliceSafe), 1000e6);

        uint256 spendingLimitInUsd = 1000000000;
        uint256 transferAmount = 1e6;

        UserSafe.SpendingLimitData memory spendingLimitBefore = aliceSafe
            .spendingLimit();
        assertEq(spendingLimitBefore.spendingLimit, defaultSpendingLimit);
        assertEq(spendingLimitBefore.usedUpAmount, 0);

        assertEq(usdc.balanceOf(etherFiCashMultisig), 0);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), transferAmount);
        assertEq(usdc.balanceOf(etherFiCashMultisig), transferAmount);

        spendingLimitBefore = aliceSafe.spendingLimit();
        assertEq(spendingLimitBefore.usedUpAmount, transferAmount);

        vm.prank(alice);
        aliceSafe.updateSpendingLimit(spendingLimitInUsd);

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

    function test_OnlyOwnerUpdateSpendingLimit() public {
        uint256 spendingLimitInUsd = 1000000000;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerLib.OnlyOwner.selector));
        aliceSafe.updateSpendingLimit(spendingLimitInUsd);
    }

    function test_UpdateSpendingLimitWithPermit() public {
        vm.prank(alice);
        usdc.transfer(address(aliceSafe), 1000e6);

        uint256 spendingLimitInUsd = 1000000000;
        uint256 transferAmount = 1e6;

        UserSafe.SpendingLimitData memory spendingLimitBefore = aliceSafe
            .spendingLimit();
        assertEq(spendingLimitBefore.spendingLimit, defaultSpendingLimit);
        assertEq(spendingLimitBefore.usedUpAmount, 0);

        assertEq(usdc.balanceOf(etherFiCashMultisig), 0);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), transferAmount);
        assertEq(usdc.balanceOf(etherFiCashMultisig), transferAmount);

        spendingLimitBefore = aliceSafe.spendingLimit();
        assertEq(spendingLimitBefore.usedUpAmount, transferAmount);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.UPDATE_SPENDING_LIMIT_METHOD(),
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
        aliceSafe.updateSpendingLimitWithPermit(spendingLimitInUsd, signature);

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

    function test_CannotSpendMoreThanSpendingLimit() public {
        uint256 spendingLimit = aliceSafe.spendingLimit().spendingLimit;
        uint256 amount = spendingLimit + 1;
        vm.prank(alice);
        usdc.transfer(address(aliceSafe), amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_SpendingLimitGetsRenewedAutomatically() public {
        uint256 spendingLimit = aliceSafe.spendingLimit().spendingLimit;
        uint256 amount = spendingLimit / 2;

        deal(address(usdc), address(aliceSafe), 1 ether);

        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        uint256 usedUpAmount = aliceSafe.spendingLimit().usedUpAmount;
        assertEq(usedUpAmount, amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), spendingLimit - amount + 1);

        vm.warp(aliceSafe.spendingLimit().renewalTimestamp);
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededSpendingLimit.selector);
        aliceSafe.transfer(address(usdc), spendingLimit - amount + 1);

        vm.warp(aliceSafe.spendingLimit().renewalTimestamp + 1);

        // Since the time for renewal is in the past, usedUpAmount should be 0
        assertEq(aliceSafe.applicableSpendingLimit().usedUpAmount, 0);

        // Since the time for renewal is in the past, we should be able to spend the whole spending limit again
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.TransferForSpending(address(usdc), spendingLimit);
        aliceSafe.transfer(address(usdc), spendingLimit);
    }
}
