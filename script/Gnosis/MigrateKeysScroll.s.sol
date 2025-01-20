// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";

contract MigrateKeysScroll is GnosisHelpers {
    bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 TOP_UP_ROLE = keccak256("TOP_UP_ROLE");
    bytes32 BRIDGER_ROLE = keccak256("BRIDGER_ROLE");

    address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
    address cashDataProvider = 0xb1F5bBc3e4DE0c767ace41EAb8A28b837fBA966F;
    address userSafeFactory = 0x18Fa07dF94b4E9F09844e1128483801B24Fe8a27;
    address topUpDestScroll = 0xeb61c16A60ab1b4a9a1F8E92305808F949F4Ea9B;
    address settlementDispatcher = 0x4Dca5093E0bB450D7f7961b5Df0A9d4c24B24786;

    address currentEtherFiWallet = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address currentUserSafeFactoryAdmin = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address currentTopUpAdmin = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address currentDispatcherBridger = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;

    address newUserSafeFactoryAdmin = 0xc8E5a04b85513cDb99ac6301E35f80F039D5dCC5;
    address newTopUpAdminCashBE = 0xc6F5A0182aD9F92dB99562e98e252aFbEaaca582;
    address newEtherFiWallet = 0x334962E5a3997eE1D480EECc64F4809dB308b6f6;
    address newTopUpAdminTopUpBE = 0xb473201cbFc2ed6FEd9eD960fACCD9E733B1C26E;
    address newDispatcherBridger = 0xb473201cbFc2ed6FEd9eD960fACCD9E733B1C26E;

    function run() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        // revoke roles scroll
        string memory revokeEtherFiWalletRole = iToHex(abi.encodeWithSignature("revokeEtherFiWalletRole(address)", currentEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), revokeEtherFiWalletRole, false)));
        
        string memory revokeAdminRoleOnFactory = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ADMIN_ROLE, currentUserSafeFactoryAdmin));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), revokeAdminRoleOnFactory, false)));
        
        string memory revokeTopUpRoleOnTopUpDest = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", TOP_UP_ROLE, currentTopUpAdmin));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), revokeTopUpRoleOnTopUpDest, false)));

        string memory revokeBridgerRoleOnDispatcher = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", BRIDGER_ROLE, currentDispatcherBridger));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(settlementDispatcher), revokeBridgerRoleOnDispatcher, false)));

        // grant roles
        string memory grantEtherFiWalletRole1 = iToHex(abi.encodeWithSignature("grantEtherFiWalletRole(address)", newEtherFiWallet));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), grantEtherFiWalletRole1, false)));

        string memory grantEtherFiWalletRole2 = iToHex(abi.encodeWithSignature("grantEtherFiWalletRole(address)", newUserSafeFactoryAdmin));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), grantEtherFiWalletRole2, false)));
        
        string memory grantAdminRoleOnFactory = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", ADMIN_ROLE, newUserSafeFactoryAdmin));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), grantAdminRoleOnFactory, false)));
        
        string memory grantTopUpRoleOnTopUpDest1 = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", TOP_UP_ROLE, newTopUpAdminCashBE));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), grantTopUpRoleOnTopUpDest1, false)));
        
        string memory grantTopUpRoleOnTopUpDest2 = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", TOP_UP_ROLE, newTopUpAdminTopUpBE));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), grantTopUpRoleOnTopUpDest2, false)));

        string memory grantBridgerRoleOnDispatcher = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", BRIDGER_ROLE, newDispatcherBridger));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(settlementDispatcher), grantBridgerRoleOnDispatcher, true)));

        vm.createDir("./output", true);
        string memory path = string(abi.encodePacked("./output/MigrateKeys-", vm.toString(block.chainid), ".json"));

        vm.writeFile(path, gnosisTx);
    }
}