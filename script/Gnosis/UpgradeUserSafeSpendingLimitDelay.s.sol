// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UserSafeSetters} from "../../src/user-safe/UserSafeSetters.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {Utils} from "../user-safe/Utils.sol";

contract UpgradeUserSafeSpendingLimitDelay is Utils, GnosisHelpers {
    address userSafeFactory = 0x18Fa07dF94b4E9F09844e1128483801B24Fe8a27;
    address cashDataProvider = 0xb1F5bBc3e4DE0c767ace41EAb8A28b837fBA966F;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address userSafeSettersImpl = address(new UserSafeSetters(cashDataProvider));

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));
        string memory userSafeSettersUpgrade = iToHex(abi.encodeWithSignature("setUserSafeSettersImpl(address)", userSafeSettersImpl));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), userSafeSettersUpgrade, true)));

        vm.createDir("./output", true);
        string memory path = "./output/UpgradeSpendingLimitDelay.json";

        vm.writeFile(path, gnosisTx);

        vm.stopBroadcast();

    }
}