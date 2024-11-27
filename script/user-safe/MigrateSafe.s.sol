// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IUserSafe, OwnerLib} from "../../src/interfaces/IUserSafe.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafeCore} from "../../src/user-safe/UserSafeCore.sol";

interface IUserSafeMigrate {
    function migrate(address[] memory tokens, address newUserSafe) external;
}

contract UserSafeMigrate is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint256 dailyLimit = 10000e6;
        uint256 monthlyLimit = 100000e6;
        int256 sykoTimeZone = 9 * 3600;
        address sykoSafe = 0x0b265b7C45a70D02349265875FF8075057287560;  
        
        OwnerLib.OwnerObject memory owner = IUserSafe(sykoSafe).owner();
        UserSafeFactory factory = UserSafeFactory(0x18Fa07dF94b4E9F09844e1128483801B24Fe8a27);

        if (owner.x == 0) revert ("OwnerNotAPasskey");

        address newSafe = factory.createUserSafe(
            "sykoSafeV2", 
            abi.encodeWithSelector(
                UserSafeCore.initialize.selector,
                abi.encode(owner.x, owner.y),
                dailyLimit,
                monthlyLimit,
                sykoTimeZone
            )
        );

        vm.stopBroadcast();
        
        address[] memory tokens = new address[](3);
        tokens[0] = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4; // USDC
        tokens[1] = 0xf55BEC9cafDbE8730f096Aa55dad6D22d44099Df; // USDT
        tokens[2] = 0x01f0a31698C4d065659b9bdC21B3610292a1c506; // weETH

        deployerPrivateKey = vm.envUint("OLD_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        IUserSafeMigrate(sykoSafe).migrate(tokens, newSafe);
        vm.stopBroadcast();
    }
}