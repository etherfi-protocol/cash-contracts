// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeEventEmitter, IUserSafe, OwnerLib, UserSafe, UserSafeLib} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeCollateralLimitTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_SetCollateralLimitIncursDelayIfAmountIsLower() public {
        uint256 newCollateralLimit = collateralLimit - 1;
        uint256 delayedTime = block.timestamp + delay + 1;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_COLLATERAL_LIMIT_METHOD,
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

        uint256 collateralLimitBefore = aliceSafe.applicableCollateralLimit();
        assertEq(collateralLimitBefore, collateralLimit);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.CollateralLimitSet(
            address(aliceSafe),
            collateralLimitBefore,
            newCollateralLimit,
            delayedTime - 1
        );
        aliceSafe.setCollateralLimit(newCollateralLimit, signature);

        uint256 collateralLimitAfterSet = aliceSafe.applicableCollateralLimit();
        assertEq(collateralLimitBefore, collateralLimitAfterSet);

        vm.warp(delayedTime);
        uint256 collateralLimitAfterDelay = aliceSafe
            .applicableCollateralLimit();
        assertEq(newCollateralLimit, collateralLimitAfterDelay);
    }

    function test_SetCollateralLimitDoesNotDelayIfLimitIsGreater() public {
        uint256 newCollateralLimit = collateralLimit + 1;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_COLLATERAL_LIMIT_METHOD,
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

        uint256 collateralLimitBefore = aliceSafe.applicableCollateralLimit();
        assertEq(collateralLimitBefore, collateralLimit);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.CollateralLimitSet(
            address(aliceSafe),
            collateralLimitBefore,
            newCollateralLimit,
            block.timestamp
        );
        aliceSafe.setCollateralLimit(newCollateralLimit, signature);

        uint256 collateralLimitAfterSet = aliceSafe.applicableCollateralLimit();
        assertEq(newCollateralLimit, collateralLimitAfterSet);
    }

    function test_CannotAddMoreCollateralThanCollateralLimit() public {
        uint256 amount = 10 ether;
        deal(address(weETH), address(aliceSafe), amount);

        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.ExceededCollateralLimit.selector);
        aliceSafe.addCollateral(address(weETH), amount);
    }
}