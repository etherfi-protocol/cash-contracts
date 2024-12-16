// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UserSafeLens} from "../src/user-safe/UserSafeLens.sol";
import {UserSafeCore} from "../src/user-safe/UserSafeCore.sol";
import {UserSafeSetters} from "../src/user-safe/UserSafeSetters.sol";
import {CashbackDispatcher} from "../src/cashback-dispatcher/CashbackDispatcher.sol";
import {SettlementDispatcher} from "../src/settlement-dispatcher/SettlementDispatcher.sol";
import {UserSafeFactory} from "../src/user-safe/UserSafeFactory.sol";
import {DebtManagerCore} from "../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../src/debt-manager/DebtManagerAdmin.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {CashDataProvider} from "../src/utils/CashDataProvider.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {GnosisHelpers} from "../utils/GnosisHelpers.sol";
import {Utils} from "./user-safe/Utils.sol";

contract MigrateMvp is Utils, GnosisHelpers {
    bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 TOP_UP_ROLE = keccak256("TOP_UP_ROLE");

    address cashDataProvider = 0xb1F5bBc3e4DE0c767ace41EAb8A28b837fBA966F;
    address userSafeFactory = 0x18Fa07dF94b4E9F09844e1128483801B24Fe8a27;
    address debtManager = 0x8f9d2Cd33551CE06dD0564Ba147513F715c2F4a0;
    address cashbackDispatcher = 0x7d372C3ca903CA2B6ecd8600D567eb6bAfC5e6c9;
    address settlementDispatcher = 0x4Dca5093E0bB450D7f7961b5Df0A9d4c24B24786;
    address topUpDestScroll = 0xeb61c16A60ab1b4a9a1F8E92305808F949F4Ea9B;

    address userSafeLens;
    address userSafeCoreImpl;
    address userSafeSettersImpl;
    address factoryImpl;
    address debtManagerCoreImpl;
    address debtManagerAdminImpl;
    address cashbackDispatcherImpl;
    address cashDataProviderImpl;

    // Scroll
    address usdc = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    // https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/technical-reference/mainnet-contracts#scroll
    address stargateUsdcPool = 0x3Fc69CC4A842838bCDC9499178740226062b14E4;
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 optimismDestEid = 30111;
    address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
    address currentEtherFiWallet = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address newEtherFiWallet = 0x20C4f96d14738d10B107036b3D1826D47b584E62;
    address newTopUpAdmin = 0xd6f5D5eadD8B86aA6271C811a503BcD78DdD8eE4;
    address newRykiOPAddress = 0x6f7F522075AA5483d049dF0Ef81FcdD3b0ace7f4;


    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        {
            userSafeCoreImpl = address(new UserSafeCore{salt: getSalt(USER_SAFE_CORE_IMPL)}(cashDataProvider));
            userSafeSettersImpl = address(new UserSafeSetters{salt: getSalt(USER_SAFE_SETTERS_IMPL)}(cashDataProvider));
            factoryImpl = address(new UserSafeFactory{salt: getSalt(FACTORY_IMPL)}());
            debtManagerCoreImpl = address(new DebtManagerCore{salt: getSalt(DEBT_MANAGER_CORE_IMPL)}());
            debtManagerAdminImpl = address(new DebtManagerAdmin{salt: getSalt(DEBT_MANAGER_ADMIN_IMPL)}());
            cashbackDispatcherImpl = address(new CashbackDispatcher{salt: getSalt(CASHBACK_DISPATCHER_IMPL)}());
            cashDataProviderImpl = address(new CashDataProvider{salt: getSalt(CASH_DATA_PROVIDER_IMPL)}());
            userSafeLens = deployLens();
        }

        {
            address[] memory tokens = new address[](1);
            tokens[0] = usdc;
            SettlementDispatcher.DestinationData[] memory configs = new SettlementDispatcher.DestinationData[](1); 
            configs[0] = SettlementDispatcher.DestinationData({
                destEid: optimismDestEid,
                destRecipient: newRykiOPAddress,
                stargate: stargateUsdcPool
            });

            string memory settlementDispatcherRykiAddressUpgrade = iToHex(abi.encodeWithSignature("setDestinationData(address[],(uint32,address,address)[])", tokens, configs));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(settlementDispatcher), settlementDispatcherRykiAddressUpgrade, false)));
        }
        
        {
            string memory userSafeFactoryUpgrade = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", factoryImpl, ""));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), userSafeFactoryUpgrade, false)));

            string memory userSafeCoreUpgrade = iToHex(abi.encodeWithSignature("upgradeUserSafeCoreImpl(address)", userSafeCoreImpl));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), userSafeCoreUpgrade, false)));

            string memory userSafeSettersUpgrade = iToHex(abi.encodeWithSignature("setUserSafeSettersImpl(address)", userSafeSettersImpl));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), userSafeSettersUpgrade, false)));

            string memory debtManagerCoreUpgrade = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", debtManagerCoreImpl, ""));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(debtManager), debtManagerCoreUpgrade, false)));

            string memory debtManagerAdminUpgrade = iToHex(abi.encodeWithSignature("setAdminImpl(address)", debtManagerAdminImpl));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(debtManager), debtManagerAdminUpgrade, false)));
            
            string memory cashbackDispatcherUpgrade = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", cashbackDispatcherImpl, ""));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashbackDispatcher), cashbackDispatcherUpgrade, false)));
            
            string memory cashDataProviderUpgrade = iToHex(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", cashDataProviderImpl, ""));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), cashDataProviderUpgrade, false)));
            
            string memory cashDataProviderSetUserSafeLens = iToHex(abi.encodeWithSignature("setUserSafeLens(address)", userSafeLens));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), cashDataProviderSetUserSafeLens, false)));
        }

        {
            // revoke roles
            // string memory revokeEtherFiWalletRole = iToHex(abi.encodeWithSignature("revokeEtherFiWalletRole(address)", currentEtherFiWallet));
            // gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), revokeEtherFiWalletRole, false)));
            
            string memory revokeCashDataProviderAdminRole = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ADMIN_ROLE, currentEtherFiWallet));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), revokeCashDataProviderAdminRole, true)));
            
            // string memory revokeAdminRoleOnFactory = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ADMIN_ROLE, currentEtherFiWallet));
            // gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), revokeAdminRoleOnFactory, false)));
            
            // string memory revokeTopUpRoleOnTopUpDest = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", TOP_UP_ROLE, currentEtherFiWallet));
            // gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), revokeTopUpRoleOnTopUpDest, false)));
        }

        {            
            // grant roles
            // string memory grantEtherFiWalletRole = iToHex(abi.encodeWithSignature("grantEtherFiWalletRole(address)", newEtherFiWallet));
            // gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), grantEtherFiWalletRole, false)));
            
            // string memory grantAdminRoleOnFactory = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", ADMIN_ROLE, newEtherFiWallet));
            // gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), grantAdminRoleOnFactory, false)));
            
            // string memory grantTopUpRoleOnTopUpDest = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", TOP_UP_ROLE, newTopUpAdmin));
            // gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(topUpDestScroll), grantTopUpRoleOnTopUpDest, true)));

            vm.createDir("./output", true);
            string memory path = "./output/UpgradeV2.01.json";

            vm.writeFile(path, gnosisTx);
        }

        vm.stopBroadcast();
    }

    function deployLens() public returns (address) {
        return address(new UUPSProxy{salt: getSalt(USER_SAFE_LENS_PROXY)}(
            address(new UserSafeLens{salt: getSalt(USER_SAFE_LENS_IMPL)}()),
            abi.encodeWithSelector(
                    UserSafeLens.initialize.selector,
                    owner,
                    address(cashDataProvider)
                )
        ));
    }
}