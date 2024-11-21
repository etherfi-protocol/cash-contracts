// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, SpendingLimit, UserSafeCore} from "../../src/user-safe/UserSafeCore.sol";
import {Setup} from "../Setup.t.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";

contract UserSafeDeployTest is Setup {
    address bob = makeAddr("bob");
    bytes bobBytes = abi.encode(bob);

    function test_Deploy() public view {
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(aliceSafe.recoverySigners()[0].ethAddr, address(0));
        assertEq(aliceSafe.recoverySigners()[1].ethAddr, etherFiRecoverySigner);
        assertEq(aliceSafe.recoverySigners()[2].ethAddr, thirdPartyRecoverySigner);

        SpendingLimit memory spendingLimit = aliceSafe.applicableSpendingLimit();
        assertEq(spendingLimit.dailyLimit, defaultDailySpendingLimit);
        assertEq(spendingLimit.monthlyLimit, defaultMonthlySpendingLimit);
        assertEq(spendingLimit.spentToday, 0);
        assertEq(spendingLimit.spentThisMonth, 0);
        assertEq(spendingLimit.newDailyLimit, 0);
        assertEq(spendingLimit.newMonthlyLimit, 0);
        assertEq(spendingLimit.dailyLimitChangeActivationTime, 0);
        assertEq(spendingLimit.monthlyLimitChangeActivationTime, 0);
        assertEq(spendingLimit.timezoneOffset, timezoneOffset);
    }

    function test_DeployAUserSafe() public {
        bytes memory salt = abi.encode("safe", block.timestamp);

        bytes memory initData = abi.encodeWithSelector(
            UserSafeCore.initialize.selector,
            bobBytes,
            defaultDailySpendingLimit,
            defaultMonthlySpendingLimit,
            timezoneOffset
        );
        
        address deterministicAddress = factory.getUserSafeAddress(salt, initData);
        vm.prank(owner);
        address safe = factory.createUserSafe(salt, initData);
        assertEq(deterministicAddress, safe);
    }

    function test_CannotDeployTwoUserSafesAtTheSameAddress() public {
        vm.startPrank(owner);
        bytes memory salt = abi.encode("safe", block.timestamp);

        bytes memory initData = abi.encodeWithSelector(
            UserSafeCore.initialize.selector,
            bobBytes,
            defaultDailySpendingLimit,
            defaultMonthlySpendingLimit,
            timezoneOffset
        );
        
        address deterministicAddress = factory.getUserSafeAddress(salt, initData);
        address safe = factory.createUserSafe(salt, initData);
        assertEq(deterministicAddress, safe);

        vm.expectRevert(CREATE3.DeploymentFailed.selector);
        factory.createUserSafe(salt, initData);
        vm.stopPrank();
    }
}