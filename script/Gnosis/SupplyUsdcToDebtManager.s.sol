// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";
import "forge-std/Test.sol";

contract SupplyUsdcToDebtManager is GnosisHelpers, Utils, Test {
    address fundsSender = 0x261bEC28B8a3BB5098436c9a918bED1270FFF1E4;
    address usdc = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    uint256 amount = 100_000e6;
    address debtManager = 0x8f9d2Cd33551CE06dD0564Ba147513F715c2F4a0;

    function run() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        string memory approval = iToHex(abi.encodeWithSignature("approve(address,uint256)", debtManager, amount));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(usdc), approval, false)));

        string memory addFunds = iToHex(abi.encodeWithSignature("supply(address,address,uint256)", fundsSender, usdc, amount));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(debtManager), addFunds, true)));

        vm.createDir("./output", true);
        string memory path = "./output/SupplyUsdcToDebtManager.json";

        vm.writeFile(path, gnosisTx);

        executeGnosisTransactionBundle(path, fundsSender);
    }
}