// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, PriceProvider, MockPriceProvider, MockERC20} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {AaveLib} from "../../src/libraries/AaveLib.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DebtManagerFundManagementTest is DebtManagerSetup {
    using SafeERC20 for IERC20;

    uint256 collateralAmt = 0.01 ether;
    IERC20 weth;

    function setUp() public override {
        super.setUp();

        if (!isFork(chainId))
            weth = IERC20(address(new MockERC20("WETH", "WETH", 18)));
        else weth = IERC20(chainConfig.weth);

        deal(address(weETH), address(owner), 1000 ether);
        deal(address(usdc), address(owner), 1 ether);

        vm.startPrank(owner);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmt);
        debtManager.depositCollateral(address(weETH), owner, collateralAmt);
        vm.stopPrank();
    }

    function test_Supply() public {
        uint256 principle = 0.01 ether;

        vm.startPrank(owner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(owner, owner, address(usdc), principle);
        debtManager.supply(owner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.withdrawableBorrowToken(owner, address(usdc)),
            principle
        );

        uint256 earnings = _borrowAndRepay(principle);

        assertEq(
            debtManager.withdrawableBorrowToken(owner, address(usdc)),
            principle + earnings
        );

        vm.prank(owner);
        debtManager.withdrawBorrowToken(address(usdc), earnings + principle);

        assertEq(debtManager.withdrawableBorrowToken(owner, address(usdc)), 0);
    }

    function test_SupplyTwice() public {
        uint256 principle = 0.01 ether;
        vm.startPrank(owner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(owner, owner, address(usdc), principle);
        debtManager.supply(owner, address(usdc), principle);
        vm.stopPrank();

        deal(address(usdc), alice, principle);
        
        vm.startPrank(alice);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(alice, alice, address(usdc), principle);
        debtManager.supply(alice, address(usdc), principle);
        vm.stopPrank();
    }

    function test_CanOnlySupplyBorrowTokens() public {
        vm.prank(alice);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.supply(owner, address(weETH), 1);
    }

    function test_CannotWithdrawTokenThatWasNotSupplied() public {
        vm.prank(owner);
        vm.expectRevert(IL2DebtManager.SharesCannotBeZero.selector);
        debtManager.withdrawBorrowToken(address(weETH), 1 ether);
    }

    function test_FundsManagementOnAave() public {
        vm.startPrank(owner);

        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd))
        );
        cashDataProvider.setPriceProvider(address(priceProvider));

        address newCollateralToken = address(weth);
        uint80 newLtv = 80e18;
        uint80 newLiquidationThreshold = 85e18;
        uint96 newLiquidationBonus = 10e18;

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = newLtv;
        collateralTokenConfig.liquidationThreshold = newLiquidationThreshold;
        collateralTokenConfig.liquidationBonus = newLiquidationBonus;


        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfig
        );

        deal(address(weth), address(debtManager), 1000 ether);

        ///// SUPPLY
        uint256 totalCollateralInAaveBefore = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weth));
        assertEq(totalCollateralInAaveBefore, 0);

        debtManager.fundManagementOperation(
            uint8(AaveLib.MarketOperationType.Supply),
            abi.encode(address(weth), collateralAmt)
        );

        uint256 totalCollateralInAaveAfter = aaveV3Adapter.getCollateralBalance(
            address(debtManager),
            address(weth)
        );
        assertEq(totalCollateralInAaveAfter, collateralAmt);

        ///// BORROW
        uint256 totalBorrowInAaveBefore = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveBefore, 0);

        uint256 borrowAmt = 1e6;
        debtManager.fundManagementOperation(
            uint8(AaveLib.MarketOperationType.Borrow),
            abi.encode(address(usdc), borrowAmt)
        );

        uint256 totalBorrowInAaveAfter = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveAfter, borrowAmt);

        ///// REPAY
        if (!isFork(chainId)) {
            IERC20(address(usdc)).safeTransfer(address(debtManager), 10e6);
        }

        uint256 totalBorrowInAaveBeforeRepay = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveBeforeRepay, borrowAmt);

        debtManager.fundManagementOperation(
            uint8(AaveLib.MarketOperationType.Repay),
            abi.encode(address(usdc), totalBorrowInAaveBeforeRepay)
        );
        uint256 totalBorrowInAaveAfterRepay = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveAfterRepay, 0);

        ///// WITHDRAW
        uint256 totalCollateralInAaveBeforeWithdraw = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weth));
        assertEq(totalCollateralInAaveBeforeWithdraw, collateralAmt);

        debtManager.fundManagementOperation(
            uint8(AaveLib.MarketOperationType.Withdraw),
            abi.encode(address(weth), totalCollateralInAaveBeforeWithdraw)
        );

        uint256 totalCollateralInAaveAfterWithdraw = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weth));
        assertEq(totalCollateralInAaveAfterWithdraw, 0);

        ///// SUPPLY AND BORROW

        uint256 totalCollateralInAaveBeforeSupplyAndBorrow = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weth));
        assertEq(totalCollateralInAaveBeforeSupplyAndBorrow, 0);
        uint256 totalBorrowInAaveBeforeSupplyAndBorrow = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveBeforeSupplyAndBorrow, 0);

        debtManager.fundManagementOperation(
            uint8(AaveLib.MarketOperationType.SupplyAndBorrow),
            abi.encode(address(weth), collateralAmt, address(usdc), 1e6)
        );

        uint256 totalCollateralInAaveAfterSupplyAndBorrow = aaveV3Adapter
            .getCollateralBalance(address(debtManager), address(weth));
        assertEq(totalCollateralInAaveAfterSupplyAndBorrow, collateralAmt);
        uint256 totalBorrowInAaveAfterSupplyAndBorrow = aaveV3Adapter.getDebt(
            address(debtManager),
            address(usdc)
        );
        assertEq(totalBorrowInAaveAfterSupplyAndBorrow, 1e6);

        vm.stopPrank();
    }

    function test_OnlyAdminCanManageFunds() public {
        vm.startPrank(notOwner);
        vm.expectRevert(
            buildAccessControlRevertData(notOwner, debtManager.ADMIN_ROLE())
        );
        debtManager.fundManagementOperation(
            uint8(AaveLib.MarketOperationType.Supply),
            abi.encode(address(weETH), collateralAmt)
        );

        vm.stopPrank();
    }

    function _borrowAndRepay(
        uint256 collateralAmount
    ) internal returns (uint256) {
        deal(address(usdc), alice, 1 ether);
        deal(address(weETH), alice, 1000 ether);

        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);

        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(
            alice
        ) / 2;
        debtManager.borrow(address(usdc), borrowAmt);

        // 1 day after, there should be some interest accumulated
        vm.warp(block.timestamp + 24 * 60 * 60);
        uint256 repayAmt = debtManager.borrowingOf(alice, address(usdc));

        IERC20(address(usdc)).forceApprove(address(debtManager), repayAmt);
        debtManager.repay(alice, address(usdc), repayAmt);
        vm.stopPrank();

        return repayAmt - borrowAmt;
    }
}
