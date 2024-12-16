// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {EIP1271SignatureUtils} from "./EIP1271SignatureUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {OwnerLib} from "./OwnerLib.sol";
import {WebAuthn} from "./WebAuthn.sol";

/**
 * @title Signature Utils
 */
library SignatureUtils {
    using EIP1271SignatureUtils for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidWebAuthSignature();

    function verifySig(
        bytes32 hash,
        OwnerLib.OwnerObject memory owner,
        bytes calldata signature
    ) internal view {
        if (owner.ethAddr != address(0))
            hash.toEthSignedMessageHash().checkSignature_EIP1271(owner.ethAddr, signature);
        else {
            WebAuthn.WebAuthnAuth memory auth = abi.decode(
                signature,
                (WebAuthn.WebAuthnAuth)
            );

            if (
                !WebAuthn.verify({
                    challenge: abi.encode(hash),
                    requireUV: false,
                    webAuthnAuth: auth,
                    x: owner.x,
                    y: owner.y
                })
            ) revert InvalidWebAuthSignature();
        }
    }
}