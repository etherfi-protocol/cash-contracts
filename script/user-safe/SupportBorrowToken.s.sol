// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "./Utils.sol";
import {CashSafe} from "../../src/cash-safe/CashSafe.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {DebtManagerAdmin} from "../../src/debt-manager/DebtManagerAdmin.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SupportBorrowToken is Utils {
    using stdJson for string;

    DebtManagerAdmin debtManagerAdmin;

    address usdt = 0xf55BEC9cafDbE8730f096Aa55dad6D22d44099Df;
    uint64 borrowApy = 634195839675 * 2;
    uint128 minShares = 10e6;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();

        address debtManager = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "debtManagerProxy")
        );

        DebtManagerAdmin(debtManager).supportBorrowToken(usdt, borrowApy, minShares);
    }
}