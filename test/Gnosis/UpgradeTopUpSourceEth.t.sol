// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../../script/user-safe/Utils.sol";
import {Test} from "forge-std/Test.sol";
import {TopUpSource} from "../../src/top-up/TopUpSource.sol";

contract TestUpgradeTopUpSourceEth is Test, GnosisHelpers {
    address topUpSource = 0xC85276fec421d0CA3c0eFd4be2B7F569bc7b5b99;
    address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address stargateAdapter = 0x1C83858e006D8D1bfBa09341eB0754181b23c01d;

    function setUp() public {
        vm.createSelectFork("https://eth.llamarpc.com");
    }

    function test_UpgradeTopUpSource() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        address topUpSourceImpl = address(new TopUpSource());

        string memory upgradeTopUpSource = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", topUpSourceImpl, ""));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpSource), upgradeTopUpSource, true)));

        vm.createDir("./output", true);
        string memory path = "./output/UpgradeTopUpSrcEth.json";

        vm.writeFile(path, gnosisTx);
        
        executeGnosisTransactionBundle(path, owner);

        assertEq(TopUpSource(payable(topUpSource)).tokenConfig(usdc).bridgeAdapter, stargateAdapter);
    }
}