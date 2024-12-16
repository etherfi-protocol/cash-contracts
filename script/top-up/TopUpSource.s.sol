// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "../user-safe/Utils.sol";
import {TopUpSource} from "../../src/top-up/TopUpSource.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployTopUpSource is Utils {
    TopUpSource topUpSrc;

    address weth;
    address owner;
    address recoveryWallet;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory chainId = vm.toString(block.chainid);
        string memory file = string.concat(vm.projectRoot(), "/deployments/fixtures/top-up-fixtures.json");
        string memory fixtures = vm.readFile(file);
        weth = stdJson.readAddress(fixtures, string.concat(".", chainId, ".", "weth"));
        owner = vm.addr(deployerPrivateKey);

        address topUpSrcImpl = address(new TopUpSource{salt: keccak256("topUpSourceImpl")}());

        bytes32 salt = keccak256("topUpSourceProxy");
        topUpSrc = TopUpSource(payable(address(new UUPSProxy{salt: salt}(topUpSrcImpl, ""))));
        topUpSrc.initialize(weth, owner);

        vm.stopBroadcast();
    }
}