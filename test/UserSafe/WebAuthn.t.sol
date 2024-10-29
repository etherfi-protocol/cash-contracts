// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, WebAuthn, UserSafe, UserSafeLib} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";
import {WebAuthnInfo, WebAuthnUtils} from "../WebAuthnUtils.sol";

contract UserSafeWebAuthnSignatureTest is UserSafeSetup {
    uint256 passkeyPrivateKey =
        uint256(
            0x03d99692017473e2d631945a812607b23269d85721e0f370b8d3e7d29a874fd2
        );
    bytes passkeyOwner =
        hex"1c05286fe694493eae33312f2d2e0d0abeda8db76238b7a204be1fb87f54ce4228fef61ef4ac300f631657635c28e59bfb2fe71bce1634c81c65642042f6dc4d";

    UserSafe passkeyOwnerSafe;

    function setUp() public override {
        super.setUp();

        bytes memory saltData = bytes("passkeySafe");

        vm.prank(owner);
        passkeyOwnerSafe = UserSafe(
            factory.createUserSafe(
                saltData,
                abi.encodeWithSelector(
                    UserSafe.initialize.selector,
                    passkeyOwner,
                    defaultDailySpendingLimit,
                    defaultMonthlySpendingLimit,
                    collateralLimit,
                    timezoneOffset
                )
            )
        );
    }

    function test_Deploy() public view {
        assertEq(
            abi.encode(passkeyOwnerSafe.owner().x, passkeyOwnerSafe.owner().y),
            passkeyOwner
        );

        assertEq(
            abi.encode(
                passkeyOwnerSafe.recoverySigners()[0].x,
                passkeyOwnerSafe.recoverySigners()[0].y
            ),
            abi.encode(0, 0)
        );
        assertEq(passkeyOwnerSafe.recoverySigners()[0].ethAddr, address(0));
        assertEq(
            passkeyOwnerSafe.recoverySigners()[1].ethAddr,
            etherFiRecoverySigner
        );
        assertEq(
            passkeyOwnerSafe.recoverySigners()[2].ethAddr,
            thirdPartyRecoverySigner
        );
    }

    function test_CanSetOwnerWithWebAuthn() public {
        address newOwner = makeAddr("owner");
        uint256 nonce = passkeyOwnerSafe.nonce() + 1;
        bytes memory newOwnerBytes = abi.encode(newOwner);

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_OWNER_METHOD,
                block.chainid,
                address(passkeyOwnerSafe),
                nonce,
                newOwnerBytes
            )
        );

        WebAuthnInfo memory webAuthn = WebAuthnUtils.getWebAuthnStruct(msgHash);

        // a user -> change my spending limit
        // challenge, clientjson
        // take a signature using passkey, UI gives authenticator data -> user biometrics
        (bytes32 r, bytes32 s) = vm.signP256(
            passkeyPrivateKey,
            webAuthn.messageHash
        );
        s = bytes32(WebAuthnUtils.normalizeS(uint256(s)));

        bytes memory signature = abi.encode(
            WebAuthn.WebAuthnAuth({
                authenticatorData: webAuthn.authenticatorData,
                clientDataJSON: webAuthn.clientDataJSON,
                typeIndex: 1,
                challengeIndex: 23,
                r: uint256(r),
                s: uint256(s)
            })
        );

        passkeyOwnerSafe.setOwner(newOwnerBytes, signature);

        assertEq(passkeyOwnerSafe.owner().ethAddr, newOwner);
    }
}
