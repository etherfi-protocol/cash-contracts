// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Library of utilities for making EIP1271-compliant signature checks.
 * @author Layr Labs, Inc.
 */
library EIP1271SignatureUtils {
    using MessageHashUtils for bytes32;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant EIP1271_MAGICVALUE = 0x1626ba7e;

    error InvalidSigner();
    error InvalidERC1271Signer();

    /**
     * @notice Checks @param signature is a valid signature of @param digestHash from @param signer.
     * If the `signer` contains no code -- i.e. it is not (yet, at least) a contract address, then checks using standard ECDSA logic
     * Otherwise, passes on the signature to the signer to verify the signature and checks that it returns the `EIP1271_MAGICVALUE`.
     */
    function checkSignature_EIP1271(
        bytes32 msgHash,
        address signer,
        bytes memory signature
    ) internal view {
        bytes32 digestHash = msgHash.toEthSignedMessageHash();

        /**
         * check validity of signature:
         * 1) if `signer` is an EOA, then `signature` must be a valid ECDSA signature from `signer`,
         * indicating their intention for this action
         * 2) if `signer` is a contract, then `signature` must will be checked according to EIP-1271
         */
        if (isContract(signer)) {
            if (
                IERC1271(signer).isValidSignature(digestHash, signature) !=
                EIP1271_MAGICVALUE
            ) revert InvalidERC1271Signer();
        } else {
            if (ECDSA.recover(digestHash, signature) != signer)
                revert InvalidSigner();
        }
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
