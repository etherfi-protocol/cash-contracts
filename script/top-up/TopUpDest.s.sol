// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "../user-safe/Utils.sol";
import {TopUpDest} from "../../src/top-up/TopUpDest.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployTopUpDest is Utils {
    TopUpDest topUpDest;

    address owner;
    address cashDataProvider;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory chainId = vm.toString(block.chainid);
        string memory file = string.concat(vm.projectRoot(), "/deployments/fixtures/top-up-fixtures.json");
        string memory fixtures = vm.readFile(file);
        owner = stdJson.readAddress(fixtures, string.concat(".", chainId, ".", "owner"));

        string memory deployments = readDeploymentFile();
        cashDataProvider = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "cashDataProviderProxy")
        );

        address topUpDestImpl = address(new TopUpDest{salt: keccak256("topUpDestImpl")}());

        bytes32 salt = keccak256("topUpDestProxy");
        topUpDest = TopUpDest(payable(address(new UUPSProxy{salt: salt}(topUpDestImpl, ""))));
        topUpDest.initialize(owner, cashDataProvider);

        vm.stopBroadcast();
    }
}