// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../../script/user-safe/Utils.sol";
import {TopUpSource} from "../../src/top-up/TopUpSource.sol";

contract UpgradeTopUpSource is Utils, GnosisHelpers {
    address topUpSource = 0xC85276fec421d0CA3c0eFd4be2B7F569bc7b5b99;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));
        address topUpSourceImpl = address(new TopUpSource());

        string memory upgradeTopUpSource = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", topUpSourceImpl, ""));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpSource), upgradeTopUpSource, true)));

        vm.createDir("./output", true);
        string memory path = string(abi.encodePacked("./output/UpgradeTopUpSrc", "-", vm.toString(block.chainid), ".json"));

        vm.writeFile(path, gnosisTx);
        
        vm.stopBroadcast();
    }
}