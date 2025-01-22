// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup} from "../Setup.t.sol";
import {console} from "forge-std/console.sol";

contract RecoverUserSafe is Setup {
    using MessageHashUtils for bytes32;

    // rupert safe: 0x5BBa1D1b2820c56c798a831cCF7Ad39B70b13A01;
    // rupert passkey: abi.encode(15082030980405370419740072472485942557010062688916066938680834158844092834592, 7559725260680920969704920277862482544482567665366802956448675880212639145527);
    // user's safe: 0x2412292985aAc0F6696Bd473Fd845FC04e2C8DaD;
    // user's passkey: abi.encode(10747656110611756665682659753863643407259137457259800218403383070240064687361, 963539874084845106450594458182541423004553654316691203780793667511663756800);

    bytes32 public constant RECOVERY_METHOD = keccak256("recoverUserSafe");
    
    IUserSafe userSafe = IUserSafe(0x2412292985aAc0F6696Bd473Fd845FC04e2C8DaD);
    bytes newOwnerBytes = abi.encode(10747656110611756665682659753863643407259137457259800218403383070240064687361, 963539874084845106450594458182541423004553654316691203780793667511663756800);

    function setUp() public override {
        super.setUp();
        // address recoverySafe1 = 0xbfCe61CE31359267605F18dcE65Cb6c3cc9694A7;   
        // address recoverySafe2 = 0xa265C271adbb0984EFd67310cfe85A77f449e291;

        // vm.startPrank(owner);   
        // cashDataProvider.setEtherFiRecoverySigner(recoverySafe1);
        // cashDataProvider.setThirdPartyRecoverySigner(recoverySafe2);
        // vm.stopPrank();
    }
    
    function test_BuildMessageHashAndDigest() external view {
        bytes32 messageHash = keccak256(
            abi.encode(
                RECOVERY_METHOD,
                block.chainid,
                address(userSafe),
                userSafe.nonce() + 1,
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
            signature: hex"72ec31877fb48e67e039bbb7ef83dc221a883559750ce4fd7a1b668a41cf8e361659b0159cc8fa4b405dd76bb405f66237ae57a5e231498fea8a2a8eae46673e1b" // no need to pass a sig since executed onchain
        });
        
        userSafe.recoverUserSafe(newOwnerBytes, signatures);
    }
}