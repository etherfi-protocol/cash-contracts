// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup} from "../Setup.t.sol";
import {console} from "forge-std/console.sol";

contract RecoverUserSafe is Setup {
    using MessageHashUtils for bytes32;

    bytes32 public constant RECOVERY_METHOD = keccak256("recoverUserSafe");
    
    bytes newOwnerBytes;

    function setUp() public override {
        super.setUp();
        address recoverySafe1 = 0xbfCe61CE31359267605F18dcE65Cb6c3cc9694A7;   
        address recoverySafe2 = 0xa265C271adbb0984EFd67310cfe85A77f449e291;

        vm.startPrank(owner);   
        cashDataProvider.setEtherFiRecoverySigner(recoverySafe1);
        cashDataProvider.setThirdPartyRecoverySigner(recoverySafe2);
        vm.stopPrank();

        newOwnerBytes = abi.encode(makeAddr("bob"));
    }
    
    function test_BuildMessageHashAndDigest() external view {
        bytes32 messageHash = keccak256(
            abi.encode(
                RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                aliceSafe.nonce() + 1,
                newOwnerBytes
            )
        );
        
        bytes32 digest = messageHash.toEthSignedMessageHash();

        console.log("digest: ");
        console.logBytes32(digest);
        console.log("messageHash: ");
        console.logBytes32(messageHash);
    }
		
    function test_RecoverWithSafeSignature() external {        
        IUserSafe.Signature[2] memory signatures;
        
        signatures[0] = IUserSafe.Signature({
            index: 1, // index 1 for etherfi signer safe
            signature: "" // no need to pass a sig since executed onchain
        });
        
        signatures[1] = IUserSafe.Signature({
            index: 2, // index 2 for third party safe
            signature: "" // no need to pass a sig since executed onchain
        });
        
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);
    }
}