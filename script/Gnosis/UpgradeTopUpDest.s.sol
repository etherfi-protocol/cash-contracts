// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";
import {TopUpDest} from "../../src/top-up/TopUpDest.sol";

contract MigrateTopUpDest is Utils, GnosisHelpers {
    address topUpDest = 0xeb61c16A60ab1b4a9a1F8E92305808F949F4Ea9B;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));
        address topUpDestImpl = address(new TopUpDest());
        
        string memory upgradeTopUpDest = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", topUpDestImpl, ""));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDest), upgradeTopUpDest, true)));

        vm.createDir("./output", true);
        string memory path = string(abi.encodePacked("./output/UpgradeTopUpDest.json"));

        vm.writeFile(path, gnosisTx);
        
        vm.stopBroadcast();
    }
}