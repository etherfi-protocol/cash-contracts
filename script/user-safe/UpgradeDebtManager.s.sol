// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils, ChainConfig} from "./Utils.sol";
import {L2DebtManager} from "../../src/L2DebtManager.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeDebtManager is Utils {
    using stdJson for string;

    L2DebtManager debtManagerProxy;
    address debtManagerImpl;

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

        debtManagerProxy = L2DebtManager(
            stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "debtManagerProxy")
            )
        );

        debtManagerImpl = address(new L2DebtManager(address(cashDataProvider)));

        debtManagerProxy.upgradeToAndCall(debtManagerImpl, "");

        vm.stopBroadcast();
    }
}
