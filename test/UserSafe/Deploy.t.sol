// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";

contract UserSafeDeployTest is UserSafeSetup {
    address bob = makeAddr("bob");
    bytes bobBytes = abi.encode(bob);

    function test_Deploy() public view {
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(aliceSafe.recoverySigners()[0].ethAddr, address(0));
        assertEq(aliceSafe.recoverySigners()[1].ethAddr, etherFiRecoverySigner);
        assertEq(
            aliceSafe.recoverySigners()[2].ethAddr,
            thirdPartyRecoverySigner
        );

        UserSafe.SpendingLimitData memory spendingLimit = aliceSafe
            .applicableSpendingLimit();
        assertEq(spendingLimit.spendingLimit, defaultSpendingLimit);
    }

    function test_DeployAUserSafe() public {
        bytes memory salt = abi.encode("safe", block.timestamp);

        bytes memory initData = abi.encodeWithSelector(
            // initialize(bytes,uint256, uint256)
            0x32b218ac,
            bobBytes,
            defaultSpendingLimit,
            collateralLimit
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
            // initialize(bytes,uint256, uint256)
            0x32b218ac,
            bobBytes,
            defaultSpendingLimit,
            collateralLimit
        );
        
        address deterministicAddress = factory.getUserSafeAddress(salt, initData);
        address safe = factory.createUserSafe(salt, initData);
        assertEq(deterministicAddress, safe);

        vm.expectRevert(CREATE3.DeploymentFailed.selector);
        factory.createUserSafe(salt, initData);
        vm.stopPrank();
    }
}
