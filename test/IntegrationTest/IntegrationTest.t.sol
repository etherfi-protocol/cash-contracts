// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IntegrationTestSetup} from "./IntegrationTestSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";

contract IntegrationTest is IntegrationTestSetup {
    function setUp() public override {
        super.setUp();

        if (!isFork(chainId)) {
            /// If not mainnet, give some usdc to debt manager so it can provide debt
            deal(address(usdc), address(etherFiCashDebtManager), 1 ether);
        } else {
            /// If it is mainnet, supply 0.01 weETH and borrow 1 USDC from Aave
            deal(address(weETH), address(owner), 0.01 ether);
            vm.startPrank(owner);
            etherFiCashDebtManager.fundManagementOperation(
                uint8(IL2DebtManager.MarketOperationType.SupplyAndBorrow),
                abi.encode(address(weETH), 0.01 ether, address(usdc), 1e6)
            );
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
            address(aliceSafe)
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
            address(aliceSafe)
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
            address(aliceSafe)
        );
        assertEq(aliceSafeDebtBefore, borrowAmt);

        aliceSafe.repay(address(usdc), repayAmt);

        uint256 aliceSafeUsdcBalAfter = usdc.balanceOf(address(aliceSafe));
        uint256 debtManagerUsdcBalAfter = usdc.balanceOf(
            address(etherFiCashDebtManager)
        );

        uint256 aliceSafeDebtAfter = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe)
        );
        assertEq(aliceSafeDebtAfter, 0);
        assertEq(aliceSafeUsdcBalBefore - aliceSafeUsdcBalAfter, repayAmt);
        assertEq(debtManagerUsdcBalAfter - debtManagerUsdcBalBefore, repayAmt);

        vm.stopPrank();
    }

    function test_RepayUsingWeETH() public {
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

        uint256 aliceSafeCollateralBefore = etherFiCashDebtManager
            .getCollateralValueInUsdc(address(aliceSafe));
        uint256 aliceSafeDebtBefore = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe)
        );
        assertEq(aliceSafeDebtBefore, borrowAmt);

        aliceSafe.repay(address(weETH), repayAmt);

        uint256 aliceSafeCollateralAfter = etherFiCashDebtManager
            .getCollateralValueInUsdc(address(aliceSafe));

        uint256 aliceSafeDebtAfter = etherFiCashDebtManager.borrowingOf(
            address(aliceSafe)
        );
        assertEq(aliceSafeDebtAfter, 0);
        assertEq(
            aliceSafeCollateralBefore - aliceSafeCollateralAfter,
            repayAmt
        );

        vm.stopPrank();
    }
}
