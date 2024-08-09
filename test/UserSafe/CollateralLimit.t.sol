// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

contract UserSafeCollateralLimitTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_SetCollateralLimit() public {
        uint256 newCollateralLimit = 1 ether;
        uint256 delayedTime = block.timestamp + delay + 1;

        uint256 collateralLimitBefore = aliceSafe.collateralLimit();
        assertEq(collateralLimitBefore, collateralLimit);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.SetCollateralLimit(
            collateralLimitBefore,
            newCollateralLimit,
            delayedTime - 1
        );
        aliceSafe.setCollateralLimit(newCollateralLimit);

        uint256 collateralLimitAfterSet = aliceSafe.applicableCollateralLimit();
        assertEq(collateralLimitBefore, collateralLimitAfterSet);

        vm.warp(delayedTime);
        uint256 collateralLimitAfterDelay = aliceSafe
            .applicableCollateralLimit();
        assertEq(newCollateralLimit, collateralLimitAfterDelay);
    }

    function test_OnlyOwnerCanSetCollateralLimits() public {
        uint256 newCollateralLimit = 1 ether;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerLib.OnlyOwner.selector));
        aliceSafe.setCollateralLimit(newCollateralLimit);
    }

    function test_SetCollateralLimitWithPermit() public {
        uint256 newCollateralLimit = 1 ether;
        uint256 delayedTime = block.timestamp + delay + 1;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.SET_COLLATERAL_LIMIT_METHOD(),
                block.chainid,
                address(aliceSafe),
                nonce,
                newCollateralLimit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 collateralLimitBefore = aliceSafe.collateralLimit();
        assertEq(collateralLimitBefore, collateralLimit);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.SetCollateralLimit(
            collateralLimitBefore,
            newCollateralLimit,
            delayedTime - 1
        );
        aliceSafe.setCollateralLimitWithPermit(newCollateralLimit, signature);

        uint256 collateralLimitAfterSet = aliceSafe.applicableCollateralLimit();
        assertEq(collateralLimitBefore, collateralLimitAfterSet);

        vm.warp(delayedTime);
        uint256 collateralLimitAfterDelay = aliceSafe
            .applicableCollateralLimit();
        assertEq(newCollateralLimit, collateralLimitAfterDelay);
    }

    function test_CannotAddMoreCollateralThanSpendingLimit() public {
        uint256 amount = 10 ether;
        deal(address(weETH), address(aliceSafe), amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededCollateralLimit.selector);
        aliceSafe.addCollateral(address(weETH), amount);
    }
}
