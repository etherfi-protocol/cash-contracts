// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "./Utils.sol";
import {CashSafe} from "../../src/cash-safe/CashSafe.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeCashSafe is Utils {
    using stdJson for string;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();

        address cashSafeProxy = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "cashSafeProxy")
        );


        address cashSafeImpl = address(new CashSafe());
        UUPSUpgradeable(cashSafeProxy).upgradeToAndCall(cashSafeImpl, "");

        vm.stopBroadcast();
    }
}