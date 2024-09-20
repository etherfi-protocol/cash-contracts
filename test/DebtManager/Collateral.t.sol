// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, PriceProvider, MockPriceProvider} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract DebtManagerCollateralTest is DebtManagerSetup {
    using stdStorage for StdStorage;
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
        collateralTokenConfig.liquidationBonus = 10e18;

        vm.startPrank(owner);
        vm.expectRevert(
            IL2DebtManager.LtvCannotBeGreaterThanLiquidationThreshold.selector
        );
        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfig);
        vm.stopPrank();
    }

    function test_LiquidationParamsCannotBeInvalid() public {
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 80e18;
        collateralTokenConfig.liquidationThreshold = 90e18;
        collateralTokenConfig.liquidationBonus = 11e18;

        vm.startPrank(owner);
        vm.expectRevert(
            IL2DebtManager.InvalidValue.selector
        );
        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfig);
        vm.stopPrank();
    }

    function test_CanAddOrRemoveSupportedCollateralTokens() public {
        vm.startPrank(owner);
        
        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd))
        );

        cashDataProvider.setPriceProvider(address(priceProvider));

        address newCollateralToken = address(usdc);
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = newLtv;
        collateralTokenConfig.liquidationThreshold = newLiquidationThreshold;
        collateralTokenConfig.liquidationBonus = newLiquidationBonus;

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigBefore;

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.CollateralTokenAdded(newCollateralToken);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.CollateralTokenConfigSet(newCollateralToken, collateralTokenConfigBefore, collateralTokenConfig);
        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfig
        );

        IL2DebtManager.CollateralTokenConfig memory configFromContract = debtManager
            .collateralTokenConfig(newCollateralToken);

        assertEq(configFromContract.ltv, newLtv);
        assertEq(configFromContract.liquidationThreshold, newLiquidationThreshold);
        assertEq(configFromContract.liquidationBonus, newLiquidationBonus);
        
        assertEq(debtManager.getCollateralTokens().length, 2);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));
        assertEq(debtManager.getCollateralTokens()[1], newCollateralToken);

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigAfter = collateralTokenConfigBefore;
        collateralTokenConfigBefore = debtManager.collateralTokenConfig(address(weETH));
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.CollateralTokenConfigSet(address(weETH), collateralTokenConfigBefore, collateralTokenConfigAfter);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.CollateralTokenRemoved(address(weETH));
        debtManager.unsupportCollateralToken(address(weETH));
        assertEq(debtManager.getCollateralTokens().length, 1);
        assertEq(debtManager.getCollateralTokens()[0], newCollateralToken);

        IL2DebtManager.CollateralTokenConfig memory configWethFromContract = debtManager
            .collateralTokenConfig(address(weETH));
        assertEq(configWethFromContract.ltv, 0);
        assertEq(configWethFromContract.liquidationThreshold, 0);
        assertEq(configWethFromContract.liquidationBonus, 0);

        vm.stopPrank();
    }

    function test_CannotAddCollateralTokenIfLtvGreaterThanLiquidationThreshold() public {
        vm.startPrank(owner);
        
        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd))
        );

        cashDataProvider.setPriceProvider(address(priceProvider));

        address newCollateralToken = address(usdc);
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 10;
        collateralTokenConfig.liquidationThreshold = 5;
        collateralTokenConfig.liquidationBonus = 5;

        vm.expectRevert(IL2DebtManager.LtvCannotBeGreaterThanLiquidationThreshold.selector);
        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfig
        );
        vm.stopPrank();
    }

    function test_CannotAddCollateralTokenIfLiquidationParamsAreInvalid() public {
        vm.startPrank(owner);
        
        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd))
        );

        cashDataProvider.setPriceProvider(address(priceProvider));

        address newCollateralToken = address(usdc);
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = 80e18;
        collateralTokenConfig.liquidationThreshold = 90e18;
        collateralTokenConfig.liquidationBonus = 11e18;

        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfig
        );
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

    function test_CannotUnsupportCollateralTokenIfTotalCollateralNotZeroForTheToken()
        public
    {
        assertEq(wweETH.isWhitelistedMinter(address(debtManager)), true);
        uint256 amount = 0.1 ether;
        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), amount);
        debtManager.depositCollateral(address(weETH), alice, amount);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.TotalCollateralAmountNotZero.selector);
        debtManager.unsupportCollateralToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotUnsupportTokenForCollateralIfItIsNotACollateralTokenAlready()
        public
    {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NotACollateralToken.selector);
        debtManager.unsupportCollateralToken(address(usdc));
        vm.stopPrank();
    }

    function test_CannotUnsupportAllTokensAsCollateral() public {
        vm.startPrank(owner);
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

    function test_DepositCollateral() public {
        uint256 amount = 0.01 ether;

        (
            IL2DebtManager.TokenData[] memory collateralsBefore,
            uint256 collateralInUsdcBefore
        ) = debtManager.collateralOf(alice);

        assertEq(collateralsBefore.length, 1);
        assertEq(collateralsBefore[0].token, address(weETH));
        assertEq(collateralsBefore[0].amount, 0);
        assertEq(collateralInUsdcBefore, 0);

        (
            uint256 userCollateralForTokenBefore,
            uint256 userCollateralForTokenInUsdcBefore
        ) = debtManager.getUserCollateralForToken(alice, address(weETH));
        assertEq(userCollateralForTokenBefore, 0);
        assertEq(userCollateralForTokenInUsdcBefore, 0);

        (
            IL2DebtManager.TokenData[] memory totalCollateralAmountBefore,
            uint256 totalCollateralInUsdcBefore
        ) = debtManager.totalCollateralAmounts();
        assertEq(totalCollateralAmountBefore[0].token, address(weETH));
        assertEq(totalCollateralAmountBefore[0].amount, 0);
        assertEq(totalCollateralInUsdcBefore, 0);

        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), amount);

        debtManager.depositCollateral(address(weETH), alice, amount);

        assertEq(weETH.balanceOf(address(wweETH)), amount);
        assertEq(aaveV3Adapter.getCollateralBalance(address(debtManager), address(wweETH)), amount);

        (
            IL2DebtManager.TokenData[] memory collateralsAfter,
            uint256 collateralInUsdcAfter
        ) = debtManager.collateralOf(alice);

        uint256 collateralValueInUsdc = debtManager
            .convertCollateralTokenToUsdc(address(weETH), amount);

        assertEq(collateralsAfter.length, 1);
        assertEq(collateralsAfter[0].token, address(weETH));
        assertEq(collateralsAfter[0].amount, amount);
        assertEq(collateralInUsdcAfter, collateralValueInUsdc);

        (
            uint256 userCollateralForTokenAfter,
            uint256 userCollateralForTokenInUsdcAfter
        ) = debtManager.getUserCollateralForToken(alice, address(weETH));

        assertEq(userCollateralForTokenAfter, amount);
        assertEq(userCollateralForTokenInUsdcAfter, collateralValueInUsdc);

        (
            IL2DebtManager.TokenData[] memory totalCollateralAmountAfter,
            uint256 totalCollateralInUsdcAfter
        ) = debtManager.totalCollateralAmounts();
        assertEq(totalCollateralAmountAfter[0].token, address(weETH));
        assertEq(totalCollateralAmountAfter[0].amount, amount);
        assertEq(totalCollateralInUsdcAfter, collateralValueInUsdc);

        vm.stopPrank();
    }

    function test_CannotDepositCollateralIfAaveAdapterNotSet() public {
        stdstore
            .target(address(cashDataProvider))
            .sig("aaveAdapter()")
            .checked_write(address(0));
        
        assertEq(cashDataProvider.aaveAdapter(), address(0));
        
        uint256 amount = 0.01 ether;

        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), amount);
        
        vm.expectRevert(IL2DebtManager.AaveAdapterNotSet.selector);
        debtManager.depositCollateral(address(weETH), alice, amount);
        vm.stopPrank();
    }

    function test_CannotDepositCollateralIfTokenNotSupported() public {
        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(notOwner);

        vm.prank(notOwner);
        vm.expectRevert(IL2DebtManager.UnsupportedCollateralToken.selector);
        debtManager.depositCollateral(address(usdc), alice, 1);
    }

    function test_CannotDepositCollateralOverSupplyCap() public {
        uint256 amount = supplyCap + 1;
        deal(address(weETH), alice, amount);
        vm.startPrank(alice);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), amount);
        vm.expectRevert(IL2DebtManager.SupplyCapBreached.selector);
        debtManager.depositCollateral(address(weETH), alice, amount);
        vm.stopPrank();
    }

    function test_CannotDepositCollateralIfAllownaceIsInsufficient() public {
        deal(address(weETH), notOwner, 2);

        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(notOwner);

        vm.startPrank(notOwner);
        IERC20(address(weETH)).forceApprove(address(debtManager), 1);

        if (!isFork(chainId) || isScroll(chainId))
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector,
                    address(debtManager),
                    1,
                    2
                )
            );
        else vm.expectRevert("ERC20: transfer amount exceeds allowance");

        debtManager.depositCollateral(address(weETH), alice, 2);

        vm.stopPrank();
    }

    function test_CannotDepositCollateralIfBalanceIsInsufficient() public {
        vm.prank(address(userSafeFactory));
        cashDataProvider.whitelistUserSafe(notOwner);

        vm.startPrank(notOwner);
        IERC20(address(weETH)).safeIncreaseAllowance(address(debtManager), 1);

        if (!isFork(chainId) || isScroll(chainId))
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    notOwner,
                    0,
                    1
                )
            );
        else vm.expectRevert("ERC20: transfer amount exceeds balance");

        debtManager.depositCollateral(address(weETH), alice, 1);
        vm.stopPrank();
    }
    
    function test_CannotDepositCollateralIfNotUserSafe() public {
        vm.expectRevert(IL2DebtManager.OnlyUserSafe.selector);
        debtManager.depositCollateral(address(weETH), alice, 1);
    }
}
