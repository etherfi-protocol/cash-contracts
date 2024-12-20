// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";

contract MigrateKeys is Utils, GnosisHelpers {
    bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 TOP_UP_ROLE = keccak256("TOP_UP_ROLE");

    address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
    address cashDataProvider = 0xb1F5bBc3e4DE0c767ace41EAb8A28b837fBA966F;
    address userSafeFactory = 0x18Fa07dF94b4E9F09844e1128483801B24Fe8a27;
    address topUpDestScroll = 0xeb61c16A60ab1b4a9a1F8E92305808F949F4Ea9B;

    address currentEtherFiWallet = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address newEtherFiWallet = 0x20C4f96d14738d10B107036b3D1826D47b584E62;
    address newTopUpAdmin = 0xd6f5D5eadD8B86aA6271C811a503BcD78DdD8eE4;

    function run() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        // revoke roles
        string memory revokeEtherFiWalletRole = iToHex(abi.encodeWithSignature("revokeEtherFiWalletRole(address)", currentEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), revokeEtherFiWalletRole, false)));
        
        string memory revokeAdminRoleOnFactory = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ADMIN_ROLE, currentEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), revokeAdminRoleOnFactory, false)));
        
        string memory revokeTopUpRoleOnTopUpDest = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", TOP_UP_ROLE, currentEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), revokeTopUpRoleOnTopUpDest, false)));

        // grant roles
        string memory grantEtherFiWalletRole = iToHex(abi.encodeWithSignature("grantEtherFiWalletRole(address)", newEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), grantEtherFiWalletRole, false)));
        
        string memory grantAdminRoleOnFactory = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", ADMIN_ROLE, newEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), grantAdminRoleOnFactory, false)));
        
        string memory grantTopUpRoleOnTopUpDest = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", TOP_UP_ROLE, newTopUpAdmin));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), grantTopUpRoleOnTopUpDest, true)));

        vm.createDir("./output", true);
        string memory path = "./output/MigrateKeys.json";

        vm.writeFile(path, gnosisTx);
    }
}