// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
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
import {UserSafeLens} from "../../src/user-safe/UserSafeLens.sol";
import {CashbackDispatcher} from "../../src/cashback-dispatcher/CashbackDispatcher.sol";
import {IAccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

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
    UserSafeLens userSafeLens;
    IL2DebtManager debtManager;
    CashDataProvider cashDataProvider;
    EtherFiCashAaveV3Adapter aaveV3Adapter;
    SettlementDispatcher settlementDispatcher;
    CashbackDispatcher cashbackDispatcher;
    address etherFiWallet = 0x2e0BE8D3D9f1833fbACf9A5e9f2d470817Ff0c00;
    address owner = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
    address bridger = 0xA6cf33124cb342D1c604cAC87986B965F428AAC4;
    uint256 delay = 3600; // 1 hour
    address deployerAddress;

    // weETH
    uint80 weETH_ltv = 50e18;
    uint80 weETH_liquidationThreshold = 75e18;
    uint96 weETH_liquidationBonus = 1e18; 
    
    // usdc
    uint80 usdc_ltv = 80e18;
    uint80 usdc_liquidationThreshold = 95e18;
    uint96 usdc_liquidationBonus = 1e18; 
    
    // scroll
    uint80 scroll_ltv = 50e18;
    uint80 scroll_liquidationThreshold = 75e18;
    uint96 scroll_liquidationBonus = 1e18; 

    uint64 borrowApyPerSecond = 158548959919; // 5% APR -> 10e18 / (365 days in seconds)

    uint32 optimismDestEid = 30111;
    address usdc_rykiOpAddress = 0x9B9c3ae1f950EF121eaeADaeEB0Bcf4695603Bff;

    address recoverySigner1 = 0xbED1b10aF02D48DA7dA0Fff26d16E0873AF46706;
    address recoverySigner2 = 0x566E58ac0F2c4BCaF6De63760C56cC3f825C48f5;
    string chainId;

    uint256 pepeCashbackPercentage = 200;
    uint256 wojakCashbackPercentage = 300;
    uint256 chadCashbackPercentage = 400;
    uint256 whaleCashbackPercentage = 400;

    uint128 minShares;

    address factoryImpl;
    address eventEmitterImpl;
    address debtManagerCoreImpl;
    address debtManagerAdminImpl;
    address debtManagerInitializer;
    address cashDataProviderImpl;
    address settlementDispatcherImpl;
    address cashbackDispatcherImpl;
    address userSafeLensImpl;
    address priceProviderImpl;

    address[] supportedCollateralTokens;
    address[] supportedBorrowTokens;

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        chainId = vm.toString(block.chainid);
        ChainConfig memory chainConfig = getChainConfig(chainId);

        supportedCollateralTokens.push(chainConfig.weETH);
        supportedCollateralTokens.push(chainConfig.usdc);
        supportedCollateralTokens.push(chainConfig.scr);

        supportedBorrowTokens.push(chainConfig.usdc);

        usdc = ERC20(chainConfig.usdc);
        weETH = ERC20(chainConfig.weETH);
        scr = ERC20(chainConfig.scr);

        SettlementDispatcher.DestinationData[] memory destDatas = new SettlementDispatcher.DestinationData[](1);
        destDatas[0] = SettlementDispatcher.DestinationData({
            destEid: optimismDestEid,
            destRecipient: usdc_rykiOpAddress,
            stargate: chainConfig.stargateUsdcPool
        });
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        settlementDispatcherImpl = address(new SettlementDispatcher{salt: getSalt(SETTLEMENT_DISPATCHER_IMPL)}());
        settlementDispatcher = SettlementDispatcher(payable(address(
            new UUPSProxy{salt: getSalt(SETTLEMENT_DISPATCHER_PROXY)}(
                settlementDispatcherImpl, 
                abi.encodeWithSelector(
                    SettlementDispatcher.initialize.selector,
                    owner,
                    bridger,
                    tokens,
                    destDatas
                ))
            ))
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
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false,
            isStableToken: false
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

        priceProviderImpl = address(new PriceProvider{salt: getSalt(PRICE_PROVIDER_IMPL)}());
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
                    owner, 
                    address(cashDataProvider),
                    address(userSafeCoreImpl),
                    address(userSafeSettersImpl)
                ))
            )
        );

        userSafeFactory.grantRole(userSafeFactory.ADMIN_ROLE(), etherFiWallet);

        eventEmitterImpl = address(new UserSafeEventEmitter{salt: getSalt(USER_SAFE_EVENT_EMITTER_IMPL)}());
        userSafeEventEmitter = UserSafeEventEmitter(address(
            new UUPSProxy{salt: getSalt(USER_SAFE_EVENT_EMITTER_PROXY)}(
                eventEmitterImpl,
                abi.encodeWithSelector(
                    UserSafeEventEmitter.initialize.selector,
                    owner,
                    address(cashDataProvider)
                )
            )
        ));

        userSafeLensImpl = address(new UserSafeLens{salt: getSalt(USER_SAFE_LENS_IMPL)}());
        userSafeLens = UserSafeLens(address(
            new UUPSProxy{salt: getSalt(USER_SAFE_LENS_PROXY)}(
                userSafeLensImpl,
                abi.encodeWithSelector(
                    UserSafeLens.initialize.selector,
                    owner,
                    address(cashDataProvider)
                )
            )
        ));

        CashDataProvider(address(cashDataProvider)).initialize(
            ICashDataProvider.InitData({
                owner: deployerAddress,
                delay: uint64(delay),
                etherFiWallet: etherFiWallet,
                settlementDispatcher: address(settlementDispatcher),
                etherFiCashDebtManager: address(debtManager),
                priceProvider: address(priceProvider),
                swapper: address(swapper),
                userSafeFactory: address(userSafeFactory),
                userSafeEventEmitter: address(userSafeEventEmitter),
                cashbackDispatcher: address(cashbackDispatcher),
                userSafeLens: address(userSafeLens),
                etherFiRecoverySigner: recoverySigner1,
                thirdPartyRecoverySigner: recoverySigner2
            })
        );

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

        IAccessControlDefaultAdminRules(address(cashDataProvider)).grantRole(cashDataProvider.ADMIN_ROLE(), owner);
        IAccessControlDefaultAdminRules(address(cashDataProvider)).renounceRole(cashDataProvider.ADMIN_ROLE(), deployerAddress);
        IAccessControlDefaultAdminRules(address(cashDataProvider)).beginDefaultAdminTransfer(owner);

        configureDebtManager();

        saveDeployments();

        vm.stopBroadcast();
    }

    function configureDebtManager() internal {
        DebtManagerCore.CollateralTokenConfig[]
            memory collateralTokenConfig = new DebtManagerCore.CollateralTokenConfig[](
                3
            );

        collateralTokenConfig[0].ltv = weETH_ltv;
        collateralTokenConfig[0].liquidationThreshold = weETH_liquidationThreshold;
        collateralTokenConfig[0].liquidationBonus = weETH_liquidationBonus;

        collateralTokenConfig[1].ltv = usdc_ltv;
        collateralTokenConfig[1].liquidationThreshold = usdc_liquidationThreshold;
        collateralTokenConfig[1].liquidationBonus = usdc_liquidationBonus;
        
        collateralTokenConfig[2].ltv = scroll_ltv;
        collateralTokenConfig[2].liquidationThreshold = scroll_liquidationThreshold;
        collateralTokenConfig[2].liquidationBonus = scroll_liquidationBonus;

        DebtManagerInitializer(address(debtManager)).initialize(
            deployerAddress,
            address(cashDataProvider)
        );
        DebtManagerCore debtManagerCore = DebtManagerCore(address(debtManager));
        debtManagerCore.upgradeToAndCall(debtManagerCoreImpl, "");
        debtManagerCore.setAdminImpl(debtManagerAdminImpl);
        
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(supportedCollateralTokens[0], collateralTokenConfig[0]);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(supportedCollateralTokens[1], collateralTokenConfig[1]);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(supportedCollateralTokens[2], collateralTokenConfig[2]);
        
        minShares = uint128(5 * 10 ** ERC20(supportedBorrowTokens[0]).decimals());

        DebtManagerAdmin(address(debtManagerCore)).supportBorrowToken(  
            supportedBorrowTokens[0], 
            borrowApyPerSecond, 
            minShares
        );

        IAccessControlDefaultAdminRules(address(debtManager)).grantRole(debtManager.ADMIN_ROLE(), owner);
        IAccessControlDefaultAdminRules(address(debtManager)).renounceRole(debtManager.ADMIN_ROLE(), deployerAddress);
        IAccessControlDefaultAdminRules(address(debtManager)).beginDefaultAdminTransfer(owner);
    }

    function saveDeployments() internal {
        string memory parentObject = "parent object";

        string memory deployedAddresses = "addresses";

        vm.serializeAddress(deployedAddresses, "usdc", address(usdc));
        vm.serializeAddress(deployedAddresses, "weETH", address(weETH));
        vm.serializeAddress(
            deployedAddresses,
            "priceProviderProxy",
            address(priceProvider)
        );
        vm.serializeAddress(
            deployedAddresses,
            "priceProviderImpl",
            address(priceProviderImpl)
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
            "userSafeLensImpl",
            address(userSafeLensImpl)
        );
        vm.serializeAddress(
            deployedAddresses,
            "userSafeLensProxy",
            address(userSafeLens)
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
