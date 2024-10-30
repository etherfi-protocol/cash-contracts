// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

struct ChainConfig {
    string rpc;
    address usdc;
    address weETH;
    address weEthWethOracle;
    address ethUsdcOracle;
    address swapRouter1InchV6;
    address swapRouterOpenOcean;
    address aaveV3Pool;
    address aaveV3PoolDataProvider;
    address stargateUsdcPool;
}

contract Utils is Script {
    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function getChainConfig(
        string memory chainId
    ) internal view returns (ChainConfig memory) {
        string memory dir = string.concat(
            vm.projectRoot(),
            "/deployments/fixtures/"
        );
        string memory file = string.concat("fixture", ".json");

        string memory inputJson = vm.readFile(string.concat(dir, file));

        ChainConfig memory config;

        config.rpc = stdJson.readString(
            inputJson,
            string.concat(".", chainId, ".", "rpc")
        );

        config.usdc = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "usdc")
        );

        config.weETH = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "weETH")
        );

        config.weEthWethOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "weEthWethOracle")
        );

        config.ethUsdcOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethUsdcOracle")
        );

        config.swapRouter1InchV6 = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "swapRouter1InchV6")
        );

        config.swapRouterOpenOcean = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "swapRouterOpenOcean")
        );

        config.aaveV3Pool = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "aaveV3Pool")
        );

        config.aaveV3PoolDataProvider = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "aaveV3PoolDataProvider")
        );

        config.stargateUsdcPool = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "stargateUsdcPool")
        );

        return config;
    }

    function readDeploymentFile() internal view returns (string memory) {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("deployments", ".json");
        return vm.readFile(string.concat(dir, chainDir, file));
    }

    function writeDeploymentFile(string memory output) internal {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("deployments", ".json");

        // Ensure the directory exists by creating it if needed
        if (!vm.exists(dir)) {
            vm.createDir(dir, true); // The 'true' parameter creates any missing intermediate directories
        }
        if (!vm.exists(chainDir)) {
            vm.createDir(chainDir, true);
        }
        
        vm.writeJson(output, string.concat(dir, chainDir, file));
    }

    function writeUserSafeDeploymentFile(string memory output) internal {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("safe", ".json");
        vm.writeJson(output, string.concat(dir, chainDir, file));
    }

    function addToJsonFile(
        string memory filePath,
        string memory newEntry
    ) internal {
        // Load the existing JSON or initialize an empty JSON if the file is not found
        string memory jsonContent;
        if (vm.exists(filePath)) {
            jsonContent = vm.readFile(filePath);
        } else {
            jsonContent = "{}"; // Initialize as empty JSON
        }

        // Convert the JSON content into a format you can modify (string manipulation here)
        // Append or modify your JSON structure as needed
        // In this example, we assume `newEntry` is a properly formatted JSON snippet you want to merge.
        string memory updatedJson = string.concat(
            "{",
            jsonContent,
            ",",
            newEntry,
            "}"
        );

        // Write the modified JSON back to the file
        vm.writeFile(filePath, updatedJson);
    }


    function isFork(string memory chainId) internal pure returns (bool) {
        if (keccak256(bytes(chainId)) == keccak256(bytes("local")))
            return false;
        else return true;
    }

    function getQuoteOneInch(
        string memory chainId,
        address from,
        address to,
        address srcToken,
        address dstToken,
        uint256 amount
    ) internal returns (bytes memory data) {
        string[] memory inputs = new string[](9);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/getQuote1Inch.ts";
        inputs[3] = chainId;
        inputs[4] = vm.toString(from);
        inputs[5] = vm.toString(to);
        inputs[6] = vm.toString(srcToken);
        inputs[7] = vm.toString(dstToken);
        inputs[8] = vm.toString(amount);

        return vm.ffi(inputs);
    }
}
