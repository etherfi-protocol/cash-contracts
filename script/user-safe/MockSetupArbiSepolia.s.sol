// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceProvider} from "../../src/mocks/MockPriceProvider.sol";
import {MockSwapper} from "../../src/mocks/MockSwapper.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {DebtManagerCore} from "../../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../../src/debt-manager/DebtManagerAdmin.sol";
import {DebtManagerInitializer} from "../../src/debt-manager/DebtManagerInitializer.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {MockAaveAdapter} from "../../src/mocks/MockAaveAdapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {CashTokenWrapperFactory, CashWrappedERC20} from "../../src/cash-wrapper-token/CashTokenWrapperFactory.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
}

contract DeployMockArbitrumSepoliaSetup is Utils {
    MockERC20 usdc = MockERC20(0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773);
    MockERC20 weETH = MockERC20(0x9Cb88EfE476d3133B7ad48C4e5f625aCD812764b);
    MockERC20 weth = MockERC20(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);
    MockPriceProvider priceProvider = MockPriceProvider(0x9ec8CaCc5f08AbDab75a430732dBCFD9b1b0a029);
    MockSwapper swapper;
    UserSafe userSafeImpl;
    UserSafeFactory userSafeFactory;
    IL2DebtManager debtManager;
    CashDataProvider cashDataProvider;
    MockAaveAdapter aaveAdapter = MockAaveAdapter(0x1a329FaE0ab264328B3c07Eb7218775923E6fFAa);
    address etherFiCashMultisig;
    address etherFiWallet;
    address owner;
    uint256 delay = 60;
    uint80 ltv = 70e18;
    uint80 liquidationThreshold = 75e18;
    uint96 liquidationBonus = 5e18; 
    uint64 borrowApyPerSecond = 634195839675; // 20% APR -> 20e18 / (365 days in seconds)
    uint256 supplyCap = 1000000 ether;

    // Shivam Metamask wallets
    address recoverySigner1 = 0x7fEd99d0aA90423de55e238Eb5F9416FF7Cc58eF;
    address recoverySigner2 = 0x24e311DA50784Cf9DB1abE59725e4A1A110220FA;
    CashTokenWrapperFactory wrapperTokenFactory;
    CashWrappedERC20 wrappedERC20Impl;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        etherFiWallet = deployerAddress;
        etherFiCashMultisig = deployerAddress;
        owner = deployerAddress;

        // usdc = MockERC20(deployErc20("USDC", "USDC", 6));
        // weETH = MockERC20(deployErc20("Wrapped eETH", "weETH", 18));
        // priceProvider = new MockPriceProvider(2500e6);
        swapper = new MockSwapper();
        // aaveAdapter = new MockAaveAdapter();

        IERC20Mintable(address(usdc)).mint(address(swapper), 1000 ether);
        
        address cashWrappedERC20Impl = address(new CashWrappedERC20());
        wrapperTokenFactory = new CashTokenWrapperFactory(address(cashWrappedERC20Impl), owner);

        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(weETH);
        collateralTokens[1] = address(weth);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        DebtManagerCore.CollateralTokenConfig[]
            memory collateralTokenConfig = new DebtManagerCore.CollateralTokenConfig[](
                2
            );

        collateralTokenConfig[0].ltv = ltv;
        collateralTokenConfig[0].liquidationThreshold = liquidationThreshold;
        collateralTokenConfig[0].liquidationBonus = liquidationBonus;
        collateralTokenConfig[0].supplyCap = supplyCap;
        
        collateralTokenConfig[0].ltv = ltv;
        collateralTokenConfig[0].liquidationThreshold = liquidationThreshold;
        collateralTokenConfig[0].liquidationBonus = liquidationBonus;
        collateralTokenConfig[0].supplyCap = supplyCap;

        address debtManagerCoreImpl = address(new DebtManagerCore());
        address debtManagerAdminImpl = address(new DebtManagerAdmin());
        address debtManagerInitializer = address(new DebtManagerInitializer());
        address debtManagerProxy = address(new UUPSProxy(debtManagerInitializer, ""));

        debtManager = IL2DebtManager(address(debtManagerProxy));

        userSafeImpl = new UserSafe(
            address(cashDataProvider),
            recoverySigner1,
            recoverySigner2
        );

        address factoryImpl = address(new UserSafeFactory());
        
        userSafeFactory = UserSafeFactory(
            address(new UUPSProxy(
                factoryImpl, 
                abi.encodeWithSelector(
                    UserSafeFactory.initialize.selector, 
                    delay,
                    address(userSafeImpl), 
                    owner, 
                    address(cashDataProvider)
                ))
            )
        );


        CashDataProvider(address(cashDataProvider)).initialize(
            owner,
            uint64(delay),
            etherFiWallet,
            etherFiCashMultisig,
            address(debtManager),
            address(priceProvider),
            address(swapper),
            address(aaveAdapter),
            address(userSafeFactory)
        );
        
        DebtManagerInitializer(address(debtManager)).initialize(
            owner,
            uint48(delay),
            address(cashDataProvider),
            address(wrapperTokenFactory)
        );
        DebtManagerCore(debtManagerProxy).upgradeToAndCall(debtManagerCoreImpl, "");
        DebtManagerCore debtManagerCore = DebtManagerCore(debtManagerProxy);
        debtManagerCore.setAdminImpl(debtManagerAdminImpl);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(address(weETH), collateralTokenConfig[0]);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(address(weth), collateralTokenConfig[1]);
        DebtManagerAdmin(address(debtManagerCore)).supportBorrowToken(
            address(usdc), 
            borrowApyPerSecond, 
            uint128(10 * 10 ** usdc.decimals())
        );

        string memory parentObject = "parent object";

        string memory deployedAddresses = "addresses";

        vm.serializeAddress(deployedAddresses, "usdc", address(usdc));

        vm.serializeAddress(deployedAddresses, "weETH", address(weETH));
        vm.serializeAddress(
            deployedAddresses,
            "priceProvider",
            address(priceProvider)
        );
        vm.serializeAddress(deployedAddresses, "swapper", address(swapper));
        vm.serializeAddress(
            deployedAddresses,
            "userSafeImpl",
            address(userSafeImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeFactoryImpl",
            address(factoryImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeFactory",
            address(userSafeFactory)
        );
        vm.serializeAddress(
            deployedAddresses,
            "wrapperTokenFactory",
            address(wrapperTokenFactory)
        );
        vm.serializeAddress(
            deployedAddresses,
            "wrappedERC20Impl",
            address(wrappedERC20Impl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "debtManagerProxy",
            address(debtManager)
        );
        vm.serializeAddress(
            deployedAddresses,
            "debtManagerCore",
            address(debtManagerCoreImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "debtManagerAdminImpl",
            address(debtManagerAdminImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "debtManagerInitializer",
            address(debtManagerInitializer)
        );
        vm.serializeAddress(
            deployedAddresses,
            "cashDataProviderProxy",
            address(cashDataProvider)
        );
        vm.serializeAddress(
            deployedAddresses,
            "cashDataProviderImpl",
            address(cashDataProviderImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "etherFiCashMultisig",
            address(etherFiCashMultisig)
        );
        vm.serializeAddress(
            deployedAddresses,
            "etherFiWallet",
            address(etherFiWallet)
        );
        vm.serializeAddress(deployedAddresses, "owner", address(owner));
        vm.serializeAddress(
            deployedAddresses,
            "recoverySigner1",
            address(recoverySigner1)
        );

        string memory addressOutput = vm.serializeAddress(
            deployedAddresses,
            "recoverySigner2",
            address(recoverySigner2)
        );

        // serialize all the data
        string memory finalJson = vm.serializeString(
            parentObject,
            deployedAddresses,
            addressOutput
        );

        writeDeploymentFile(finalJson);

        vm.stopBroadcast();
    }

    function deployErc20(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal returns (address) {
        return address(new MockERC20(name, symbol, decimals));
    }
}
