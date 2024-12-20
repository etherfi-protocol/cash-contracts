// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";

contract AddFundsToTopUpContract is GnosisHelpers, Utils {
    address fundsSender = 0x261bEC28B8a3BB5098436c9a918bED1270FFF1E4;
    address usdc = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    uint256 amount = 100_000e6;
    address topUpDest = 0xeb61c16A60ab1b4a9a1F8E92305808F949F4Ea9B;

    function run() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        string memory approval = iToHex(abi.encodeWithSignature("approve(address,uint256)", topUpDest, amount));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(usdc), approval, false)));

        string memory addFunds = iToHex(abi.encodeWithSignature("deposit(address,uint256)", usdc, amount));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDest), addFunds, true)));

        vm.createDir("./output", true);
        string memory path = "./output/AddFundsToTopUpDest.json";

        vm.writeFile(path, gnosisTx);

        executeGnosisTransactionBundle(path, fundsSender);
    }
}