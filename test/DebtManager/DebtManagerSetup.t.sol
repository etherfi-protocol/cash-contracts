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
import {L2DebtManager} from "../../src/L2DebtManager.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

contract DebtManagerSetup is Utils {
    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    address alice = makeAddr("alice");

    IEtherFiCashAaveV3Adapter aaveV3Adapter;

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
    uint256 liquidationThreshold = 60e18; // 60%
    uint256 borrowApyPerSecond = 1e18; // 1%

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

            priceProvider = new PriceProvider(weEthWethOracle, ethUsdcOracle);

            aaveV3Adapter = IEtherFiCashAaveV3Adapter(
                new EtherFiCashAaveV3Adapter(
                    address(aavePool),
                    address(aaveV3PoolDataProvider),
                    aaveReferralCode,
                    interestRateMode
                )
            );
        }

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = address(weETH);
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        address impl = address(
            new L2DebtManager(
                address(weETH),
                address(usdc),
                etherFiCashSafe,
                address(priceProvider),
                address(aaveV3Adapter)
            )
        );

        address proxy = address(
            new UUPSProxy(
                impl,
                abi.encodeWithSelector(
                    // initialize(address,uint256,uint256,address[],address[])
                    0x1df44494,
                    owner,
                    liquidationThreshold,
                    borrowApyPerSecond,
                    collateralTokens,
                    borrowTokens
                )
            )
        );
        debtManager = L2DebtManager(proxy);

        vm.stopPrank();
    }
}
