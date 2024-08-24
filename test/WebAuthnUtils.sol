// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {n} from "SmoothCryptoLib/lib/libSCL_RIP7212.sol";
import {Base64Url} from "../src/libraries/Base64Url.sol";

struct WebAuthnInfo {
    bytes authenticatorData;
    string clientDataJSON;
    bytes32 messageHash;
}

library WebAuthnUtils {
    uint256 constant P256_N_DIV_2 = n / 2;

    function getWebAuthnStruct(
        bytes32 challenge
    ) public pure returns (WebAuthnInfo memory) {
        string memory challengeb64url = Base64Url.encode(abi.encode(challenge));
        string memory clientDataJSON = string(
            abi.encodePacked(
                '{"type":"webauthn.get","challenge":"',
                challengeb64url,
                '","origin":"https://cash.ether.fi","crossOrigin":false}'
            )
        );

        // Authenticator data for Chrome Profile touchID signature
        bytes
            memory authenticatorData = hex"49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000000";

        bytes32 clientDataJSONHash = sha256(bytes(clientDataJSON));
        bytes32 messageHash = sha256(
            abi.encodePacked(authenticatorData, clientDataJSONHash)
        );

        return WebAuthnInfo(authenticatorData, clientDataJSON, messageHash);
    }

    /// @dev normalizes the s value from a p256r1 signature so that
    /// it will pass malleability checks.
    function normalizeS(uint256 s) public pure returns (uint256) {
        if (s > P256_N_DIV_2) {
            return n - s;
        }

        return s;
    }
}
