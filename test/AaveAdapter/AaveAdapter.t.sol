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

contract AaveAdapterTest is Utils {
    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    IEtherFiCashAaveV3Adapter aaveV3Adapter;

    IPool aavePool;
    IPoolDataProvider aaveV3PoolDataProvider;
    // Interest rate mode -> Stable: 1, variable: 2
    uint256 interestRateMode = 2;
    uint16 aaveReferralCode = 0;

    IERC20 weETH;
    IERC20 usdc;
    string chainId;

    function setUp() public {
        chainId = vm.envString("TEST_CHAIN");

        vm.startPrank(owner);

        if (!isFork(chainId)) {
            emit log_named_string("Testing on ChainID", chainId);

            usdc = IERC20(address(new MockERC20("USDC", "USDC", 6)));
            weETH = IERC20(address(new MockERC20("weETH", "weETH", 18)));
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

            aaveV3Adapter = IEtherFiCashAaveV3Adapter(
                new EtherFiCashAaveV3Adapter(
                    address(aavePool),
                    address(aaveV3PoolDataProvider),
                    aaveReferralCode,
                    interestRateMode
                )
            );

            deal(address(usdc), owner, 1 ether);
            deal(address(weETH), owner, 1000 ether);
        }

        vm.stopPrank();
    }

    function test_Flow() public {
        test_FullFlow();
    }

    function test_Process() public {
        test_Borrow();
    }

    function test_Supply() internal returns (uint256) {
        vm.startPrank(owner);

        uint256 amount = 0.001 ether;
        weETH.safeTransfer(address(aaveV3Adapter), amount);
        aaveV3Adapter.supply(address(weETH), amount);

        uint256 collateralBalance = aaveV3Adapter.getCollateralBalance(
            address(aaveV3Adapter),
            address(weETH)
        );
        assertEq(collateralBalance, amount);

        vm.stopPrank();

        return amount;
    }

    function test_Borrow() internal returns (uint256, uint256) {
        uint256 supplyAmt = test_Supply();
        vm.startPrank(owner);

        vm.roll(block.number + 10);
        uint256 usdcBalBefore = usdc.balanceOf(address(aaveV3Adapter));

        uint256 borrowAmt = 0.1e6;

        if (!isFork(chainId)) {
            usdc.safeTransfer(address(aaveV3Adapter), borrowAmt);
        }

        aaveV3Adapter.borrow(address(usdc), borrowAmt);

        uint256 usdcBalAfter = usdc.balanceOf(address(aaveV3Adapter));

        uint256 debt = aaveV3Adapter.getDebt(
            address(aaveV3Adapter),
            address(usdc)
        );
        assertEq(debt, borrowAmt);
        assertEq(usdcBalAfter - usdcBalBefore, borrowAmt);

        vm.stopPrank();

        return (supplyAmt, borrowAmt);
    }

    function test_Repay() internal returns (uint256, uint256, uint256) {
        (uint256 supplyAmt, uint256 borrowAmt) = test_Borrow();
        vm.startPrank(owner);

        vm.roll(block.number + 10);
        uint256 repayAmt = aaveV3Adapter.getDebt(
            address(aaveV3Adapter),
            address(usdc)
        );

        usdc.safeTransfer(address(aaveV3Adapter), borrowAmt);
        aaveV3Adapter.repay(address(usdc), repayAmt);

        uint256 finalDebt = aaveV3Adapter.getDebt(
            address(aaveV3Adapter),
            address(usdc)
        );

        assertEq(finalDebt, 0);

        vm.stopPrank();

        return (supplyAmt, borrowAmt, repayAmt);
    }

    function test_FullFlow() internal {
        test_Repay();
        vm.startPrank(owner);

        vm.roll(block.number + 10);
        uint256 balBefore = weETH.balanceOf(address(aaveV3Adapter));

        uint256 withdrawAmt = aaveV3Adapter.getCollateralBalance(
            address(aaveV3Adapter),
            address(weETH)
        );

        if (!isFork(chainId)) {
            weETH.safeTransfer(address(aaveV3Adapter), withdrawAmt);
        }

        aaveV3Adapter.withdraw(address(weETH), withdrawAmt);

        uint256 balAfter = weETH.balanceOf(address(aaveV3Adapter));
        assertEq(balAfter - balBefore, withdrawAmt);
        vm.stopPrank();
    }
}
