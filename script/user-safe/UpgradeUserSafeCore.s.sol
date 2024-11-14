// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils, ChainConfig} from "./Utils.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafeCore} from "../../src/user-safe/UserSafeCore.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeUserSafeCore is Utils {
    using stdJson for string;

    UserSafeFactory userSafeFactory;
    UserSafeCore userSafeCoreImpl;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();

        address cashDataProvider = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "cashDataProviderProxy")
        );

        userSafeFactory = UserSafeFactory(
            stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "userSafeFactory")
            )
        );

        userSafeCoreImpl = new UserSafeCore(address(cashDataProvider));

        userSafeFactory.upgradeUserSafeCoreImpl(address(userSafeCoreImpl));

        vm.stopBroadcast();
    }
}