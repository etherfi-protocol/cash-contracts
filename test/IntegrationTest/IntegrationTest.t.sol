// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {IntegrationTestSetup, PriceProvider, MockPriceProvider, MockERC20} from "./IntegrationTestSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IntegrationTest is IntegrationTestSetup {
    using SafeERC20 for IERC20;

    IERC20 weth;
    uint256 collateralAmount = 0.01 ether;
    uint256 supplyAmount = 1e6;
    uint256 borrowAmount = 1e6;

    function setUp() public override {
        super.setUp();

        if (!isFork(chainId)) {
            /// If not mainnet, give some usdc to debt manager so it can provide debt
            vm.startPrank(owner);
            weth = IERC20(address(new MockERC20("WETH", "WETH", 18)));

            usdc.approve(address(etherFiCashDebtManager), supplyAmount);
            etherFiCashDebtManager.supply(
                address(owner),
                address(usdc),
                supplyAmount
            );
            vm.stopPrank();
        } else {
            vm.startPrank(owner);

            weth = IERC20(chainConfig.weth);

            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd))
            );
            cashDataProvider.setPriceProvider(address(priceProvider));

            address newCollateralToken = address(weth);
            uint256 newLtv = 80e18;
            uint256 newLiquidationThreshold = 85e18;

            etherFiCashDebtManager.supportCollateralToken(
                newCollateralToken,
                newLtv,
                newLiquidationThreshold
            );

            /// If it is mainnet, supply 0.01 weETH and borrow 1 USDC from Aave
            deal(
                address(weETH),
                address(etherFiCashDebtManager),
                collateralAmount
            );
            deal(
                address(weth),
                address(etherFiCashDebtManager),
                collateralAmount
            );
            etherFiCashDebtManager.fundManagementOperation(
                uint8(IL2DebtManager.MarketOperationType.SupplyAndBorrow),
                abi.encode(
                    address(weth),
                    collateralAmount,
                    address(usdc),
                    borrowAmount
                )
            );
            vm.stopPrank();
        }
    }

    function test_AddCollateral() public {
        uint256 amount = 0.01 ether;
        deal(address(weETH), address(aliceSafe), amount);

        uint256 aliceSafeCollateralBefore = etherFiCashDebtManager
            .getCollateralValueInUsdc(address(aliceSafe));
        assertEq(aliceSafeCollateralBefore, 0);

        uint256 aliceSafeBalBefore = weETH.balanceOf(address(aliceSafe));
        uint256 debtManagerBalBefore = weETH.balanceOf(
            address(etherFiCashDebtManager)
        );

        vm.prank(etherFiWallet);
        aliceSafe.addCollateral(address(weETH), amount);

        uint256 aliceSafeCollateralAfter = etherFiCashDebtManager
            .getCollateralValueInUsdc(address(aliceSafe));
        assertEq(
            aliceSafeCollateralAfter,
            etherFiCashDebtManager.convertCollateralTokenToUsdc(
                address(weETH),
                amount
            )
        );

        uint256 aliceSafeBalAfter = weETH.balanceOf(address(aliceSafe));
        uint256 debtManagerBalAfter = weETH.balanceOf(
            address(etherFiCashDebtManager)
        );

        assertEq(aliceSafeBalBefore - aliceSafeBalAfter, amount);
        assertEq(debtManagerBalAfter - debtManagerBalBefore, amount);
    }

    function test_AddCollateralAndBorrow() public {
        uint256 supplyAmt = 0.01 ether;
        uint256 borrowAmt = 1e6;

        deal(address(weETH), address(aliceSafe), supplyAmt);

        uint256 aliceSafeCollateralBefore = etherFiCashDebtManager
            .getCollateralValueInUsdc(address(aliceSafe));
        assertEq(aliceSafeCollateralBefore, 0);

        uint256 aliceSafeDebtBefore = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtBefore, 0);

        uint256 aliceSafeWeEthBalBefore = weETH.balanceOf(address(aliceSafe));
        uint256 cashSafeUsdcBalBefore = usdc.balanceOf(
            address(etherFiCashMultisig)
        );

        uint256 debtManagerWeEthBalBefore = weETH.balanceOf(
            address(etherFiCashDebtManager)
        );
        uint256 debtManagerUsdcBalBefore = usdc.balanceOf(
            address(etherFiCashDebtManager)
        );

        vm.prank(etherFiWallet);
        aliceSafe.addCollateralAndBorrow(
            address(weETH),
            supplyAmt,
            address(usdc),
            borrowAmt
        );

        uint256 aliceSafeCollateralAfter = etherFiCashDebtManager
            .getCollateralValueInUsdc(address(aliceSafe));
        assertEq(
            aliceSafeCollateralAfter,
            etherFiCashDebtManager.convertCollateralTokenToUsdc(
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
            address(etherFiCashMultisig)
        );

        uint256 debtManagerWeEthBalAfter = weETH.balanceOf(
            address(etherFiCashDebtManager)
        );
        uint256 debtManagerUsdcBalAfter = usdc.balanceOf(
            address(etherFiCashDebtManager)
        );

        assertEq(aliceSafeWeEthBalBefore - aliceSafeWeEthBalAfter, supplyAmt);
        assertEq(
            debtManagerWeEthBalAfter - debtManagerWeEthBalBefore,
            supplyAmt
        );
        assertEq(cashSafeUsdcBalAfter - cashSafeUsdcBalBefore, borrowAmt);
        assertEq(debtManagerUsdcBalBefore - debtManagerUsdcBalAfter, borrowAmt);
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
        uint256 debtManagerUsdcBalBefore = usdc.balanceOf(
            address(etherFiCashDebtManager)
        );
        uint256 aliceSafeDebtBefore = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtBefore, borrowAmt);

        aliceSafe.repay(address(usdc), repayAmt);

        uint256 aliceSafeUsdcBalAfter = usdc.balanceOf(address(aliceSafe));
        uint256 debtManagerUsdcBalAfter = usdc.balanceOf(
            address(etherFiCashDebtManager)
        );

        uint256 aliceSafeDebtAfter = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe),
            address(usdc)
        );
        assertEq(aliceSafeDebtAfter, 0);
        assertEq(aliceSafeUsdcBalBefore - aliceSafeUsdcBalAfter, repayAmt);
        assertEq(debtManagerUsdcBalAfter - debtManagerUsdcBalBefore, repayAmt);

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

    function test_MultipleSuppliers() public {
        vm.startPrank(owner);
        MockERC20 newCollateralToken = new MockERC20("CollToken", "CTK", 18);
        MockERC20 newBorrowToken = new MockERC20("DebtToken", "DTK", 18);

        uint256 newCollateralLtv = 80e18;
        uint256 newCollateralLiquidationThreshold = 85e18;
        uint256 newBorrowTokenApy = 1e18;

        etherFiCashDebtManager.supportCollateralToken(
            address(newCollateralToken),
            newCollateralLtv,
            newCollateralLiquidationThreshold
        );
        etherFiCashDebtManager.supportBorrowToken(
            address(newBorrowToken),
            newBorrowTokenApy
        );
        vm.stopPrank();

        deal(address(newCollateralToken), address(aliceSafe), 1000 ether);
        deal(address(newBorrowToken), address(aliceSafe), 1000 ether);
        deal(address(newBorrowToken), address(alice), 1000 ether);
        deal(address(newBorrowToken), address(owner), 1000 ether);

        uint256 newBorrowTokenSupplyAmt = 1 ether;
        vm.startPrank(alice);
        newBorrowToken.approve(
            address(etherFiCashDebtManager),
            newBorrowTokenSupplyAmt
        );
        etherFiCashDebtManager.supply(
            alice,
            address(newBorrowToken),
            newBorrowTokenSupplyAmt
        );

        assertEq(
            etherFiCashDebtManager.withdrawableBorrowToken(
                alice,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt
        );

        IL2DebtManager.BorrowTokenConfig
            memory borrowTokenConfig = etherFiCashDebtManager.borrowTokenConfig(
                address(newBorrowToken)
            );

        assertEq(
            borrowTokenConfig.totalSharesOfBorrowTokens,
            newBorrowTokenSupplyAmt
        );
        vm.stopPrank();

        vm.startPrank(owner);
        newBorrowToken.approve(
            address(etherFiCashDebtManager),
            newBorrowTokenSupplyAmt
        );
        etherFiCashDebtManager.supply(
            owner,
            address(newBorrowToken),
            newBorrowTokenSupplyAmt
        );

        assertEq(
            etherFiCashDebtManager.withdrawableBorrowToken(
                owner,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt
        );

        borrowTokenConfig = etherFiCashDebtManager.borrowTokenConfig(
            address(newBorrowToken)
        );

        assertEq(
            borrowTokenConfig.totalSharesOfBorrowTokens,
            2 * newBorrowTokenSupplyAmt
        );
        vm.stopPrank();

        vm.prank(etherFiWallet);
        aliceSafe.addCollateralAndBorrow(
            address(newCollateralToken),
            1 ether,
            address(newBorrowToken),
            1 ether
        );

        uint256 timeElapsed = 24 * 60 * 60;
        vm.warp(block.timestamp + 24 * 60 * 60);

        uint256 expectedInterest = (1 ether * newBorrowTokenApy * timeElapsed) /
            1e20;
        assertEq(
            etherFiCashDebtManager.borrowingOf(
                address(aliceSafe),
                address(newBorrowToken)
            ),
            ((1 ether + expectedInterest) * 1e6) /
                10 ** newBorrowToken.decimals()
        );

        vm.prank(etherFiWallet);
        aliceSafe.repay(address(newBorrowToken), 1 ether + expectedInterest);

        assertEq(
            etherFiCashDebtManager.withdrawableBorrowToken(
                alice,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt + expectedInterest / 2
        );
        assertEq(
            etherFiCashDebtManager.withdrawableBorrowToken(
                owner,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt + expectedInterest / 2
        );
    }
}
