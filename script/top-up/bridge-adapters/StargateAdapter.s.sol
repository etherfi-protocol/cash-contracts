// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "../../user-safe/Utils.sol";
import {TopUpSource} from "../../../src/top-up/TopUpSource.sol";
import {UUPSProxy} from "../../../src/UUPSProxy.sol";
import {StargateAdapter} from "../../../src/top-up/bridges/StargateAdapter.sol";

contract DeployStargateAdapter is Utils {
    StargateAdapter stargateAdapter;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        bytes32 salt = keccak256("stargateAdapter");
        stargateAdapter = new StargateAdapter{salt: salt}(); 
    }
}