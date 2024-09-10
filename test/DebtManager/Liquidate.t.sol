// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, PriceProvider, MockPriceProvider, MockERC20} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract DebtManagerLiquidateTest is DebtManagerSetup {
    using SafeERC20 for IERC20;

    uint256 collateralAmount = 0.01 ether;
    uint256 collateralValueInUsdc;
    uint256 borrowAmt;

    function setUp() public override {
        super.setUp();

        collateralValueInUsdc = debtManager.convertCollateralTokenToUsdc(
            address(weETH),
            collateralAmount
        );

        deal(address(usdc), alice, 1 ether);
        deal(address(usdc), owner, 1 ether);
        deal(address(weETH), alice, 1000 ether);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);

        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), collateralAmount);
        debtManager.depositCollateral(address(weETH), alice, collateralAmount);

        borrowAmt = debtManager.remainingBorrowingCapacityInUSDC(alice);

        debtManager.borrow(address(usdc), borrowAmt);
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold() public {     
        uint80 newThreshold = 70e18;

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig = debtManager.collateralTokenConfig(address(weETH));
        collateralTokenConfig.liquidationThreshold = newThreshold;

        vm.prank(owner);
        debtManager.setCollateralTokenConfig(
            address(weETH),
            collateralTokenConfig
        );

        IL2DebtManager.CollateralTokenConfig memory configFromContract = debtManager.collateralTokenConfig(
            address(weETH)
        );

        assertEq(configFromContract.liquidationThreshold, newThreshold);
    }

    function test_OnlyAdminCanSetLiquidationThreshold() public {
        uint80 newThreshold = 70e18;
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig = debtManager.collateralTokenConfig(address(weETH));
        collateralTokenConfig.liquidationThreshold = newThreshold;

        vm.startPrank(notOwner);
        vm.expectRevert(
            buildAccessControlRevertData(notOwner, debtManager.ADMIN_ROLE())
        );
        debtManager.setCollateralTokenConfig(
            address(weETH),
            collateralTokenConfig
        );

        vm.stopPrank();
    }

    function test_Liquidate() public {
        vm.startPrank(owner);

        uint256 liquidatorWeEthBalBefore = weETH.balanceOf(owner);

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 5e18;
        collateralTokenConfig.liquidationThreshold = 10e18;
        collateralTokenConfig.liquidationBonus = 5e18;

        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfig);
        assertEq(debtManager.liquidatable(alice), true);

        address[] memory collateralTokenPreference = debtManager.getCollateralTokens();

        IERC20(address(usdc)).forceApprove(address(debtManager), borrowAmt);
        debtManager.liquidate(alice, address(usdc), collateralTokenPreference, borrowAmt);

        vm.stopPrank();

        uint256 aliceCollateralAfter = debtManager.getCollateralValueInUsdc(
            alice
        );
        uint256 aliceDebtAfter = debtManager.borrowingOf(alice, address(usdc));
        uint256 liquidatorWeEthBalAfter = weETH.balanceOf(owner);

        uint256 liquidatedUsdcCollateralAmt = debtManager.convertUsdcToCollateralToken(address(weETH), borrowAmt);
        uint256 liquidationBonusReceived =  (
            liquidatedUsdcCollateralAmt * collateralTokenConfig.liquidationBonus
        ) / debtManager.HUNDRED_PERCENT();
        uint256 liquidationBonusInUsdc = debtManager.convertCollateralTokenToUsdc(address(weETH), liquidationBonusReceived);

        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsdc(
                address(weETH),
                liquidatorWeEthBalAfter - liquidatorWeEthBalBefore - liquidationBonusReceived
            ),
            borrowAmt,
            10
        );
        assertEq(aliceCollateralAfter, collateralValueInUsdc - borrowAmt - liquidationBonusInUsdc);
        assertEq(aliceDebtAfter, 0);
    }

    function test_PartialLiquidate() public {
        vm.startPrank(owner);

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 5e18;
        collateralTokenConfig.liquidationThreshold = 10e18;
        collateralTokenConfig.liquidationBonus = 5e18;

        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfig);
        assertEq(debtManager.liquidatable(alice), true);

        // since we will be setting the liquidation threshold to 10%
        uint256 maxBorrow = collateralValueInUsdc / 10;
        uint256 liquidatorWeEthBalBefore = weETH.balanceOf(owner);
        uint256 liquidationAmt = borrowAmt - (maxBorrow / 3);

        address[] memory collateralTokenPreference = debtManager.getCollateralTokens();

        IERC20(address(usdc)).forceApprove(address(debtManager), liquidationAmt);
        debtManager.liquidate(alice, address(usdc), collateralTokenPreference, liquidationAmt);

        vm.stopPrank();

        uint256 aliceCollateralAfter = debtManager.getCollateralValueInUsdc(
            alice
        );
        uint256 aliceDebtAfter = debtManager.borrowingOf(alice, address(usdc));
        uint256 liquidatorWeEthBalAfter = weETH.balanceOf(owner);

        uint256 liquidatedUsdcCollateralAmt = debtManager.convertUsdcToCollateralToken(address(weETH), liquidationAmt);
        uint256 liquidationBonusReceived =  (
            liquidatedUsdcCollateralAmt * collateralTokenConfig.liquidationBonus
        ) / debtManager.HUNDRED_PERCENT();
        uint256 liquidationBonusInUsdc = debtManager.convertCollateralTokenToUsdc(address(weETH), liquidationBonusReceived);


        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsdc(
                address(weETH),
                liquidatorWeEthBalAfter - liquidatorWeEthBalBefore - liquidationBonusReceived
            ),
            liquidationAmt,
            10
        );
        assertApproxEqAbs(
            aliceCollateralAfter,
            collateralValueInUsdc - liquidationAmt - liquidationBonusInUsdc,
            10
        );
        assertApproxEqAbs(aliceDebtAfter, maxBorrow / 3, 10);
    }

    function test_CannotLiquidateIfNotLiquidatable() public {
        vm.startPrank(owner);
        assertEq(debtManager.liquidatable(alice), false);
        IERC20(address(usdc)).forceApprove(address(debtManager), borrowAmt);

        address[] memory collateralTokens = debtManager.getCollateralTokens();
        vm.expectRevert(IL2DebtManager.CannotLiquidateYet.selector);
        debtManager.liquidate(alice, address(usdc), collateralTokens, borrowAmt);

        vm.stopPrank();
    }

    function test_ChooseCollateralPreferenceWhenLiquidating() public {
        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd))
        );
        vm.prank(owner);
        cashDataProvider.setPriceProvider(address(priceProvider));
        
        address newCollateralToken = address(new MockERC20("collateral", "CTK", 18));
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigNewCollateralToken;
        collateralTokenConfigNewCollateralToken.ltv = 5e18;
        collateralTokenConfigNewCollateralToken.liquidationThreshold = 10e18;
        collateralTokenConfigNewCollateralToken.liquidationBonus = 10e18;
        deal(newCollateralToken, owner, 100 ether);

        vm.startPrank(owner);
        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfigNewCollateralToken
        );

        uint256 collateralAmtNewToken = 0.005 ether;

        // Add some amount of collateral for the new token as well
        IERC20(address(newCollateralToken)).safeIncreaseAllowance(address(debtManager), collateralAmtNewToken);
        debtManager.depositCollateral(address(newCollateralToken), alice, collateralAmtNewToken);

        // Lower the thresholds for weETH as well
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigWeETH;
        collateralTokenConfigWeETH.ltv = 5e18;
        collateralTokenConfigWeETH.liquidationThreshold = 10e18;
        collateralTokenConfigWeETH.liquidationBonus = 5e18;
        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfigWeETH);

        address[] memory collateralTokenPreference = new address[](2);
        collateralTokenPreference[0] = newCollateralToken;
        collateralTokenPreference[1] = address(weETH);

        assertEq(debtManager.liquidatable(alice), true);

        // currently, alice collateral -> 
        // 0.01 weETH + 0.005 newToken  => 30 + 15 = 45 USDC (since 3000 is the default price in mock price provider)
        // alice debt -> 30 * 50% = 15 USD (initial collateral 30 USD, LTV: 50%)
        // When we liquidate -> user should receive the following:
        
        // for a debt of 15 USD ->

        // new token is first in preference 
        // total collateral in new token -> 0.005 * 3000 = 15 USDC
        // liquidation bonus -> 0.005 * 10% bonus -> 0.0005 in collateral tokens -> 1.5 USDC 
        // so new token wipes off 15 - 1.5 = 13.5 USDC of debt
        
        // weETH is second in preference 
        // total collateral in weETH -> 0.01 * 3000 = 30 USDC
        // total debt left = 1.5 USDC
        // total collateral worth 1.5 USDC in weETH -> 1.5 / 3000 -> 0.0005
        // total bonus on 0.0005 weETH => 0.0005 * 5% = 0.000025

        uint256 ownerWeETHBalBefore = weETH.balanceOf(owner);
        uint256 ownerNewTokenBalBefore = IERC20(newCollateralToken).balanceOf(owner);
        uint256 aliceDebtBefore = debtManager.borrowingOf(alice, address(usdc));

        IERC20(address(usdc)).forceApprove(address(debtManager), borrowAmt);
        debtManager.liquidate(alice, address(usdc), collateralTokenPreference, borrowAmt);

        vm.stopPrank();

        _validate(newCollateralToken, ownerNewTokenBalBefore, ownerWeETHBalBefore, aliceDebtBefore);
    }

    function _validate(
        address newCollateralToken,
        uint256 ownerNewTokenBalBefore,
        uint256 ownerWeETHBalBefore,
        uint256 aliceDebtBefore
    ) internal view {
        uint256 ownerWeETHBalAfter = weETH.balanceOf(owner);
        uint256 ownerNewTokenBalAfter = IERC20(newCollateralToken).balanceOf(owner);
        uint256 aliceDebtAfter = debtManager.borrowingOf(alice, address(usdc));

        uint256 borrowWipedByNewToken = 13.5 * 1e6;
        uint256 borrowWipedByWeETH = 1.5 * 1e6;
        uint256 liquidationBonusNewToken = 0.0005 ether;
        uint256 liquidationBonusWeETH = 0.000025 ether;

        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsdc(
                address(newCollateralToken),
                ownerNewTokenBalAfter - ownerNewTokenBalBefore - liquidationBonusNewToken
            ),
            borrowWipedByNewToken,
            10
        );
        
        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsdc(
                address(weETH),
                ownerWeETHBalAfter - ownerWeETHBalBefore - liquidationBonusWeETH
            ),
            borrowWipedByWeETH,
            10
        );

        assertEq(aliceDebtBefore, borrowAmt);
        assertEq(aliceDebtAfter, 0);
    }
}
