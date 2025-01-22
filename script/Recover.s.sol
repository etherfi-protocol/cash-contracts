// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {console} from "forge-std/console.sol";
import {IUserSafe} from "../src/interfaces/IUserSafe.sol";

contract RecoverSafe is Script {
    using MessageHashUtils for bytes32;

    bytes32 public constant RECOVERY_METHOD = keccak256("recoverUserSafe");
    
    IUserSafe userSafe = IUserSafe(0x0c188cD4679C7337Ef1dFC97B7af55461B62Aa3e);
    bytes newOwnerBytes = hex"b8f875ac054b9d83d37f340a08d04106d26a1b094171b4eebc01dbd47c6cba13e4603e8e90bb076073272b2a9be265b7dfb260ec088f7732f51957413355474d";
    
    function run() external {      
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

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

        vm.stopBroadcast();
    }
}