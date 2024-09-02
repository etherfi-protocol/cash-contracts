// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPool} from "@aave/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave/interfaces/IPoolDataProvider.sol";
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

    IERC20 weETH;
    IERC20 usdc;
    string chainId;
    address weEthWethOracle;
    address ethUsdcOracle;
    address etherFiCashSafe = makeAddr("etherFiCashSafe");
    PriceProvider priceProvider;
    L2DebtManager debtManager;
    uint256 mockWeETHPriceInUsd = 3000e6;
    uint256 ltv = 50e18; // 50%
    uint256 liquidationThreshold = 60e18; // 60%
    uint256 borrowApyPerSecond = 1e18; // 1%

    uint64 delay = 10;
    address etherFiWallet = makeAddr("etherFiWallet");
    address swapper = makeAddr("swapper");

    function setUp() public virtual {
        chainId = vm.envString("TEST_CHAIN");

        vm.startPrank(owner);

        if (!isFork(chainId)) {
            emit log_named_string("Testing on ChainID", chainId);

            usdc = IERC20(address(new MockERC20("USDC", "USDC", 6)));
            weETH = IERC20(address(new MockERC20("weETH", "weETH", 18)));
            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd))
            );

            aaveV3Adapter = IEtherFiCashAaveV3Adapter(new MockAaveAdapter());
        } else {
            emit log_named_string("Testing on ChainID", chainId);

            ChainConfig memory chainConfig = getChainConfig(chainId);
            vm.createSelectFork(chainConfig.rpc);

            usdc = IERC20(chainConfig.usdc);
            weETH = IERC20(chainConfig.weETH);

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

        IL2DebtManager.CollateralTokenConfigData[]
            memory collateralTokenConfig = new IL2DebtManager.CollateralTokenConfigData[](
                1
            );
        collateralTokenConfig[0] = IL2DebtManager.CollateralTokenConfigData({
            ltv: ltv,
            liquidationThreshold: liquidationThreshold
        });
        uint256[] memory borrowApys = new uint256[](1);
        borrowApys[0] = borrowApyPerSecond;

        address debtManagerImpl = address(
            new L2DebtManager(address(cashDataProvider))
        );

        address debtManagerProxy = address(
            new UUPSProxy(
                debtManagerImpl,
                abi.encodeWithSelector(
                    // initialize(address,address[],(uint256,uint256)[],address[],uint256[])
                    0xa9e49bef,
                    owner,
                    collateralTokens,
                    collateralTokenConfig,
                    borrowTokens,
                    borrowApys
                )
            )
        );
        debtManager = L2DebtManager(debtManagerProxy);

        (bool success, ) = address(cashDataProvider).call(
            abi.encodeWithSelector(
                // intiailize(address,uint64,address,address,address,address,address,address,address,address)
                0xf86fac96,
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
            )
        );

        if (!success) revert("Initialize failed on Cash Data Provider");

        vm.stopPrank();
    }
}
