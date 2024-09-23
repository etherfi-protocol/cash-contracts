// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src/user-safe/UserSafe.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {SwapperOpenOcean} from "../../src/utils/SwapperOpenOcean.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {DebtManagerCore} from "../../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../../src/debt-manager/DebtManagerAdmin.sol";
import {DebtManagerInitializer} from "../../src/debt-manager/DebtManagerInitializer.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {EtherFiCashAaveV3Adapter} from "../../src/adapters/aave-v3/EtherFiCashAaveV3Adapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {CashTokenWrapperFactory, CashWrappedERC20} from "../../src/cash-wrapper-token/CashTokenWrapperFactory.sol";
import {IWeETH} from "../../src/interfaces/IWeETH.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";


contract DeployUserSafeSetup is Utils {
    ERC20 usdc;
    ERC20 weETH;
    PriceProvider priceProvider;
    SwapperOpenOcean swapper;
    UserSafe userSafeImpl;
    UserSafeFactory userSafeFactory;
    IL2DebtManager debtManager;
    CashDataProvider cashDataProvider;
    EtherFiCashAaveV3Adapter aaveV3Adapter;
    address etherFiCashMultisig;
    address etherFiWallet;
    address owner;
    uint256 delay = 300; // 5 min
    uint80 ltv = 70e18;
    uint80 liquidationThreshold = 75e18;
    uint96 liquidationBonus = 5e18; 

    uint64 borrowApyPerSecond = 634195839675; // 20% APR -> 20e18 / (365 days in seconds)
    uint256 supplyCap = 10000000 ether;

    // Shivam Metamask wallets
    address recoverySigner1 = 0x7fEd99d0aA90423de55e238Eb5F9416FF7Cc58eF;
    address recoverySigner2 = 0x24e311DA50784Cf9DB1abE59725e4A1A110220FA;
    string chainId;
    uint16 aaveV3ReferralCode = 0;
    uint256 interestRateMode = 2; // variable

    CashTokenWrapperFactory wrapperTokenFactory;
    CashWrappedERC20 wrappedERC20Impl;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        chainId = vm.toString(block.chainid);
        ChainConfig memory chainConfig = getChainConfig(chainId);

        address[] memory supportedCollateralTokens = new address[](1);
        supportedCollateralTokens[0] = chainConfig.weETH;
        address[] memory supportedBorrowTokens = new address[](1);
        supportedBorrowTokens[0] = chainConfig.usdc;

        etherFiWallet = deployerAddress;
        etherFiCashMultisig = deployerAddress;
        owner = deployerAddress;

        usdc = ERC20(chainConfig.usdc);
        weETH = ERC20(chainConfig.weETH);

        PriceProvider.Config memory weETHConfig = PriceProvider.Config({
            oracle: chainConfig.weEthWethOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(chainConfig.weEthWethOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: true
        });

        PriceProvider.Config memory ethConfig = PriceProvider.Config({
            oracle: chainConfig.ethUsdcOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(chainConfig.ethUsdcOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });

        address[] memory initialTokens = new address[](2);
        initialTokens[0] = address(weETH);
        initialTokens[1] = eth;

        PriceProvider.Config[]
            memory initialTokensConfig = new PriceProvider.Config[](2);
        initialTokensConfig[0] = weETHConfig;
        initialTokensConfig[1] = ethConfig;

        priceProvider = new PriceProvider(
            owner,
            initialTokens,
            initialTokensConfig
        );
        swapper = new SwapperOpenOcean(
            chainConfig.swapRouterOpenOcean,
            supportedCollateralTokens
        );
        aaveV3Adapter = new EtherFiCashAaveV3Adapter(
            chainConfig.aaveV3Pool,
            chainConfig.aaveV3PoolDataProvider,
            aaveV3ReferralCode,
            interestRateMode
        );

        address cashWrappedERC20Impl = address(new CashWrappedERC20());
        wrapperTokenFactory = new CashTokenWrapperFactory(address(cashWrappedERC20Impl), owner);

        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weETH);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        DebtManagerCore.CollateralTokenConfig[]
            memory collateralTokenConfig = new DebtManagerCore.CollateralTokenConfig[](
                1
            );

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
            address(aaveV3Adapter),
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
}
