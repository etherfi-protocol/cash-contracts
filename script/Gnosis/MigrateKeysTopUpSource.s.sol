// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";

contract MigrateKeysTopUpSource is Utils, GnosisHelpers {
    bytes32 BRIDGER_ROLE = keccak256("BRIDGER_ROLE");

    address currentTopUpBridger = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address newTopUpBridger = 0xb473201cbFc2ed6FEd9eD960fACCD9E733B1C26E;

    address topUpSource = 0xC85276fec421d0CA3c0eFd4be2B7F569bc7b5b99;

    function run() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        string memory revokeTopUpSourceBridgerRole = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", BRIDGER_ROLE, currentTopUpBridger));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpSource), revokeTopUpSourceBridgerRole, false)));

        string memory grantTopUpSourceBridgerRole = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", BRIDGER_ROLE, newTopUpBridger));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpSource), grantTopUpSourceBridgerRole, true)));
        
        vm.createDir("./output", true);
        string memory path = string(abi.encodePacked("./output/MigrateKeys-", vm.toString(block.chainid), ".json"));

        vm.writeFile(path, gnosisTx);
    }
}