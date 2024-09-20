// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils, ChainConfig} from "./Utils.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src/user-safe/UserSafe.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployUserSafe is Utils {
    UserSafeFactory userSafeFactory;
    UserSafe ownerSafe;
    uint256 defaultSpendingLimit = 10000e6;
    uint256 collateralLimit = 10000e6;
    address ownerEoa;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        if (ownerEoa == address(0)) ownerEoa = deployer;

        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();

        userSafeFactory = UserSafeFactory(
            stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "userSafeFactory")
            )
        );

        bytes memory saltData = abi.encode("ownerSafe", block.timestamp);
        
        ownerSafe = UserSafe(
            userSafeFactory.createUserSafe(
                saltData,
                abi.encodeWithSelector(
                    // initialize(bytes,uint256,uint256)
                    0x32b218ac,
                    abi.encode(ownerEoa),
                    defaultSpendingLimit,
                    collateralLimit
                )
            )
        );

        string memory parentObject = "parent object";
        string memory deployedAddresses = "addresses";

        vm.serializeAddress(deployedAddresses, "owner", ownerEoa);
        string memory addressOutput = vm.serializeAddress(
            deployedAddresses,
            "safe",
            address(ownerSafe)
        );

        // serialize all the data
        string memory finalJson = vm.serializeString(
            parentObject,
            deployedAddresses,
            addressOutput
        );

        writeUserSafeDeploymentFile(finalJson);
        vm.stopBroadcast();
    }
}
