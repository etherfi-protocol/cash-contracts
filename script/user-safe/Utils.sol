// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

struct ChainConfig {
    string rpc;
    address usdc;
    address weETH;
    address scr;
    address weEthWethOracle;
    address ethUsdcOracle;
    address scrUsdOracle;
    address usdcUsdOracle;
    address swapRouter1InchV6;
    address swapRouterOpenOcean;
    address aaveV3Pool;
    address aaveV3PoolDataProvider;
    address stargateUsdcPool;
}

contract Utils is Script {
    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    string internal FACTORY_PROXY = "FactoryProxy";
    string internal FACTORY_IMPL = "FactoryImpl";
    string internal SETTLEMENT_DISPATCHER_PROXY = "SettlementDispatcherProxy";
    string internal SETTLEMENT_DISPATCHER_IMPL = "SettlementDispatcherImpl";
    string internal CASHBACK_DISPATCHER_PROXY = "CashbackDispatcherProxy";
    string internal CASHBACK_DISPATCHER_IMPL = "CashbackDispatcherImpl";
    string internal PRICE_PROVIDER_PROXY = "PriceProviderProxy";
    string internal PRICE_PROVIDER_IMPL = "PriceProviderImpl";
    string internal SWAPPER_OPEN_OCEAN = "SwapperOpenOcean";
    string internal CASH_DATA_PROVIDER_PROXY = "CashDataProviderProxy";
    string internal CASH_DATA_PROVIDER_IMPL = "CashDataProviderImpl";
    string internal DEBT_MANAGER_PROXY = "DebtManagerProxy";
    string internal DEBT_MANAGER_CORE_IMPL = "DebtManagerCoreImpl";
    string internal DEBT_MANAGER_ADMIN_IMPL = "DebtManagerAdminImpl";
    string internal DEBT_MANAGER_INITIALIZER_IMPL = "DebtManagerInitializerImpl";
    string internal USER_SAFE_CORE_IMPL = "UserSafeCoreImpl";
    string internal USER_SAFE_SETTERS_IMPL = "UserSafeSettersImpl";
    string internal USER_SAFE_EVENT_EMITTER_PROXY = "UserSafeEventEmitterProxy";
    string internal USER_SAFE_EVENT_EMITTER_IMPL = "UserSafeEventEmitterImpl";
    string internal USER_SAFE_LENS_PROXY = "UserSafeLensProxy";
    string internal USER_SAFE_LENS_IMPL = "UserSafeLensImpl";

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

        config.scr = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "scr")
        );

        config.weEthWethOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "weEthWethOracle")
        );

        config.ethUsdcOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethUsdcOracle")
        );

        config.scrUsdOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "scrUsdOracle")
        );

        config.usdcUsdOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "usdcUsdOracle")
        );

        config.usdcUsdOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "usdcUsdOracle")
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
        vm.writeJson(output, string.concat(dir, chainDir, file));
    }

    function writeUserSafeDeploymentFile(string memory output) internal {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("safe", ".json");
        vm.writeJson(output, string.concat(dir, chainDir, file));
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

    function getSalt(string memory contractName) internal pure returns (bytes32) {
        return keccak256(bytes(contractName));
    }
}