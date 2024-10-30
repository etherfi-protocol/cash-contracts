// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Utils} from "../user-safe/Utils.sol";
import {TopUpSource} from "../../src/top-up/TopUpSource.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Console.sol";

struct TokenConfig {
    string token;
    string bridge;
    address recipient;
    uint256 slippage;
    address stargatePool;
    address oftAdapter;
}

contract TopUpSourceSetConfig is Utils {
    TopUpSource topUpSrc;
    address stargateAdapter;
    address etherFiOFTBridgeAdapter;
    
    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        string memory chainId = vm.toString(block.chainid);
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat(dir, chainDir, "top-ups", ".json");

        if (!vm.exists(file)) revert ("Deployment file not found");
        string memory deployments = vm.readFile(file);

        topUpSrc = TopUpSource(
            payable(
                stdJson.readAddress(
                    deployments,
                    string.concat(".", "topUps", ".", "topUpSourceProxy")
                )
            )
        );

        stargateAdapter = stdJson.readAddress(
            deployments,
            string.concat(".", "stargateAdapter")
        );
        etherFiOFTBridgeAdapter = stdJson.readAddress(
            deployments,
            string.concat(".", "etherFiOFTBridgeAdapter")
        );
        
        string memory fixturesFile = string.concat(vm.projectRoot(), "/deployments/fixtures/top-up-fixtures.json");
        string memory fixtures = vm.readFile(fixturesFile);

        (address[] memory tokens, TopUpSource.TokenConfig[] memory tokenConfig) = parseTokenConfigs(fixtures, chainId);

        topUpSrc.setTokenConfig(tokens, tokenConfig);
    
        vm.stopBroadcast();
    }   

    // Helper function to parse token configs from JSON
    function parseTokenConfigs(string memory jsonString, string memory chainId) internal view returns (address[] memory tokens, TopUpSource.TokenConfig[] memory tokenConfig) {
        uint256 count = getTokenConfigsLength(jsonString, chainId);
        tokens = new address[](count);
        tokenConfig = new TopUpSource.TokenConfig[](count);
        
        for (uint256 i = 0; i < count; i++) {
            string memory base = string.concat(".", chainId, ".tokenConfigs[", vm.toString(i), "]");
            
            tokens[i] = stdJson.readAddress(jsonString, string.concat(base, ".address"));
            tokenConfig[i].recipientOnDestChain = stdJson.readAddress(jsonString, string.concat(base, ".recipientOnDestChain"));
            tokenConfig[i].maxSlippageInBps = uint96(stdJson.readUint(jsonString, string.concat(base, ".maxSlippageInBps")));
            string memory bridge = stdJson.readString(jsonString, string.concat(base, ".bridge"));

            if (keccak256(bytes(bridge)) == keccak256(bytes("stargate"))) {
                tokenConfig[i].bridgeAdapter = stargateAdapter;
                tokenConfig[i].additionalData = abi.encode(stdJson.readAddress(jsonString, string.concat(base, ".stargatePool")));
            } else if (keccak256(bytes(bridge)) == keccak256(bytes("oftBridgeAdapter"))) {
                tokenConfig[i].bridgeAdapter = etherFiOFTBridgeAdapter;
                tokenConfig[i].additionalData = abi.encode(stdJson.readAddress(jsonString, string.concat(base, ".oftAdapter")));
            } else revert ("Unknown bridge");

            if (tokenConfig[i].recipientOnDestChain == address(0)) revert (string.concat("Invalid recipientOnDestChain for token ", stdJson.readString(jsonString, string.concat(base, ".token"))));
            if (tokenConfig[i].maxSlippageInBps > 10000) revert (string.concat("Invalid maxSlippageInBps for token ", stdJson.readString(jsonString, string.concat(base, ".token"))));
            if (tokenConfig[i].bridgeAdapter == address(0)) revert (string.concat("Invalid bridgeAdapter for token ", stdJson.readString(jsonString, string.concat(base, ".token"))));
        }
        
        return (tokens, tokenConfig);
    }

    // First, let's create a helper to find the array length
    function getTokenConfigsLength(string memory jsonString, string memory chainId) internal view returns (uint256) {
        uint256 i = 0;
        // Keep checking indices until we get an invalid entry
        while (true) {
            string memory path = string.concat(
                ".", 
                chainId, 
                ".tokenConfigs[",
                vm.toString(i),
                "].address"
            );
            
            // This will revert if the index doesn't exist
            try this.getValue(jsonString, path) returns (address) {
                i++;
            } catch {
                break;
            }
        }
        return i;
    }

    function getValue(string memory jsonString, string memory path) external pure returns (address) {
        return stdJson.readAddress(jsonString, path);
    }
}