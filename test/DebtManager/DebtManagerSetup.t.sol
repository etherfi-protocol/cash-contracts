// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPool} from "@aave/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave/interfaces/IPoolDataProvider.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Utils, ChainConfig} from "../Utils.sol";
import {IEtherFiCashAaveV3Adapter, EtherFiCashAaveV3Adapter} from "../../src/adapters/aave-v3/EtherFiCashAaveV3Adapter.sol";
import {MockAaveAdapter} from "../../src/mocks/MockAaveAdapter.sol";
import {MockPriceProvider} from "../../src/mocks/MockPriceProvider.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {DebtManagerCore} from "../../src/debt-manager/DebtManagerCore.sol";
import {DebtManagerAdmin} from "../../src/debt-manager/DebtManagerAdmin.sol";
import {DebtManagerInitializer} from "../../src/debt-manager/DebtManagerInitializer.sol";import {IWeETH} from "../../src/interfaces/IWeETH.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";

contract DebtManagerSetup is Utils {
    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    address alice = makeAddr("alice");

    address userSafeFactory;
    IEtherFiCashAaveV3Adapter aaveV3Adapter;
    CashDataProvider cashDataProvider;

    IPool aavePool;
    IPoolDataProvider aaveV3PoolDataProvider;
    // Interest rate mode -> Stable: 1, variable: 2
    uint256 interestRateMode = 2;
    uint16 aaveReferralCode = 0;

    ERC20 weETH;
    ERC20 usdc;
    string chainId;
    address weEthWethOracle;
    address ethUsdcOracle;
    address etherFiCashSafe = makeAddr("etherFiCashSafe");
    PriceProvider priceProvider;
    IL2DebtManager debtManager;
    uint256 mockWeETHPriceInUsd = 3000e6;
    uint80 ltv = 50e18; // 50%
    uint80 liquidationThreshold = 60e18; // 60%
    uint96 liquidationBonus = 5e18; // 5%
    uint64 borrowApyPerSecond = 1e16; // 0.01%

    uint64 delay = 10;
    address etherFiWallet = makeAddr("etherFiWallet");
    address swapper = makeAddr("swapper");
    ChainConfig chainConfig;
    uint256 supplyCap = 10000 ether;

    DebtManagerCore debtManagerCore;
    DebtManagerAdmin debtManagerAdmin;

    uint128 minShares;

    function setUp() public virtual {
        chainId = vm.envString("TEST_CHAIN");

        vm.startPrank(owner);

        if (!isFork(chainId)) {
            emit log_named_string("Testing on ChainID", chainId);

            usdc = ERC20(address(new MockERC20("USDC", "USDC", 6)));
            weETH = ERC20(address(new MockERC20("weETH", "weETH", 18)));
            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd))
            );

            aaveV3Adapter = IEtherFiCashAaveV3Adapter(new MockAaveAdapter());
        } else {
            emit log_named_string("Testing on ChainID", chainId);

            chainConfig = getChainConfig(chainId);
            vm.createSelectFork(chainConfig.rpc);

            usdc = ERC20(chainConfig.usdc);
            weETH = ERC20(chainConfig.weETH);

            aavePool = IPool(chainConfig.aaveV3Pool);
            aaveV3PoolDataProvider = IPoolDataProvider(
                chainConfig.aaveV3PoolDataProvider
            );
            weEthWethOracle = chainConfig.weEthWethOracle;
            ethUsdcOracle = chainConfig.ethUsdcOracle;

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

        DebtManagerCore.CollateralTokenConfig[]
            memory collateralTokenConfig = new DebtManagerCore.CollateralTokenConfig[](
                1
            );
        collateralTokenConfig[0].ltv = ltv;
        collateralTokenConfig[0].liquidationThreshold = liquidationThreshold;
        collateralTokenConfig[0].liquidationBonus = liquidationBonus;
        collateralTokenConfig[0].supplyCap = supplyCap;

        IL2DebtManager.BorrowTokenConfigData[]
            memory borrowTokenConfig = new IL2DebtManager.BorrowTokenConfigData[](
                1
            );

        minShares = uint128(1 * 10 ** usdc.decimals());
        borrowTokenConfig[0] = IL2DebtManager.BorrowTokenConfigData({
           borrowApy: borrowApyPerSecond,
           minShares: minShares
        });

        address debtManagerCoreImpl = address(new DebtManagerCore());
        address debtManagerAdminImpl = address(new DebtManagerAdmin());
        address debtManagerInitializer = address(new DebtManagerInitializer());
        address debtManagerProxy = address(new UUPSProxy(debtManagerInitializer, ""));

        debtManager = IL2DebtManager(address(debtManagerProxy));


        userSafeFactory = address(1);

        CashDataProvider(address(cashDataProvider)).initialize(
            owner,
            delay,
            etherFiWallet,
            etherFiCashSafe,
            address(debtManager),
            address(priceProvider),
            address(swapper),
            address(aaveV3Adapter),
            userSafeFactory
        );
    
        DebtManagerInitializer(address(debtManager)).initialize(
            owner,
            uint48(delay),
            address(cashDataProvider)
        );

        DebtManagerCore(debtManagerProxy).upgradeToAndCall(debtManagerCoreImpl, "");
        debtManagerCore = DebtManagerCore(debtManagerProxy);
        debtManagerCore.setAdminImpl(debtManagerAdminImpl);
        DebtManagerAdmin(address(debtManagerCore)).supportCollateralToken(address(weETH), collateralTokenConfig[0]);
        DebtManagerAdmin(address(debtManagerCore)).supportBorrowToken(
            address(usdc), 
            borrowApyPerSecond, 
            uint128(1 * 10 ** usdc.decimals())
        );

        vm.stopPrank();
        
        vm.prank(userSafeFactory);
        cashDataProvider.whitelistUserSafe(alice);
    }
}
