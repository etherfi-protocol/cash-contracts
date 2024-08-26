// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils, ChainConfig} from "./Utils.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src/user-safe/UserSafe.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeUserSafe is Utils {
    using stdJson for string;

    UserSafeFactory userSafeFactory;
    UserSafe userSafeImpl;

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

        address recoverySigner1 = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "recoverySigner1")
        );

        address recoverySigner2 = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "recoverySigner2")
        );

        userSafeFactory = UserSafeFactory(
            stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "userSafeFactory")
            )
        );

        userSafeImpl = new UserSafe(
            cashDataProvider,
            recoverySigner1,
            recoverySigner2
        );

        userSafeFactory.upgradeTo(address(userSafeImpl));

        vm.stopBroadcast();
    }
}
