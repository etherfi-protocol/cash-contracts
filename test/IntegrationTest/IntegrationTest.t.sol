// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib} from "../../src/user-safe/UserSafeCore.sol";
import {IntegrationTestSetup, PriceProvider, MockPriceProvider, MockERC20} from "./IntegrationTestSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IntegrationTest is IntegrationTestSetup {
    using SafeERC20 for IERC20;

    uint256 collateralAmount = 0.01 ether;
    uint256 supplyAmount = 10e6;
    uint256 borrowAmount = 1e6;

    function setUp() public override {
        super.setUp();

        if (!isFork(chainId)) {
            /// If not mainnet, give some usdc to debt manager so it can provide debt
            vm.startPrank(owner);

            usdc.approve(address(etherFiCashDebtManager), supplyAmount);
            etherFiCashDebtManager.supply(
                address(owner),
                address(usdc),
                supplyAmount
            );
            vm.stopPrank();
        } else {
            vm.startPrank(owner);

            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd))
            );
            cashDataProvider.setPriceProvider(address(priceProvider));

            // address newCollateralToken = address(weth);
            // uint80 newLtv = 80e18;
            // uint80 newLiquidationThreshold = 85e18;
            // uint96 newLiquidationBonus = 8.5e18;

            // IL2DebtManager.CollateralTokenConfig memory config = IL2DebtManager.CollateralTokenConfig({
            //     ltv: newLtv,
            //     liquidationThreshold: newLiquidationThreshold,
            //     liquidationBonus: newLiquidationBonus,
            //     supplyCap: supplyCap
            // });

            // etherFiCashDebtManager.supportCollateralToken(
            //     newCollateralToken,
            //     config
            // );

            // /// If it is mainnet, supply 0.01 weETH and borrow 1 USDC from Aave
            // deal(
            //     address(weETH),
            //     address(etherFiCashDebtManager),
            //     collateralAmount
            // );
            // deal(
            //     address(weth),
            //     address(etherFiCashDebtManager),
            //     collateralAmount
            // );
            // etherFiCashDebtManager.fundManagementOperation(
            //     uint8(IL2DebtManager.MarketOperationType.SupplyAndBorrow),
            //     abi.encode(
            //         address(weth),
            //         collateralAmount,
            //         address(usdc),
            //         borrowAmount
            //     )
            // );
            vm.stopPrank();
        }
    }

    function test_AddCollateral() public {
        uint256 amount = 0.01 ether;
        deal(address(weETH), address(aliceSafe), amount);

        uint256 aliceSafeCollateralBefore = etherFiCashDebtManager.getCollateralValueInUsd(address(aliceSafe));
        assertEq(aliceSafeCollateralBefore, 0);

        uint256 aliceSafeBalBefore = weETH.balanceOf(address(aliceSafe));

        vm.prank(etherFiWallet);
        aliceSafe.addCollateral(address(weETH), amount);

        uint256 aliceSafeCollateralAfter = etherFiCashDebtManager.getCollateralValueInUsd(address(aliceSafe));
        assertEq(
            aliceSafeCollateralAfter,
            etherFiCashDebtManager.convertCollateralTokenToUsd(
                address(weETH),
                amount
            )
        );

        uint256 aliceSafeBalAfter = weETH.balanceOf(address(aliceSafe));

        assertEq(aliceSafeBalBefore - aliceSafeBalAfter, amount);
    }

    function test_AddCollateralAndBorrow() public {
        uint256 supplyAmt = 0.01 ether;
        uint256 borrowAmt = 1e6;

        deal(address(weETH), address(aliceSafe), supplyAmt);

        uint256 aliceSafeCollateralBefore = etherFiCashDebtManager.getCollateralValueInUsd(address(aliceSafe));
        assertEq(aliceSafeCollateralBefore, 0);

        uint256 aliceSafeDebtBefore = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtBefore, 0);

        uint256 aliceSafeWeEthBalBefore = weETH.balanceOf(address(aliceSafe));
        uint256 cashSafeUsdcBalBefore = usdc.balanceOf(
            address(settlementDispatcher)
        );

        vm.prank(etherFiWallet);
        aliceSafe.addCollateralAndBorrow(
            address(weETH),
            supplyAmt,
            address(usdc),
            borrowAmt
        );

        uint256 aliceSafeCollateralAfter = etherFiCashDebtManager.getCollateralValueInUsd(address(aliceSafe));
        assertEq(
            aliceSafeCollateralAfter,
            etherFiCashDebtManager.convertCollateralTokenToUsd(
                address(weETH),
                supplyAmt
            )
        );

        uint256 aliceSafeDebtAfter = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtAfter, borrowAmt);

        uint256 aliceSafeWeEthBalAfter = weETH.balanceOf(address(aliceSafe));
        uint256 cashSafeUsdcBalAfter = usdc.balanceOf(
            address(settlementDispatcher)
        );

        assertEq(aliceSafeWeEthBalBefore - aliceSafeWeEthBalAfter, supplyAmt);
        assertEq(cashSafeUsdcBalAfter - cashSafeUsdcBalBefore, borrowAmt);
    }

    function test_RepayUsingUsdc() public {
        uint256 supplyAmt = 0.01 ether;
        uint256 borrowAmt = 1e6;
        uint256 repayAmt = 1e6;

        deal(address(weETH), address(aliceSafe), supplyAmt);
        deal(address(usdc), address(aliceSafe), repayAmt);

        vm.startPrank(etherFiWallet);
        aliceSafe.addCollateralAndBorrow(
            address(weETH),
            supplyAmt,
            address(usdc),
            borrowAmt
        );

        uint256 aliceSafeUsdcBalBefore = usdc.balanceOf(address(aliceSafe));

        uint256 aliceSafeDebtBefore = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtBefore, borrowAmt);

        aliceSafe.repay(address(usdc), repayAmt);

        uint256 aliceSafeUsdcBalAfter = usdc.balanceOf(address(aliceSafe));

        uint256 aliceSafeDebtAfter = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtAfter, 0);
        assertEq(aliceSafeUsdcBalBefore - aliceSafeUsdcBalAfter, repayAmt);

        vm.stopPrank();
    }

    function test_WithdrawCollateral() public {
        uint256 supplyAmt = 0.01 ether;
        uint256 borrowAmt = 1e6;

        deal(address(weETH), address(aliceSafe), supplyAmt);

        vm.startPrank(etherFiWallet);
        aliceSafe.addCollateralAndBorrow(
            address(weETH),
            supplyAmt,
            address(usdc),
            borrowAmt
        );

        uint256 aliceSafeWeEthBalBefore = weETH.balanceOf(address(aliceSafe));

        uint256 withdrawAmt = 0.001 ether;
        aliceSafe.withdrawCollateralFromDebtManager(
            address(weETH),
            withdrawAmt
        );

        uint256 aliceSafeWeEthBalAfter = weETH.balanceOf(address(aliceSafe));

        assertEq(aliceSafeWeEthBalAfter - aliceSafeWeEthBalBefore, withdrawAmt);
    }

    function test_CloseAccount() public {
        uint256 supplyAmt = 0.01 ether;
        uint256 borrowAmt = 1e6;

        deal(address(weETH), address(aliceSafe), supplyAmt);

        vm.prank(etherFiWallet);
        aliceSafe.addCollateralAndBorrow(
            address(weETH),
            supplyAmt,
            address(usdc),
            borrowAmt
        );

        vm.startPrank(alice);
        deal(address(usdc), alice, borrowAmt);
        usdc.approve(address(etherFiCashDebtManager), borrowAmt);
        etherFiCashDebtManager.repay(
            address(aliceSafe),
            address(usdc),
            borrowAmt
        );
        vm.stopPrank();

        uint256 aliceSafeWeEthBalBefore = weETH.balanceOf(address(aliceSafe));

        vm.prank(etherFiWallet);
        aliceSafe.closeAccountWithDebtManager();

        uint256 aliceSafeWeEthBalAfter = weETH.balanceOf(address(aliceSafe));

        assertEq(aliceSafeWeEthBalAfter - aliceSafeWeEthBalBefore, supplyAmt);
    }

    function test_MultipleBorrowTokens() public {
        if (!isScroll(chainId)) return;
        
        // Here we are considering wstETH as a stable token to just test out with 18 decimals
        // So debt manager considers the value of  1 wstETH as 1 USDC
        IERC20 wstETH = IERC20(0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32);
        uint64 newBorrowApy = 1e18;
        uint128 newMinShares = 1e16;

        vm.prank(owner);
        etherFiCashDebtManager.supportBorrowToken(address(wstETH), newBorrowApy, newMinShares);

        address supplier = makeAddr("supplier");
        uint256 wstETHSupplyAmt = 100 ether;
        uint256 usdcSupplyAmt = 100e6;
        // since 100 ether of wstETH is considered as 100 USD value 
        uint256 totalSupplyInUsdc = (100 + 100) * 10**6;

        deal(address(wstETH), supplier, 100 ether);
        deal(address(usdc), supplier, 100 ether);

        vm.startPrank(supplier);
        wstETH.forceApprove(address(etherFiCashDebtManager), wstETHSupplyAmt);
        usdc.approve(address(etherFiCashDebtManager), wstETHSupplyAmt);
        etherFiCashDebtManager.supply(supplier, address(wstETH), wstETHSupplyAmt);
        etherFiCashDebtManager.supply(supplier, address(usdc), usdcSupplyAmt);
        vm.stopPrank();

        assertEq(wstETH.balanceOf(address(etherFiCashDebtManager)), wstETHSupplyAmt);
        assertEq(usdc.balanceOf(address(etherFiCashDebtManager)), usdcSupplyAmt);

        (, uint256 totalSuppliesFromContract) = etherFiCashDebtManager.totalSupplies();
        assertEq(totalSuppliesFromContract, totalSupplyInUsdc);
        
        (
            uint256 wstETHBorrowAmt, 
            uint256 usdcBorrowAmt
        ) = _addCollateralAndBorrow(wstETH, wstETHSupplyAmt, usdcSupplyAmt);       
        _repay(wstETH, wstETHSupplyAmt, usdcBorrowAmt, wstETHBorrowAmt);

        IL2DebtManager.CollateralTokenConfig[]
            memory collateralTokenConfig = new IL2DebtManager.CollateralTokenConfig[](
                1
            );

        collateralTokenConfig[0].ltv = 10e18;
        collateralTokenConfig[0].liquidationThreshold = 10e18;
        collateralTokenConfig[0].liquidationBonus = 5e18;
        collateralTokenConfig[0].supplyCap = supplyCap;
        vm.prank(owner);
        etherFiCashDebtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfig[0]);

        assertEq(etherFiCashDebtManager.liquidatable(address(aliceSafe)), true);

        _liquidate(wstETH, usdcBorrowAmt);
    }

    function _addCollateralAndBorrow(
        IERC20 wstETH,
        uint256 wstETHSupplyAmt, 
        uint256 usdcSupplyAmt
    ) internal returns (uint256, uint256) {
        uint256 aliceCollateralAmt = 1 ether;
        deal(address(weETH), address(aliceSafe), 100 ether);
        vm.prank(address(etherFiWallet));
        aliceSafe.addCollateral(address(weETH), aliceCollateralAmt);

        // reason for using 1e38 -> 18 to remove decimals from collateral amt and 20 for removing the ltv precision
        uint256 expectedBorrowableAmount = aliceCollateralAmt * priceProvider.price(address(weETH)) * ltv / 10**38;
        uint256 aliceBorrowableAmount = etherFiCashDebtManager.remainingBorrowingCapacityInUSD(address(aliceSafe));
        assertEq(expectedBorrowableAmount, aliceBorrowableAmount);

        // since we have only 100 supplied, we have to borrow 0.01 wstETH from Aave
        uint256 wstETHBorrowAmt = 100.01 ether;
        vm.prank(etherFiWallet);
        aliceSafe.borrow(address(wstETH), wstETHBorrowAmt);

        assertEq(etherFiCashDebtManager.borrowingOf(address(aliceSafe), address(wstETH)), wstETHBorrowAmt * 1e6 / 1e18);
        assertEq(aaveV3Adapter.getDebt(address(etherFiCashDebtManager), address(wstETH)), wstETHBorrowAmt - wstETHSupplyAmt);
        
        // since we have only 1000 supplied, we have to borrow 300 USDC from Aave
        uint256 usdcBorrowAmt = 1300e6;
        vm.prank(etherFiWallet);
        aliceSafe.borrow(address(usdc), usdcBorrowAmt);

        assertEq(etherFiCashDebtManager.borrowingOf(address(aliceSafe), address(usdc)), usdcBorrowAmt);
        assertEq(aaveV3Adapter.getDebt(address(etherFiCashDebtManager), address(usdc)), usdcBorrowAmt - usdcSupplyAmt);

        return (wstETHBorrowAmt, usdcBorrowAmt);
    }

    function _repay(
        IERC20 wstETH,
        uint256 wstETHSupplyAmt,
        uint256 usdcBorrowAmt,
        uint256 wstETHBorrowAmt
    ) internal {
        (, uint256 totalBorrowingInUsd) = etherFiCashDebtManager.borrowingOf(address(aliceSafe));
        uint256 expectedTotalBorrow = usdcBorrowAmt + wstETHBorrowAmt * 1e6 / 1e18;
        assertEq(expectedTotalBorrow, totalBorrowingInUsd);

        uint256 wstETHRepayAmt = 0.001 ether;
        deal(address(wstETH), address(aliceSafe), wstETHRepayAmt);
        vm.prank(etherFiWallet);
        aliceSafe.repay(address(wstETH), wstETHRepayAmt);

        assertEq(wstETH.balanceOf(address(aliceSafe)), 0);

        ( , totalBorrowingInUsd) = etherFiCashDebtManager.borrowingOf(address(aliceSafe));
        expectedTotalBorrow = usdcBorrowAmt + (wstETHBorrowAmt - wstETHRepayAmt) * 1e6 / 1e18;
        assertEq(expectedTotalBorrow, totalBorrowingInUsd);

        assertApproxEqAbs(
            aaveV3Adapter.getDebt(address(etherFiCashDebtManager), address(wstETH)), 
            wstETHBorrowAmt - wstETHSupplyAmt - wstETHRepayAmt, 
            1
        );
    }

    function _liquidate(IERC20 wstETH, uint256 usdcBorrowAmt) internal {
        uint256 borrowingAmt = etherFiCashDebtManager.borrowingOf(address(aliceSafe), address(wstETH)) * 1e18 / 1e6;
        address liquidator = makeAddr("liquidator");
        deal(address(wstETH), liquidator, borrowingAmt);
        vm.startPrank(liquidator);
        wstETH.forceApprove(address(etherFiCashDebtManager), borrowingAmt);
        etherFiCashDebtManager.liquidate(address(aliceSafe), address(wstETH), etherFiCashDebtManager.getCollateralTokens());

        assertEq(wstETH.balanceOf(liquidator), 0);
        assertEq(aaveV3Adapter.getDebt(address(etherFiCashDebtManager), address(wstETH)), 0);

        (, uint256 totalBorrowingInUsd) = etherFiCashDebtManager.borrowingOf(address(aliceSafe));
        uint256 expectedTotalBorrow = usdcBorrowAmt;
        assertEq(expectedTotalBorrow, totalBorrowingInUsd);
    }

    // function test_MultipleSuppliers() public {
    //     vm.startPrank(owner);
    //     MockERC20 newCollateralToken = new MockERC20("CollToken", "CTK", 18);
    //     MockERC20 newBorrowToken = new MockERC20("DebtToken", "DTK", 18);

    //     uint80 newCollateralLtv = 80e18;
    //     uint80 newCollateralLiquidationThreshold = 85e18;
    //  uint96 newCollateralLiquidationBonus = 5e18;
    //     uint64 newBorrowTokenApy = 1e18;

    //     IL2DebtManager.CollateralTokenConfig memory config;
    //     config.ltv = newCollateralLtv;
    //     config.liquidationThreshold = newCollateralLiquidationThreshold;
    //     config.liquidationBonus = newCollateralLiquidationBonus;
    //     config.supplyCap = 1000000 ether;

    //     etherFiCashDebtManager.supportCollateralToken(
    //         address(newCollateralToken),
    //         config
    //     );
    //     etherFiCashDebtManager.supportBorrowToken(
    //         address(newBorrowToken),
    //         newBorrowTokenApy,
    //         1
    //     );
    //     vm.stopPrank();

    //     deal(address(newCollateralToken), address(aliceSafe), 1000 ether);
    //     deal(address(newBorrowToken), address(aliceSafe), 1000 ether);
    //     deal(address(newBorrowToken), address(alice), 1000 ether);
    //     deal(address(newBorrowToken), address(owner), 1000 ether);

    //     uint256 newBorrowTokenSupplyAmt = 1 ether;
    //     vm.startPrank(alice);
    //     newBorrowToken.approve(
    //         address(etherFiCashDebtManager),
    //         newBorrowTokenSupplyAmt
    //     );
    //     etherFiCashDebtManager.supply(
    //         alice,
    //         address(newBorrowToken),
    //         newBorrowTokenSupplyAmt
    //     );

    //     assertEq(
    //         etherFiCashDebtManager.supplierBalance(
    //             alice,
    //             address(newBorrowToken)
    //         ),
    //         newBorrowTokenSupplyAmt
    //     );

    //     IL2DebtManager.BorrowTokenConfig
    //         memory borrowTokenConfig = etherFiCashDebtManager.borrowTokenConfig(
    //             address(newBorrowToken)
    //         );

    //     assertEq(
    //         borrowTokenConfig.totalSharesOfBorrowTokens,
    //         newBorrowTokenSupplyAmt
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(owner);
    //     newBorrowToken.approve(
    //         address(etherFiCashDebtManager),
    //         newBorrowTokenSupplyAmt
    //     );
    //     etherFiCashDebtManager.supply(
    //         owner,
    //         address(newBorrowToken),
    //         newBorrowTokenSupplyAmt
    //     );

    //     assertEq(
    //         etherFiCashDebtManager.supplierBalance(
    //             owner,
    //             address(newBorrowToken)
    //         ),
    //         newBorrowTokenSupplyAmt
    //     );

    //     borrowTokenConfig = etherFiCashDebtManager.borrowTokenConfig(
    //         address(newBorrowToken)
    //     );

    //     assertEq(
    //         borrowTokenConfig.totalSharesOfBorrowTokens,
    //         2 * newBorrowTokenSupplyAmt
    //     );
    //     vm.stopPrank();

    //     vm.prank(etherFiWallet);
    //     aliceSafe.addCollateralAndBorrow(
    //         address(newCollateralToken),
    //         1 ether,
    //         address(newBorrowToken),
    //         1 ether
    //     );

    //     uint256 timeElapsed = 24 * 60 * 60;
    //     uint256 expectedInterest = 1 ether * ((newBorrowTokenApy * timeElapsed) / 1e20);
        
    //     vm.warp(block.timestamp + timeElapsed);

    //     assertEq(
    //         etherFiCashDebtManager.borrowingOf(
    //             address(aliceSafe),
    //             address(newBorrowToken)
    //         ),
    //         ((1 ether + expectedInterest) * 1e6) /
    //             10 ** newBorrowToken.decimals()
    //     );

    //     vm.prank(etherFiWallet);
    //     aliceSafe.repay(address(newBorrowToken), 1 ether + expectedInterest);

    //     assertEq(
    //         etherFiCashDebtManager.supplierBalance(
    //             alice,
    //             address(newBorrowToken)
    //         ),
    //         newBorrowTokenSupplyAmt + expectedInterest / 2
    //     );
    //     assertEq(
    //         etherFiCashDebtManager.supplierBalance(
    //             owner,
    //             address(newBorrowToken)
    //         ),
    //         newBorrowTokenSupplyAmt + expectedInterest / 2
    //     );
    // }
}
