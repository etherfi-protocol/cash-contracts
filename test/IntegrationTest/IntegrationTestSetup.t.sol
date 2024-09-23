// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src//user-safe/UserSafe.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {DebtManagerCore} from "../../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../../src/debt-manager/DebtManagerAdmin.sol";
import {DebtManagerInitializer} from "../../src/debt-manager/DebtManagerInitializer.sol";
import {UserSafeV2Mock} from "../../src/mocks/UserSafeV2Mock.sol";
import {SwapperOpenOcean} from "../../src/utils/SwapperOpenOcean.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {OwnerLib} from "../../src/libraries/OwnerLib.sol";
import {Utils, ChainConfig} from "../Utils.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceProvider} from "../../src/mocks/MockPriceProvider.sol";
import {MockSwapper} from "../../src/mocks/MockSwapper.sol";
import {IPool} from "@aave/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave/interfaces/IPoolDataProvider.sol";
import {IEtherFiCashAaveV3Adapter, EtherFiCashAaveV3Adapter} from "../../src/adapters/aave-v3/EtherFiCashAaveV3Adapter.sol";
import {MockAaveAdapter} from "../../src/mocks/MockAaveAdapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {MockCashTokenWrapperFactory} from "../../src/mocks/MockCashTokenWrapperFactory.sol";
import {MockCashWrappedERC20} from "../../src/mocks/MockCashWrappedERC20.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";

contract IntegrationTestSetup is Utils {
    using OwnerLib for address;

    address owner = makeAddr("owner");

    address notOwner = makeAddr("notOwner");

    string chainId;

    uint256 etherFiRecoverySignerPk;
    address etherFiRecoverySigner;
    uint256 thirdPartyRecoverySignerPk;
    address thirdPartyRecoverySigner;

    UserSafeFactory factory;
    UserSafe impl;

    ERC20 usdc;
    ERC20 weETH;
    ERC20 weth;
    SwapperOpenOcean swapper;
    PriceProvider priceProvider;
    CashDataProvider cashDataProvider;

    uint256 mockWeETHPriceInUsd = 3000e6;
    uint256 defaultSpendingLimit = 10000e6;
    uint256 collateralLimit = 10000e6;
    uint64 delay = 10;
    address etherFiCashMultisig = makeAddr("multisig");
    address etherFiWallet = makeAddr("etherFiWallet");

    address weEthWethOracle;
    address ethUsdcOracle;
    address swapRouterOpenOcean;

    address alice;
    uint256 alicePk;
    bytes aliceBytes;
    UserSafe aliceSafe;

    IEtherFiCashAaveV3Adapter aaveV3Adapter;

    IPool aavePool;
    IPoolDataProvider aaveV3PoolDataProvider;
    // Interest rate mode -> Stable: 1, variable: 2
    uint256 interestRateMode = 2;
    uint16 aaveReferralCode = 0;

    IL2DebtManager etherFiCashDebtManager;

    uint80 ltv = 50e18; //50%
    uint80 liquidationThreshold = 60e18; // 60%
    uint96 liquidationBonus = 5e18; // 60%
    uint64 borrowApy = 1000; // 10%
    ChainConfig chainConfig;
    uint256 supplyCap = 10000 ether;

    MockCashTokenWrapperFactory wrapperTokenFactory;
    MockCashWrappedERC20 wweETH;

    function setUp() public virtual {
        chainId = vm.envString("TEST_CHAIN");

        vm.startPrank(owner);

        emit log_named_string("Testing on ChainID", chainId);

        if (!isFork(chainId)) {
            usdc = ERC20(address(new MockERC20("usdc", "usdc", 6)));
            weETH = ERC20(address(new MockERC20("weETH", "weETH", 18)));
            weth = ERC20(address(new MockERC20("weth", "WETH", 18)));

            swapper = SwapperOpenOcean(address(new MockSwapper()));
            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd))
            );
            aaveV3Adapter = IEtherFiCashAaveV3Adapter(new MockAaveAdapter());
        } else {
            chainConfig = getChainConfig(chainId);
            vm.createSelectFork(chainConfig.rpc);

            usdc = ERC20(chainConfig.usdc);
            weETH = ERC20(chainConfig.weETH);
            weth = ERC20(chainConfig.weth);
            weEthWethOracle = chainConfig.weEthWethOracle;
            ethUsdcOracle = chainConfig.ethUsdcOracle;
            swapRouterOpenOcean = chainConfig.swapRouterOpenOcean;

            address[] memory assets = new address[](1);
            assets[0] = address(weETH);

            swapper = new SwapperOpenOcean(swapRouterOpenOcean, assets);
            PriceProvider.Config memory weETHConfig = PriceProvider.Config({
                oracle: weEthWethOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(weEthWethOracle).decimals(),
                maxStaleness: 1 days,
                dataType: PriceProvider.ReturnType.Int256,
                isBaseTokenEth: true
            });
            
            PriceProvider.Config memory ethConfig = PriceProvider.Config({
                oracle: ethUsdcOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(ethUsdcOracle).decimals(),
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

            aavePool = IPool(chainConfig.aaveV3Pool);
            aaveV3PoolDataProvider = IPoolDataProvider(
                chainConfig.aaveV3PoolDataProvider
            );

            aaveV3Adapter = IEtherFiCashAaveV3Adapter(
                new EtherFiCashAaveV3Adapter(
                    address(aavePool),
                    address(aaveV3PoolDataProvider),
                    aaveReferralCode,
                    interestRateMode
                )
            );
        }

        address cashWrappedERC20Impl = address(new MockCashWrappedERC20());
        wrapperTokenFactory = new MockCashTokenWrapperFactory(address(cashWrappedERC20Impl), owner);

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

        etherFiCashDebtManager = IL2DebtManager(address(debtManagerProxy));

        (etherFiRecoverySigner, etherFiRecoverySignerPk) = makeAddrAndKey(
            "etherFiRecoverySigner"
        );

        (thirdPartyRecoverySigner, thirdPartyRecoverySignerPk) = makeAddrAndKey(
            "thirdPartyRecoverySigner"
        );

        impl = new UserSafe(
            address(cashDataProvider),
            etherFiRecoverySigner,
            thirdPartyRecoverySigner
        );

        address factoryImpl = address(new UserSafeFactory());
        
        factory = UserSafeFactory(
            address(new UUPSProxy(
                factoryImpl, 
                abi.encodeWithSelector(
                    UserSafeFactory.initialize.selector, 
                    uint48(delay),
                    address(impl), 
                    owner, 
                    address(cashDataProvider)
                ))
            )
        );

        CashDataProvider(address(cashDataProvider)).initialize(
            owner,
            delay,
            etherFiWallet,
            etherFiCashMultisig,
            address(etherFiCashDebtManager),
            address(priceProvider),
            address(swapper),
            address(aaveV3Adapter),
            address(factory)
        );

        DebtManagerInitializer(address(etherFiCashDebtManager)).initialize(
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
            borrowApy, 
            uint128(10 * 10 ** usdc.decimals())
        );

        (alice, alicePk) = makeAddrAndKey("alice");
        aliceBytes = abi.encode(alice);

        bytes memory saltData = bytes("aliceSafe");

        aliceSafe = UserSafe(
            factory.createUserSafe(
                saltData,
                abi.encodeWithSelector(
                    // initialize(bytes,uint256, uint256)
                    0x32b218ac,
                    aliceBytes,
                    defaultSpendingLimit,
                    collateralLimit
                )
            )
        );

        deal(address(weETH), alice, 1000 ether);
        deal(address(usdc), alice, 1 ether);
        deal(address(usdc), address(swapper), 1 ether);

        // Set weth as cash wrapped ERC20 since it has a cap on Aave
        wweETH = MockCashWrappedERC20(wrapperTokenFactory.deployWrapper(address(weETH)));
        vm.etch(address(weth), address(wweETH).code);
        wweETH = MockCashWrappedERC20(address(weth));
        wrapperTokenFactory.setWrappedTokenAddress(address(weETH), address(wweETH));
        wweETH.init(address(wrapperTokenFactory), address(weETH), "wweETH", "wweETH", 18);

        address[] memory minters = new address[](1);
        minters[0] = address(etherFiCashDebtManager);
        bool[] memory mintersWhitelist = new bool[](1);
        mintersWhitelist[0] = true;

        address[] memory recipients = new address[](2);
        
        if (isScroll(chainId)) recipients[0] = 0xf301805bE1Df81102C957f6d4Ce29d2B8c056B2a; // aWeth token
        else recipients[0] = address(MockAaveAdapter(address(aaveV3Adapter)).aave());
        recipients[1] = address(etherFiCashDebtManager);
        bool[] memory recipientsWhitelist = new bool[](2);
        recipientsWhitelist[0] = true;
        recipientsWhitelist[1] = true;

        wrapperTokenFactory.whitelistMinters(address(weETH), minters, mintersWhitelist);
        wrapperTokenFactory.whitelistRecipients(address(weETH), recipients, recipientsWhitelist);

        vm.stopPrank();
    }
}
