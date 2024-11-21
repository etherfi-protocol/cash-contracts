// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup, PriceProvider, MockPriceProvider, MockERC20} from "../Setup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract DebtManagerCollateralTest is Setup {
    using SafeERC20 for IERC20;

    uint80 newLtv = 80e18;
    uint80 newLiquidationThreshold = 85e18;
    uint96 newLiquidationBonus = 10e18;

    function setUp() public override {
        super.setUp();

        deal(address(usdc), alice, 1 ether);
        deal(address(weETH), alice, 1000 ether);
    }

    function test_LtvCannotBeGreaterThanLiquidationThreshold() public {
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 90e18;
        collateralTokenConfig.liquidationThreshold = 80e18;

        vm.startPrank(owner);
        vm.expectRevert(
            IL2DebtManager.LtvCannotBeGreaterThanLiquidationThreshold.selector
        );
        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfig);
        vm.stopPrank();
    }

    function test_CanAddOrRemoveSupportedCollateralTokens() public {
        vm.startPrank(owner);
        address newCollateralToken = address(new MockERC20("CollToken", "CTK", 18));
        
        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd, address(usdc)))
        );

        cashDataProvider.setPriceProvider(address(priceProvider));

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = newLtv;
        collateralTokenConfig.liquidationThreshold = newLiquidationThreshold;
        collateralTokenConfig.liquidationBonus = newLiquidationBonus;

        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfig
        );

        IL2DebtManager.CollateralTokenConfig memory configFromContract = debtManager
            .collateralTokenConfig(newCollateralToken);

        assertEq(configFromContract.ltv, newLtv);
        assertEq(configFromContract.liquidationThreshold, newLiquidationThreshold);
        assertEq(configFromContract.liquidationBonus, newLiquidationBonus);
        
        assertEq(debtManager.getCollateralTokens().length, 3);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));
        assertEq(debtManager.getCollateralTokens()[1], address(usdc));
        assertEq(debtManager.getCollateralTokens()[2], newCollateralToken);

        debtManager.unsupportCollateralToken(address(weETH));
        assertEq(debtManager.getCollateralTokens().length, 2);
        assertEq(debtManager.getCollateralTokens()[0], newCollateralToken);
        assertEq(debtManager.getCollateralTokens()[1], address(usdc));

        IL2DebtManager.CollateralTokenConfig memory configWethFromContract = debtManager
            .collateralTokenConfig(address(weETH));
        assertEq(configWethFromContract.ltv, 0);
        assertEq(configWethFromContract.liquidationThreshold, 0);
        assertEq(configWethFromContract.liquidationBonus, 0);

        vm.stopPrank();
    }

    function test_OnlyAdminCanSupportOrUnsupportCollateral() public {
        address newCollateralToken = address(usdc);

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = newLtv;
        collateralTokenConfig.liquidationThreshold = newLiquidationThreshold;
        collateralTokenConfig.liquidationBonus = newLiquidationBonus;

        vm.startPrank(alice);
        vm.expectRevert(
            buildAccessControlRevertData(alice, ADMIN_ROLE)
        );
        debtManager.supportCollateralToken(newCollateralToken, collateralTokenConfig);
        vm.expectRevert(
            buildAccessControlRevertData(alice, ADMIN_ROLE)
        );
        debtManager.unsupportCollateralToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotAddCollateralTokenIfAlreadySupported() public {
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = newLtv;
        collateralTokenConfig.liquidationThreshold = newLiquidationThreshold;
        collateralTokenConfig.liquidationBonus = newLiquidationBonus;

        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.AlreadyCollateralToken.selector);
        debtManager.supportCollateralToken(address(weETH), collateralTokenConfig);
        vm.stopPrank();
    }

    function test_CannotAddNullAddressAsCollateralToken() public {
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = newLtv;
        collateralTokenConfig.liquidationThreshold = newLiquidationThreshold;
        collateralTokenConfig.liquidationBonus = newLiquidationBonus;

        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.supportCollateralToken(address(0), collateralTokenConfig);
        vm.stopPrank();
    }

    function test_CannotUnsupportTokenForCollateralIfItIsNotACollateralTokenAlready() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NotACollateralToken.selector);
        debtManager.unsupportCollateralToken(address(1));
        vm.stopPrank();
    }

    function test_CannotUnsupportAllTokensAsCollateral() public {
        vm.startPrank(owner);
        debtManager.unsupportCollateralToken(address(usdc));
        vm.expectRevert(IL2DebtManager.NoCollateralTokenLeft.selector);
        debtManager.unsupportCollateralToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotUnsupportAddressZeroAsCollateralToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.unsupportCollateralToken(address(0));
        vm.stopPrank();
    }
}
