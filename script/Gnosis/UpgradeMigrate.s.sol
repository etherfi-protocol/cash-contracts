// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";
import {UserSafeCore} from "../../src/user-safe/UserSafeCore.sol";
import "forge-std/Test.sol";

contract UpgradeMigrate is GnosisHelpers, Utils, Test {
    address cashDataProvider = 0xb1F5bBc3e4DE0c767ace41EAb8A28b837fBA966F;
    address userSafeFactory = 0x18Fa07dF94b4E9F09844e1128483801B24Fe8a27;
    address cashController =0xA6cf33124cb342D1c604cAC87986B965F428AAC4;

    UserSafeCore randomSafe = UserSafeCore(0xc648F8abc7Cd9A157dD5e053a9eA37B944f5e790);
    address etherFiWallet = 0x334962E5a3997eE1D480EECc64F4809dB308b6f6;

    function run() public {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast();

        address userSafeCoreImpl = address(new UserSafeCore(cashDataProvider));
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        string memory userSafeCoreUpgrade = iToHex(abi.encodeWithSignature("upgradeUserSafeCoreImpl(address)", userSafeCoreImpl));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), userSafeCoreUpgrade, true)));

        vm.createDir("./output", true);
        string memory path = "./output/UpgradeMigrate.json";
        vm.writeFile(path, gnosisTx);
        vm.stopBroadcast();

        /// below here is just a test
        executeGnosisTransactionBundle(path, cashController);

        address[] memory tokens = new address[](2);
        tokens[0] = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
        tokens[1] = 0xd29687c813D741E2F938F4aC377128810E217b1b;

        address newSafe = 0x5ebfD422ab7F78c0f4Ca53294A044D70991744f7;

        vm.prank(etherFiWallet);
        randomSafe.migrate(tokens, newSafe);
    }
}