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
import {IL2DebtManager, L2DebtManager} from "../../src/L2DebtManager.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";

contract DebtManagerSetup is Utils {
    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    address alice = makeAddr("alice");

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
    L2DebtManager debtManager;
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

            priceProvider = new PriceProvider(
                address(weETH),
                weEthWethOracle,
                ethUsdcOracle
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

        IL2DebtManager.CollateralTokenConfig[]
            memory collateralTokenConfig = new IL2DebtManager.CollateralTokenConfig[](
                1
            );
        collateralTokenConfig[0] = IL2DebtManager.CollateralTokenConfig({
            ltv: ltv,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            supplyCap: supplyCap
        });

        IL2DebtManager.BorrowTokenConfigData[]
            memory borrowTokenConfig = new IL2DebtManager.BorrowTokenConfigData[](
                1
            );
        borrowTokenConfig[0] = IL2DebtManager.BorrowTokenConfigData({
           borrowApy: borrowApyPerSecond,
           minSharesToMint: uint128(1 * 10 ** usdc.decimals())
        });

        address debtManagerImpl = address(
            new L2DebtManager(address(cashDataProvider))
        );

        debtManager = L2DebtManager(
            address(new UUPSProxy(debtManagerImpl, ""))
        );

        CashDataProvider(address(cashDataProvider)).initialize(
            owner,
            delay,
            etherFiWallet,
            etherFiCashSafe,
            address(debtManager),
            address(usdc),
            address(weETH),
            address(priceProvider),
            address(swapper),
            address(aaveV3Adapter)
        );

        debtManager.initialize(
            owner,
            uint48(delay),
            collateralTokens,
            collateralTokenConfig,
            borrowTokens,
            borrowTokenConfig
        );

        vm.stopPrank();
    }
}
