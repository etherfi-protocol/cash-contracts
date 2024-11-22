// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeFactory} from "../src/user-safe/UserSafeFactory.sol";
import {IL2DebtManager} from "../src/interfaces/IL2DebtManager.sol";
import {DebtManagerCore} from "../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../src/debt-manager/DebtManagerAdmin.sol";
import {DebtManagerInitializer} from "../src/debt-manager/DebtManagerInitializer.sol";
import {SwapperOpenOcean} from "../src/utils/SwapperOpenOcean.sol";
import {PriceProvider} from "../src/oracle/PriceProvider.sol";
import {CashDataProvider} from "../src/utils/CashDataProvider.sol";
import {OwnerLib} from "../src/libraries/OwnerLib.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceProvider} from "../src/mocks/MockPriceProvider.sol";
import {MockSwapper} from "../src/mocks/MockSwapper.sol";
import {IWeETH} from "../src/interfaces/IWeETH.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {UserSafeCore, UserSafeStorage, UserSafeEventEmitter, SpendingLimit, UserSafeLib} from "../src/user-safe/UserSafeCore.sol";
import {UserSafeSetters} from "../src/user-safe/UserSafeSetters.sol";
import {IUserSafe} from "../src/interfaces/IUserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {CashbackDispatcher} from "../src/cashback-dispatcher/CashbackDispatcher.sol";

contract Setup is Utils {
    using OwnerLib for address;
    using MessageHashUtils for bytes32;

    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    string chainId;

    uint256 etherFiRecoverySignerPk;
    address etherFiRecoverySigner;
    uint256 thirdPartyRecoverySignerPk;
    address thirdPartyRecoverySigner;

    UserSafeCore userSafeCoreImpl;
    UserSafeSetters userSafeSettersImpl;
    UserSafeFactory factory;
    UserSafeEventEmitter eventEmitter;

    ERC20 usdc;
    ERC20 weETH;
    ERC20 scr;
    SwapperOpenOcean swapper;
    PriceProvider priceProvider;
    CashDataProvider cashDataProvider;
    CashbackDispatcher cashbackDispatcher;

    uint256 mockWeETHPriceInUsd = 3000e6;
    uint256 defaultDailySpendingLimit = 10000e6;
    uint256 defaultMonthlySpendingLimit = 100000e6;
    uint64 delay = 10;
    address settlementDispatcher = makeAddr("settlementDispatcher");
    IL2DebtManager debtManager;
    address etherFiWallet = makeAddr("etherFiWallet");

    address weEthWethOracle;
    address ethUsdcOracle;
    address usdcUsdOracle;
    address scrUsdOracle;
    address swapRouterOpenOcean;

    address alice;
    uint256 alicePk;
    bytes aliceBytes;
    IUserSafe aliceSafe;

    uint80 ltv = 50e18; // 50%
    uint80 liquidationThreshold = 60e18; // 60%
    uint96 liquidationBonus = 5e18; // 5%
    uint64 borrowApyPerSecond = 1e16; // 0.01% per second
    ChainConfig chainConfig;
    uint256 supplyCap = 10000 ether;
    int256 timezoneOffset = 4 * 60 * 60; // Dubai timezone
    uint128 minShares;
    bytes32 txId = keccak256("txId");

    function setUp() public virtual {
        chainId = vm.envString("TEST_CHAIN");

        vm.startPrank(owner);

        emit log_named_string("Testing on ChainID", chainId);

        if (!isFork(chainId)) {
            usdc = ERC20(address(new MockERC20("usdc", "usdc", 6)));
            weETH = ERC20(address(new MockERC20("weETH", "weETH", 18)));
            scr = ERC20(address(new MockERC20("scroll", "scr", 18)));

            swapper = SwapperOpenOcean(address(new MockSwapper()));
            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd, address(usdc)))
            );
        } else {
            chainConfig = getChainConfig(chainId);
            vm.createSelectFork(chainConfig.rpc);

            usdc = ERC20(chainConfig.usdc);
            weETH = ERC20(chainConfig.weETH);
            scr = ERC20(chainConfig.scr);
            weEthWethOracle = chainConfig.weEthWethOracle;
            ethUsdcOracle = chainConfig.ethUsdcOracle;
            scrUsdOracle = chainConfig.scrUsdOracle;
            usdcUsdOracle = chainConfig.usdcUsdOracle;
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
                isBaseTokenEth: true,
                isStableToken: false
            });
            
            PriceProvider.Config memory ethConfig = PriceProvider.Config({
                oracle: ethUsdcOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(ethUsdcOracle).decimals(),
                maxStaleness: 1 days,
                dataType: PriceProvider.ReturnType.Int256,
                isBaseTokenEth: false,
                isStableToken: false
            });
            
            PriceProvider.Config memory usdcConfig = PriceProvider.Config({
                oracle: usdcUsdOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(usdcUsdOracle).decimals(),
                maxStaleness: 10 days,
                dataType: PriceProvider.ReturnType.Int256,
                isBaseTokenEth: false,
                isStableToken: true
            });
            
            PriceProvider.Config memory scrollConfig = PriceProvider.Config({
                oracle: scrUsdOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(scrUsdOracle).decimals(),
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

            priceProvider = PriceProvider(address(new UUPSProxy(
                address(new PriceProvider()), 
                abi.encodeWithSelector(
                    PriceProvider.initialize.selector,
                    owner,
                    initialTokens,
                    initialTokensConfig
                )
            )));
        }

        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        address cashbackDispatcherImpl = address(new CashbackDispatcher());
        cashbackDispatcher = CashbackDispatcher(
            address(
                new UUPSProxy(
                    cashbackDispatcherImpl, 
                    abi.encodeWithSelector(
                        CashbackDispatcher.initialize.selector,
                        address(owner),
                        address(cashDataProvider),
                        address(priceProvider),
                        address(scr)
                    )
                )
            )
        );

        address[] memory collateralTokens = new address[](2);
        collateralTokens[0] = address(weETH);
        collateralTokens[1] = address(usdc);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        DebtManagerCore.CollateralTokenConfig[]
            memory collateralTokenConfig = new DebtManagerCore.CollateralTokenConfig[](
                2
            );

        collateralTokenConfig[0].ltv = ltv;
        collateralTokenConfig[0].liquidationThreshold = liquidationThreshold;
        collateralTokenConfig[0].liquidationBonus = liquidationBonus;
        
        collateralTokenConfig[1].ltv = ltv;
        collateralTokenConfig[1].liquidationThreshold = liquidationThreshold;
        collateralTokenConfig[1].liquidationBonus = liquidationBonus;

        address debtManagerCoreImpl = address(new DebtManagerCore());
        address debtManagerAdminImpl = address(new DebtManagerAdmin());
        address debtManagerInitializer = address(new DebtManagerInitializer());
        address debtManagerProxy = address(new UUPSProxy(debtManagerInitializer, ""));

        debtManager = IL2DebtManager(address(debtManagerProxy));

        (etherFiRecoverySigner, etherFiRecoverySignerPk) = makeAddrAndKey("etherFiRecoverySigner");
        (thirdPartyRecoverySigner, thirdPartyRecoverySignerPk) = makeAddrAndKey("thirdPartyRecoverySigner");

        userSafeCoreImpl = new UserSafeCore(address(cashDataProvider));
        userSafeSettersImpl = new UserSafeSetters(address(cashDataProvider));
        address factoryImpl = address(new UserSafeFactory());
        
        factory = UserSafeFactory(
            address(new UUPSProxy(
                factoryImpl, 
                abi.encodeWithSelector(
                    UserSafeFactory.initialize.selector, 
                    uint48(delay),
                    owner, 
                    address(cashDataProvider),
                    address(userSafeCoreImpl),
                    address(userSafeSettersImpl)
                ))
            )
        );

        address eventEmitterImpl = address(new UserSafeEventEmitter());
        eventEmitter = UserSafeEventEmitter(address(
            new UUPSProxy(
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
            delay,
            etherFiWallet,
            settlementDispatcher,
            address(debtManager),
            address(priceProvider),
            address(swapper),
            address(factory),
            address(eventEmitter),
            address(cashbackDispatcher),
            etherFiRecoverySigner,
            thirdPartyRecoverySigner
        ));

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
        
        minShares = uint128(10 * 10 ** usdc.decimals());
        DebtManagerAdmin(address(debtManagerCore)).supportBorrowToken(
            address(usdc), 
            borrowApyPerSecond, 
            minShares
        );


        (alice, alicePk) = makeAddrAndKey("alice");
        aliceBytes = abi.encode(alice);

        bytes memory saltData = bytes("aliceSafe");

        aliceSafe = IUserSafe(
            factory.createUserSafe(
                saltData,
                abi.encodeWithSelector(
                    UserSafeCore.initialize.selector,
                    aliceBytes,
                    defaultDailySpendingLimit,
                    defaultMonthlySpendingLimit,
                    timezoneOffset
                )
            )
        );

        deal(address(weETH), alice, 1000 ether);
        deal(address(usdc), alice, 1 ether);
        deal(address(usdc), address(swapper), 1 ether);

        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_MODE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                IUserSafe.Mode.Debit
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.setMode(IUserSafe.Mode.Debit, signature);

        vm.stopPrank();
    }
}
