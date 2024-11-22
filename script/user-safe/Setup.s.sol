// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {SwapperOpenOcean} from "../../src/utils/SwapperOpenOcean.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {DebtManagerCore} from "../../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../../src/debt-manager/DebtManagerAdmin.sol";
import {DebtManagerInitializer} from "../../src/debt-manager/DebtManagerInitializer.sol";
import {CashDataProvider, ICashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {EtherFiCashAaveV3Adapter} from "../../src/adapters/aave-v3/EtherFiCashAaveV3Adapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {IWeETH} from "../../src/interfaces/IWeETH.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {UserSafeCore} from "../../src/user-safe/UserSafeCore.sol";
import {SettlementDispatcher} from "../../src/settlement-dispatcher/SettlementDispatcher.sol";
import {UserSafeSetters} from "../../src/user-safe/UserSafeSetters.sol";
import {UserSafeEventEmitter} from "../../src/user-safe/UserSafeEventEmitter.sol";
import {IUserSafe} from "../../src/interfaces/IUserSafe.sol";
import {CashbackDispatcher} from "../../src/cashback-dispatcher/CashbackDispatcher.sol";

contract DeployUserSafeSetup is Utils {
    ERC20 usdc;
    ERC20 weETH;
    ERC20 scr;
    PriceProvider priceProvider;
    SwapperOpenOcean swapper;
    UserSafeEventEmitter userSafeEventEmitter;
    UserSafeCore userSafeCoreImpl;
    UserSafeSetters userSafeSettersImpl;
    UserSafeFactory userSafeFactory;
    IL2DebtManager debtManager;
    CashDataProvider cashDataProvider;
    EtherFiCashAaveV3Adapter aaveV3Adapter;
    SettlementDispatcher settlementDispatcher;
    CashbackDispatcher cashbackDispatcher;
    address etherFiWallet;
    address owner;
    uint256 delay = 300; // 5 min

    // weETH
    uint80 weETH_ltv = 70e18;
    uint80 weETH_liquidationThreshold = 75e18;
    uint96 weETH_liquidationBonus = 5e18; 
    
    // usdc
    uint80 usdc_ltv = 90e18;
    uint80 usdc_liquidationThreshold = 99e18;
    uint96 usdc_liquidationBonus = 1e18; 

    uint64 borrowApyPerSecond = 634195839675; // 20% APR -> 20e18 / (365 days in seconds)
    uint256 supplyCap = 10000000 ether;

    uint32 optimismDestEid = 30111;

    // Shivam Metamask wallets
    address recoverySigner1 = 0x7fEd99d0aA90423de55e238Eb5F9416FF7Cc58eF;
    address recoverySigner2 = 0x24e311DA50784Cf9DB1abE59725e4A1A110220FA;
    string chainId;

    uint256 pepeCashbackPercentage = 200;
    uint256 wojakCashbackPercentage = 300;
    uint256 chadCashbackPercentage = 400;
    uint256 whaleCashbackPercentage = 500;

    address factoryImpl;
    address eventEmitterImpl;
    address debtManagerCoreImpl;
    address debtManagerAdminImpl;
    address debtManagerInitializer;
    address cashDataProviderImpl;
    address settlementDispatcherImpl;
    address cashbackDispatcherImpl;

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
        owner = deployerAddress;

        usdc = ERC20(chainConfig.usdc);
        weETH = ERC20(chainConfig.weETH);
        scr = ERC20(chainConfig.scr);

        settlementDispatcherImpl = address(new SettlementDispatcher{salt: getSalt(SETTLEMENT_DISPATCHER_IMPL)}());
        settlementDispatcher = SettlementDispatcher(payable(address(new UUPSProxy{salt: getSalt(SETTLEMENT_DISPATCHER_PROXY)}(settlementDispatcherImpl, ""))));
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        SettlementDispatcher.DestinationData[] memory destDatas = new SettlementDispatcher.DestinationData[](1);
        destDatas[0] = SettlementDispatcher.DestinationData({
            destEid: optimismDestEid,
            destRecipient: deployerAddress,
            stargate: chainConfig.stargateUsdcPool
        });

        settlementDispatcher.initialize(
            uint48(delay),
            deployerAddress,
            tokens,
            destDatas
        );

        PriceProvider.Config memory weETHConfig = PriceProvider.Config({
            oracle: chainConfig.weEthWethOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(chainConfig.weEthWethOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: true,
            isStableToken: false
        });

        PriceProvider.Config memory ethConfig = PriceProvider.Config({
            oracle: chainConfig.ethUsdcOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(chainConfig.ethUsdcOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false,
            isStableToken: false
        });

        PriceProvider.Config memory usdcConfig = PriceProvider.Config({
            oracle: chainConfig.usdcUsdOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(chainConfig.usdcUsdOracle).decimals(),
            maxStaleness: 10 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false,
            isStableToken: true
        });

        PriceProvider.Config memory scrollConfig = PriceProvider.Config({
            oracle: chainConfig.scrUsdOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(chainConfig.scrUsdOracle).decimals(),
            maxStaleness: 10 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false,
            isStableToken: true
        });

        address[] memory initialTokens = new address[](4);
        initialTokens[0] = address(weETH);
        initialTokens[1] = eth;
        initialTokens[2] = address(usdc);
        initialTokens[3] = address(scr);

        PriceProvider.Config[] memory initialTokensConfig = new PriceProvider.Config[](4);
        initialTokensConfig[0] = weETHConfig;
        initialTokensConfig[1] = ethConfig;
        initialTokensConfig[2] = usdcConfig;
        initialTokensConfig[3] = scrollConfig;

        address priceProviderImpl = address(new PriceProvider{salt: getSalt(PRICE_PROVIDER_IMPL)}());
        priceProvider = PriceProvider(
            address(
                new UUPSProxy{salt: getSalt(PRICE_PROVIDER_PROXY)}(
                    priceProviderImpl,
                    abi.encodeWithSelector(
                        PriceProvider.initialize.selector,
                        owner,
                        initialTokens,
                        initialTokensConfig
                    )
                )
            )
        );

        swapper = new SwapperOpenOcean{salt: getSalt(SWAPPER_OPEN_OCEAN)}(
            chainConfig.swapRouterOpenOcean,
            supportedCollateralTokens
        );

        cashDataProviderImpl = address(new CashDataProvider{salt: getSalt(CASH_DATA_PROVIDER_IMPL)}());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy{salt: getSalt(CASH_DATA_PROVIDER_PROXY)}(cashDataProviderImpl, ""))
        );

        cashbackDispatcherImpl = address(new CashbackDispatcher{salt: getSalt(CASHBACK_DISPATCHER_IMPL)}());
        cashbackDispatcher = CashbackDispatcher(
            address(new UUPSProxy{salt: getSalt(CASHBACK_DISPATCHER_PROXY)}(
                cashbackDispatcherImpl,
                abi.encodeWithSelector(
                    CashbackDispatcher.initialize.selector,
                    address(owner),
                    address(cashDataProvider),
                    address(priceProvider),
                    address(scr)
                )
            ))
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weETH);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        DebtManagerCore.CollateralTokenConfig[]
            memory collateralTokenConfig = new DebtManagerCore.CollateralTokenConfig[](
                2
            );

        collateralTokenConfig[0].ltv = weETH_ltv;
        collateralTokenConfig[0].liquidationThreshold = weETH_liquidationThreshold;
        collateralTokenConfig[0].liquidationBonus = weETH_liquidationBonus;

        collateralTokenConfig[1].ltv = usdc_ltv;
        collateralTokenConfig[1].liquidationThreshold = usdc_liquidationThreshold;
        collateralTokenConfig[1].liquidationBonus = usdc_liquidationBonus;

        debtManagerCoreImpl = address(new DebtManagerCore{salt: getSalt(DEBT_MANAGER_CORE_IMPL)}());
        debtManagerAdminImpl = address(new DebtManagerAdmin{salt: getSalt(DEBT_MANAGER_ADMIN_IMPL)}());
        debtManagerInitializer = address(new DebtManagerInitializer{salt: getSalt(DEBT_MANAGER_INITIALIZER_IMPL)}());
        address debtManagerProxy = address(new UUPSProxy{salt: getSalt(DEBT_MANAGER_PROXY)}(debtManagerInitializer, ""));

        debtManager = IL2DebtManager(address(debtManagerProxy));

        userSafeCoreImpl = new UserSafeCore{salt: getSalt(USER_SAFE_CORE_IMPL)}(address(cashDataProvider));
        userSafeSettersImpl = new UserSafeSetters{salt: getSalt(USER_SAFE_SETTERS_IMPL)}(address(cashDataProvider));
        factoryImpl = address(new UserSafeFactory{salt: getSalt(FACTORY_IMPL)}());
        
        userSafeFactory = UserSafeFactory(
            address(new UUPSProxy{salt: getSalt(FACTORY_PROXY)}(
                factoryImpl, 
                abi.encodeWithSelector(
                    UserSafeFactory.initialize.selector, 
                    delay,
                    owner, 
                    address(cashDataProvider),
                    address(userSafeCoreImpl),
                    address(userSafeSettersImpl)
                ))
            )
        );

        eventEmitterImpl = address(new UserSafeEventEmitter{salt: getSalt(USER_SAFE_EVENT_EMITTER_IMPL)}());
        userSafeEventEmitter = UserSafeEventEmitter(address(
            new UUPSProxy{salt: getSalt(USER_SAFE_EVENT_EMITTER_PROXY)}(
                eventEmitterImpl,
                abi.encodeWithSelector(
                    UserSafeEventEmitter.initialize.selector,
                    delay,
                    owner,
                    address(cashDataProvider)
                )
            )
        ));

        CashDataProvider(address(cashDataProvider)).initialize(abi.encode(
            owner,
            uint64(delay),
            etherFiWallet,
            settlementDispatcher,
            address(debtManager),
            address(priceProvider),
            address(swapper),
            address(aaveV3Adapter),
            address(userSafeFactory),
            address(userSafeEventEmitter),
            address(cashbackDispatcher),
            address(recoverySigner1),
            address(recoverySigner2)
        ));

        ICashDataProvider.UserSafeTiers[] memory userSafeTiers = new ICashDataProvider.UserSafeTiers[](4);
        userSafeTiers[0] = ICashDataProvider.UserSafeTiers.Pepe;
        userSafeTiers[1] = ICashDataProvider.UserSafeTiers.Wojak;
        userSafeTiers[2] = ICashDataProvider.UserSafeTiers.Chad;
        userSafeTiers[3] = ICashDataProvider.UserSafeTiers.Whale;

        uint256[] memory cashbackPercentages = new uint256[](4);
        cashbackPercentages[0] = pepeCashbackPercentage;
        cashbackPercentages[1] = wojakCashbackPercentage;
        cashbackPercentages[2] = chadCashbackPercentage;
        cashbackPercentages[3] = whaleCashbackPercentage;

        cashDataProvider.setTierCashbackPercentage(userSafeTiers, cashbackPercentages);

        DebtManagerInitializer(address(debtManager)).initialize(
            owner,
            uint48(delay),
            address(cashDataProvider)
        );
        DebtManagerCore(debtManagerProxy).upgradeToAndCall(debtManagerCoreImpl, "");
        DebtManagerCore debtManagerCore = DebtManagerCore(debtManagerProxy);
        debtManagerCore.setAdminImpl(debtManagerAdminImpl);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(address(weETH), collateralTokenConfig[0]);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(address(usdc), collateralTokenConfig[1]);
        DebtManagerAdmin(address(debtManagerCore)).supportBorrowToken(
            address(usdc), 
            borrowApyPerSecond, 
            uint128(10 * 10 ** usdc.decimals())
        );

        saveDeployments();

        vm.stopBroadcast();
    }

    function saveDeployments() internal {
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
            "userSafeCoreImpl",
            address(userSafeCoreImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeSettersImpl",
            address(userSafeSettersImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeFactoryImpl",
            address(factoryImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeFactoryProxy",
            address(userSafeFactory)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeEventEmitterImpl",
            address(eventEmitterImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeEventEmitterProxy",
            address(userSafeEventEmitter)
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
            "settlementDispatcherProxy",
            address(settlementDispatcher)
        );
        vm.serializeAddress(
            deployedAddresses,
            "settlementDispatcherImpl",
            address(settlementDispatcherImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "cashbackDispatcherProxy",
            address(cashbackDispatcher)
        );
        vm.serializeAddress(
            deployedAddresses,
            "cashbackDispatcherImpl",
            address(cashbackDispatcherImpl)
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
    }
}
