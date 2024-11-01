// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafe, UserSafeLib} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeOwnerTest is UserSafeSetup {
    using MessageHashUtils for bytes32;
    using OwnerLib for bytes;

    function test_CanSetEthereumAddrAsOwner() public {
        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        bytes memory signature = _signSetOwner(newOwnerBytes);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.OwnerSet(address(aliceSafe), aliceSafe.owner(), newOwnerBytes.getOwnerObject());
        aliceSafe.setOwner(newOwnerBytes, signature);

        assertEq(aliceSafe.owner().ethAddr, newOwner);
        assertEq(aliceSafe.owner().x, 0);
        assertEq(aliceSafe.owner().y, 0);
    }

    function test_CanSetPasskeyAsOwner() public {
        uint256 x = 1;
        uint256 y = 2;

        bytes memory newOwnerBytes = abi.encode(x, y);
        bytes memory signature = _signSetOwner(newOwnerBytes);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.OwnerSet(address(aliceSafe), aliceSafe.owner(), newOwnerBytes.getOwnerObject());
        aliceSafe.setOwner(newOwnerBytes, signature);

        assertEq(aliceSafe.owner().ethAddr, address(0));
        assertEq(aliceSafe.owner().x, x);
        assertEq(aliceSafe.owner().y, y);
    }

    function _signSetOwner(
        bytes memory ownerBytes
    ) internal view returns (bytes memory) {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_OWNER_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                ownerBytes
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }
}