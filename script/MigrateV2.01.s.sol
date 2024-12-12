// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UserSafeLens} from "../src/user-safe/UserSafeLens.sol";
import {UserSafeCore} from "../src/user-safe/UserSafeCore.sol";
import {UserSafeSetters} from "../src/user-safe/UserSafeSetters.sol";
import {CashbackDispatcher} from "../src/cashback-dispatcher/CashbackDispatcher.sol";
import {UserSafeFactory} from "../src/user-safe/UserSafeFactory.sol";
import {DebtManagerCore} from "../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../src/debt-manager/DebtManagerAdmin.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {CashDataProvider} from "../src/utils/CashDataProvider.sol";
import {Utils, ChainConfig} from "./user-safe/Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {GnosisHelpers} from "./GnosisHelper.s.sol";

contract Migrate is Utils, GnosisHelpers {
    address userSafeCoreImpl;
    address userSafeSettersImpl;
    address factoryImpl;
    address debtManagerCoreImpl;
    address debtManagerAdminImpl;
    address cashbackDispatcherImpl;
    address cashDataProviderImpl;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        bytes32 ETHER_FI_WALLET_ROLE = keccak256("ETHER_FI_WALLET_ROLE");
        bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();

        address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
        address currentEtherFiWallet = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
        address newEtherFiWallet = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;

        address cashDataProvider = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "cashDataProviderProxy")
        );
        address userSafeFactory = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "userSafeFactoryProxy")
        );
        address debtManager = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "debtManagerProxy")
        );
        address cashbackDispatcher = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "cashbackDispatcherProxy")
        );

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        {
            userSafeCoreImpl = address(new UserSafeCore{salt: getSalt(USER_SAFE_CORE_IMPL)}(cashDataProvider));
            userSafeSettersImpl = address(new UserSafeSetters{salt: getSalt(USER_SAFE_SETTERS_IMPL)}(cashDataProvider));
            factoryImpl = address(new UserSafeFactory{salt: getSalt(FACTORY_IMPL)}());
            debtManagerCoreImpl = address(new DebtManagerCore{salt: getSalt(DEBT_MANAGER_CORE_IMPL)}());
            debtManagerAdminImpl = address(new DebtManagerAdmin{salt: getSalt(DEBT_MANAGER_ADMIN_IMPL)}());
            cashbackDispatcherImpl = address(new CashbackDispatcher{salt: getSalt(CASHBACK_DISPATCHER_IMPL)}());
            cashDataProviderImpl = address(new CashDataProvider{salt: getSalt(CASH_DATA_PROVIDER_IMPL)}());
            deployLens(owner, cashDataProvider);
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
        }

        {
            // revoke roles
            string memory revokeEtherFiWalletRole = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ETHER_FI_WALLET_ROLE, currentEtherFiWallet));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), revokeEtherFiWalletRole, false)));
            
            string memory revokeCashDataProviderAdminRole = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ADMIN_ROLE, currentEtherFiWallet));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), revokeCashDataProviderAdminRole, false)));
            
            string memory revokeAdminRoleOnFactory = iToHex(abi.encodeWithSignature("revokeRole(bytes32,address)", ADMIN_ROLE, currentEtherFiWallet));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), revokeAdminRoleOnFactory, false)));

        }

        {            
            // grant roles
            string memory grantEtherFiWalletRole = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", ETHER_FI_WALLET_ROLE, newEtherFiWallet));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(cashDataProvider), grantEtherFiWalletRole, false)));
            
            string memory grantAdminRoleOnFactory = iToHex(abi.encodeWithSignature("grantRole(bytes32,address)", ADMIN_ROLE, newEtherFiWallet));
            gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(userSafeFactory), grantAdminRoleOnFactory, true)));
            
            vm.createDir("./output", true);
            string memory path = "./output/UpgradeV2.01.json";

            vm.writeFile(path, gnosisTx);
        }


        revert ("I am just a test");
    }

    function deployLens(address owner, address cashDataProvider) public {
        new UUPSProxy{salt: getSalt(USER_SAFE_LENS_PROXY)}(
            address(new UserSafeLens{salt: getSalt(USER_SAFE_LENS_IMPL)}()),
            abi.encodeWithSelector(
                    UserSafeLens.initialize.selector,
                    owner,
                    address(cashDataProvider)
                )
        );
    }
}