// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

struct ChainConfig {
    string rpc;
    address weth;
    address usdc;
    address usdt;
    address weETH;
    address weEthWethOracle;
    address ethUsdcOracle;
    address swapRouter1InchV6;
    address swapRouterOpenOcean;
    address aaveV3Pool;
    address aaveV3PoolDataProvider;
}

contract Utils is Test {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant HUNDRED_PERCENT = 100e18;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SIX_DECIMALS = 1e6;
    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function getChainConfig(
        string memory chainId
    ) internal view returns (ChainConfig memory) {
        ChainConfig memory config;

        string memory dir = string.concat(
            vm.projectRoot(),
            "/deployments/fixtures/"
        );
        string memory file = string.concat("fixture", ".json");

        string memory inputJson = vm.readFile(string.concat(dir, file));

        config.rpc = stdJson.readString(
            inputJson,
            string.concat(".", chainId, ".", "rpc")
        );

        config.weth = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "weth")
        );

        config.usdc = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "usdc")
        );

        config.usdt = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "usdt")
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

        return config;
    }

    function isFork(string memory chainId) internal pure returns (bool) {
        if (keccak256(bytes(chainId)) == keccak256(bytes("local")))
            return false;
        else return true;
    }

    function isScroll(string memory chainId) internal pure returns (bool) {
        if (keccak256(bytes(chainId)) == keccak256(bytes("534352")))
            return true;
        else return false;
    }

    function getQuoteOneInch(
        string memory chainId,
        address from,
        address to,
        address srcToken,
        address dstToken,
        uint256 amount,
        uint8 srcTokenDecimals
    ) internal returns (bytes memory data) {
        string[] memory inputs = new string[](10);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/getQuote1Inch.ts";
        inputs[3] = chainId;
        inputs[4] = vm.toString(from);
        inputs[5] = vm.toString(to);
        inputs[6] = vm.toString(srcToken);
        inputs[7] = vm.toString(dstToken);
        inputs[8] = vm.toString(amount);
        inputs[9] = vm.toString(srcTokenDecimals);

        return vm.ffi(inputs);
    }

    function getQuoteOpenOcean(
        string memory chainId,
        address from,
        address to,
        address srcToken,
        address dstToken,
        uint256 amount,
        uint8 srcTokenDecimals
    ) internal returns (bytes memory data) {
        string[] memory inputs = new string[](10);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/getQuoteOpenOcean.ts";
        inputs[3] = chainId;
        inputs[4] = vm.toString(from);
        inputs[5] = vm.toString(to);
        inputs[6] = vm.toString(srcToken);
        inputs[7] = vm.toString(dstToken);
        inputs[8] = vm.toString(amount);
        inputs[9] = vm.toString(srcTokenDecimals);

        return vm.ffi(inputs);
    }

    function buildAccessControlRevertData(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                role
            );
    }
}
