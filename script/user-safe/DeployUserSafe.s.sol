// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils, ChainConfig} from "./Utils.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {IUserSafe} from "../../src/interfaces/IUserSafe.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {UserSafeCore} from "../../src/user-safe/UserSafeCore.sol";

contract DeployUserSafe is Utils {
    UserSafeFactory userSafeFactory;
    IUserSafe ownerSafe;
    uint256 defaultDailySpendingLimit = 1000e6;
    uint256 defaultMonthlySpendingLimit = 10000e6;
    uint256 collateralLimit = 10000e6;
    int256 timezoneOffset = 4 * 3600; // Dubai Timezone
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
                string.concat(".", "addresses", ".", "userSafeFactoryProxy")
            )
        );
        address cashDataProvider = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "cashDataProviderProxy")
        );

        bytes memory saltData = abi.encode("ownerSafe", block.timestamp);
        
        ownerSafe = IUserSafe(
            userSafeFactory.createUserSafe(
                saltData,
                abi.encodeWithSelector(
                    UserSafeCore.initialize.selector,
                    abi.encode(ownerEoa),
                    defaultDailySpendingLimit,
                    defaultMonthlySpendingLimit,
                    collateralLimit,
                    timezoneOffset
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