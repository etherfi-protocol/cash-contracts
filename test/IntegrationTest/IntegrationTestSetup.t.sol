// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src//user-safe/UserSafe.sol";
import {IL2DebtManager, L2DebtManager} from "../../src/L2DebtManager.sol";
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
import {L2DebtManager} from "../../src/L2DebtManager.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

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

    L2DebtManager etherFiCashDebtManager;

    uint256 ltv = 50e18; //50%
    uint256 liquidationThreshold = 60e18; // 60%
    uint256 borrowApy = 1000; // 10%
    ChainConfig chainConfig;

    function setUp() public virtual {
        chainId = vm.envString("TEST_CHAIN");

        vm.startPrank(owner);

        emit log_named_string("Testing on ChainID", chainId);

        if (!isFork(chainId)) {
            usdc = ERC20(address(new MockERC20("usdc", "usdc", 6)));
            weETH = ERC20(address(new MockERC20("weETH", "weETH", 18)));

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
            weEthWethOracle = chainConfig.weEthWethOracle;
            ethUsdcOracle = chainConfig.ethUsdcOracle;
            swapRouterOpenOcean = chainConfig.swapRouterOpenOcean;

            address[] memory assets = new address[](1);
            assets[0] = address(weETH);

            swapper = new SwapperOpenOcean(swapRouterOpenOcean, assets);
            priceProvider = new PriceProvider(
                address(weETH),
                weEthWethOracle,
                ethUsdcOracle
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

        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weETH);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        IL2DebtManager.CollateralTokenConfigData[]
            memory collateralTokenConfig = new IL2DebtManager.CollateralTokenConfigData[](
                1
            );
        collateralTokenConfig[0] = IL2DebtManager.CollateralTokenConfigData({
            ltv: ltv,
            liquidationThreshold: liquidationThreshold
        });
        uint256[] memory borrowApys = new uint256[](1);
        borrowApys[0] = borrowApy;

        address debtManagerImpl = address(
            new L2DebtManager(address(cashDataProvider))
        );

        etherFiCashDebtManager = L2DebtManager(
            address(new UUPSProxy(debtManagerImpl, ""))
        );

        CashDataProvider(address(cashDataProvider)).initialize(
            owner,
            delay,
            etherFiWallet,
            etherFiCashMultisig,
            address(etherFiCashDebtManager),
            address(usdc),
            address(weETH),
            address(priceProvider),
            address(swapper),
            address(aaveV3Adapter)
        );

        etherFiCashDebtManager.initialize(
            owner,
            uint48(delay),
            collateralTokens,
            collateralTokenConfig,
            borrowTokens,
            borrowApys
        );

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

        factory = new UserSafeFactory(address(impl), owner);

        (alice, alicePk) = makeAddrAndKey("alice");
        aliceBytes = abi.encode(alice);

        aliceSafe = UserSafe(
            factory.createUserSafe(
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

        vm.stopPrank();
    }
}
