// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SignatureUtils
 * @author ether.fi [shivam@ether.fi]
 * @notice Library to verify Signatures using ECDSA signing scheme
 */
library SignatureUtils {
    using MessageHashUtils for bytes32;

    string constant MSG_PREFIX = "\x19Ethereum Signed Message:\n32";

    error InvalidSigner();

    function isValidSig(
        bytes32 _messageHash,
        address _signer,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) internal pure returns (bool) {
        bytes32 signedHash = _messageHash.toEthSignedMessageHash();
        if (_signer != ECDSA.recover(signedHash, _v, _r, _s)) return false;

        return true;
    }

    function verifySig(
        bytes32 _messageHash,
        address _signer,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) internal pure {
        if (!isValidSig(_messageHash, _signer, _r, _s, _v))
            revert InvalidSigner();
    }
}
