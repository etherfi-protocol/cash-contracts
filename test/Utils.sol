// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

struct ChainConfig {
    string rpc;
    address usdc;
    address weETH;
    address weEthWethOracle;
    address ethUsdcOracle;
    address swapRouter1InchV6;
}

contract Utils is Test {
    function getChainConfig(
        string memory chainId
    ) internal view returns (ChainConfig memory) {
        string memory dir = string.concat(vm.projectRoot(), "/test/fixtures/");
        string memory file = string.concat("fixture", ".json");

        string memory inputJson = vm.readFile(string.concat(dir, file));

        string memory rpc = stdJson.readString(
            inputJson,
            string.concat(".", chainId, "rpc")
        );

        address usdc = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, "usdc")
        );

        address weETH = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, "weETH")
        );

        address weEthWethOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, "weEthWethOracle")
        );

        address ethUsdcOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, "ethUsdcOracle")
        );

        address swapRouter1InchV6 = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, "swapRouter1InchV6")
        );

        return
            ChainConfig({
                rpc: rpc,
                usdc: usdc,
                weETH: weETH,
                weEthWethOracle: weEthWethOracle,
                ethUsdcOracle: ethUsdcOracle,
                swapRouter1InchV6: swapRouter1InchV6
            });
    }
}
