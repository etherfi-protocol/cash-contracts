// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";

contract SetUsdcConfig is Test, GnosisHelpers {
    address usdc = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address debtManager = 0x8f9d2Cd33551CE06dD0564Ba147513F715c2F4a0;
    address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;

    function setUp() external {
        vm.createSelectFork("https://rpc.scroll.io");
    }

    function test_SetConfig() public {
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 90e18;
        collateralTokenConfig.liquidationThreshold = 95e18;
        collateralTokenConfig.liquidationBonus = 1e18;

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));   
        string memory setCollateralConfig = iToHex(abi.encodeWithSelector(IL2DebtManager.setCollateralTokenConfig.selector, usdc, collateralTokenConfig));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(debtManager), setCollateralConfig, false)));


        string memory setBorrowApyZero = iToHex(abi.encodeWithSelector(IL2DebtManager.setBorrowApy.selector, usdc, 1));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(debtManager), setBorrowApyZero, true)));

        vm.createDir("./output", true);
        string memory path = "./output/SetUsdcConfig.json";

        vm.writeFile(path, gnosisTx);
        
        executeGnosisTransactionBundle(path, owner);
    }
}