// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

contract UserSafeOwnerTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_CanSetEthereumAddrAsOwner() public {
        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        vm.prank(alice);
        aliceSafe.setOwner(newOwnerBytes);

        assertEq(aliceSafe.owner().ethAddr, newOwner);
        assertEq(aliceSafe.owner().x, 0);
        assertEq(aliceSafe.owner().y, 0);
    }

    function test_CanSetPasskeyAsOwner() public {
        uint256 x = 1;
        uint256 y = 2;

        bytes memory newOwnerBytes = abi.encode(x, y);

        vm.prank(alice);
        aliceSafe.setOwner(newOwnerBytes);

        assertEq(aliceSafe.owner().ethAddr, address(0));
        assertEq(aliceSafe.owner().x, x);
        assertEq(aliceSafe.owner().y, y);
    }

    function test_OnlyOwnerCanSetNewOwner() public {
        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        vm.prank(notOwner);
        vm.expectRevert(OwnerLib.OnlyOwner.selector);
        aliceSafe.setOwner(newOwnerBytes);
    }

    function test_CanSetOwnerWithPermitUsingEthereumSignature() public {
        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.SET_OWNER_METHOD(),
                block.chainid,
                address(aliceSafe),
                newOwnerBytes,
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(notOwner);
        aliceSafe.setOwnerWithPermit(newOwnerBytes, nonce, signature);

        assertEq(aliceSafe.owner().ethAddr, newOwner);
        assertEq(aliceSafe.owner().x, 0);
        assertEq(aliceSafe.owner().y, 0);
    }
}
