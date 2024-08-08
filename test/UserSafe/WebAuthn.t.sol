// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {IUserSafe, OwnerLib, WebAuthn, UserSafe} from "../../src/user-safe/UserSafe.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
// import {UserSafeSetup} from "./UserSafeSetup.sol";
// import {WebAuthnInfo, WebAuthnUtils} from "../WebAuthnUtils.sol";

// contract UserSafeWebAuthnSignatureTest is UserSafeSetup {
//     function test_CanSetOwnerWithWebAuthn() public {
//         address newOwner = makeAddr("owner");
//         uint256 nonce = passkeyOwnerSafe.nonce() + 1;
//         bytes memory newOwnerBytes = abi.encode(newOwner);

//         bytes32 msgHash = keccak256(
//             abi.encode(
//                 passkeyOwnerSafe.SET_OWNER_METHOD(),
//                 block.chainid,
//                 address(passkeyOwnerSafe),
//                 newOwnerBytes,
//                 nonce
//             )
//         );

//         WebAuthnInfo memory webAuthn = WebAuthnUtils.getWebAuthnStruct(msgHash);

//         (bytes32 r, bytes32 s) = vm.signP256(
//             passkeyPrivateKey,
//             webAuthn.messageHash
//         );
//         s = bytes32(WebAuthnUtils.normalizeS(uint256(s)));

//         bytes memory signature = abi.encode(
//             WebAuthn.WebAuthnAuth({
//                 authenticatorData: webAuthn.authenticatorData,
//                 clientDataJSON: webAuthn.clientDataJSON,
//                 typeIndex: 1,
//                 challengeIndex: 23,
//                 r: uint256(r),
//                 s: uint256(s)
//             })
//         );

//         passkeyOwnerSafe.setOwnerWithPermit(newOwnerBytes, nonce, signature);
//     }
// }
