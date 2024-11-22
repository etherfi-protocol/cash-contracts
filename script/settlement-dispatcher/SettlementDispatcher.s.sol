// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import {Script} from "forge-std/Script.sol";
import {SettlementDispatcher} from "../../src/settlement-dispatcher/SettlementDispatcher.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
contract DeploySettlementDispatcher is Script {
    SettlementDispatcher settlementDispatcher;  
    // Scroll
    address usdc = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    // https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/technical-reference/mainnet-contracts#scroll
    address stargateUsdcPool = 0x3Fc69CC4A842838bCDC9499178740226062b14E4;
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 optimismDestEid = 30111;
    uint48 accessControlDelay = 100;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        address settlementDispatcherImpl = address(new SettlementDispatcher());
        address[] memory tokens = new address[](1); 
        tokens[0] = address(usdc);

        SettlementDispatcher.DestinationData[] memory destDatas = new SettlementDispatcher.DestinationData[](1);
        destDatas[0] = SettlementDispatcher.DestinationData({
            destEid: optimismDestEid,
            destRecipient: deployerAddress,
            stargate: stargateUsdcPool
        });
        
        settlementDispatcher = SettlementDispatcher(payable(address(new UUPSProxy(
            settlementDispatcherImpl, 
            abi.encodeWithSelector(
                SettlementDispatcher.initialize.selector, 
                accessControlDelay, 
                deployerAddress, 
                tokens, 
                destDatas
            )
        ))));

        CashDataProvider cashDataProvider = CashDataProvider(0x61D76fB1eb4645F30dE515d0483Bf3488F4a2B99);
        cashDataProvider.setSettlementDispatcher(address(settlementDispatcher));

        vm.stopBroadcast();
    }
}