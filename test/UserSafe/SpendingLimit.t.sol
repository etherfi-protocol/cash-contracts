// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafe} from "../../src/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

error OwnableUnauthorizedAccount(address account);

contract UserSafeSpendingLimitTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_SetSpendingLimit() public {
        uint256 dailySpendingLimit = 1000000;
        uint256 weeklySpendingLimit = 10000000;
        uint256 monthlySpendingLimit = 100000000;
        uint256 yearlySpendingLimit = 100000000;

        vm.prank(alice);
        aliceSafe.setSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Daily),
            dailySpendingLimit
        );

        UserSafe.SpendingLimitData memory spendingLimitData = aliceSafe
            .spendingLimit();

        assertEq(
            spendingLimitData.renewalTimestamp,
            block.timestamp + 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, dailySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(UserSafe.SpendingLimitTypes.Daily)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);

        vm.prank(alice);
        aliceSafe.setSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Weekly),
            weeklySpendingLimit
        );
        spendingLimitData = aliceSafe.spendingLimit();
        assertEq(
            spendingLimitData.renewalTimestamp,
            block.timestamp + 7 * 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, weeklySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(UserSafe.SpendingLimitTypes.Weekly)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);

        vm.prank(alice);
        aliceSafe.setSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Monthly),
            monthlySpendingLimit
        );
        spendingLimitData = aliceSafe.spendingLimit();
        assertEq(
            spendingLimitData.renewalTimestamp,
            block.timestamp + 30 * 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, monthlySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(UserSafe.SpendingLimitTypes.Monthly)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);

        vm.prank(alice);
        aliceSafe.setSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Yearly),
            yearlySpendingLimit
        );
        spendingLimitData = aliceSafe.spendingLimit();
        assertEq(
            spendingLimitData.renewalTimestamp,
            block.timestamp + 365 * 24 * 60 * 60
        );
        assertEq(spendingLimitData.spendingLimit, yearlySpendingLimit);
        assertEq(
            uint8(spendingLimitData.spendingLimitType),
            uint8(UserSafe.SpendingLimitTypes.Yearly)
        );
        assertEq(spendingLimitData.usedUpAmount, 0);
    }

    function test_SetIncomingSpendingLimit() public {
        uint256 spendingLimit = 1000000;

        vm.startPrank(alice);
        aliceSafe.setSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Daily),
            spendingLimit
        );

        uint64 renewalTimestamp = aliceSafe.spendingLimit().renewalTimestamp;

        aliceSafe.setIncomingSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Weekly),
            spendingLimit
        );

        assertEq(
            aliceSafe.incomingSpendingLimit().renewalTimestamp,
            renewalTimestamp + 7 * 24 * 60 * 60
        );

        vm.warp(renewalTimestamp + 1);
        assertEq(
            aliceSafe.applicableSpendingLimit().renewalTimestamp,
            renewalTimestamp + 7 * 24 * 60 * 60
        );
        vm.stopPrank();
    }

    function test_OnlyOwnerCanSetSpendingLimits() public {
        uint256 spendingLimit = 1000000;

        vm.startPrank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        aliceSafe.setSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Daily),
            spendingLimit
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        aliceSafe.setIncomingSpendingLimit(
            uint8(UserSafe.SpendingLimitTypes.Weekly),
            spendingLimit
        );
        vm.stopPrank();
    }

    function test_SetSpendingLimitWithPermit() public {
        uint8 spendingLimitType = uint8(UserSafe.SpendingLimitTypes.Monthly);
        uint256 spendingLimitInUsd = 1000000000;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.SET_SPENDING_LIMIT_METHOD(),
                spendingLimitType,
                spendingLimitInUsd,
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        UserSafe.SpendingLimitData memory spendingLimitBefore = aliceSafe
            .spendingLimit();
        assertEq(spendingLimitBefore.spendingLimit, 0);

        vm.prank(notOwner);
        aliceSafe.setSpendingLimitWithPermit(
            spendingLimitType,
            spendingLimitInUsd,
            nonce,
            r,
            s,
            v
        );

        UserSafe.SpendingLimitData memory spendingLimitAfter = aliceSafe
            .spendingLimit();
        assertEq(spendingLimitAfter.spendingLimit, spendingLimitInUsd);
    }

    function test_SetIncomingSpendingLimitWithPermit() public {
        uint8 spendingLimitType = uint8(UserSafe.SpendingLimitTypes.Monthly);
        uint256 spendingLimitInUsd = 1000000000;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.SET_INCOMING_SPENDING_LIMIT_METHOD(),
                spendingLimitType,
                spendingLimitInUsd,
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        UserSafe.SpendingLimitData
            memory incomingSpendingLimitBefore = aliceSafe
                .incomingSpendingLimit();
        assertEq(incomingSpendingLimitBefore.spendingLimit, 0);

        vm.prank(notOwner);
        aliceSafe.setIncomingSpendingLimitWithPermit(
            spendingLimitType,
            spendingLimitInUsd,
            nonce,
            r,
            s,
            v
        );

        UserSafe.SpendingLimitData memory incomingSpendingLimitAfter = aliceSafe
            .incomingSpendingLimit();
        assertEq(incomingSpendingLimitAfter.spendingLimit, spendingLimitInUsd);
    }
}
