// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "./Utils.sol";
import {SettlementDispatcher} from "../../src/settlement-dispatcher/SettlementDispatcher.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeSettlementDispatcher is Utils {
    using stdJson for string;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();

        address settlementDispatcherProxy = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "settlementDispatcherProxy")
        );


        address settlementDispatcherImpl = address(new SettlementDispatcher());
        UUPSUpgradeable(settlementDispatcherProxy).upgradeToAndCall(settlementDispatcherImpl, "");

        vm.stopBroadcast();
    }
}