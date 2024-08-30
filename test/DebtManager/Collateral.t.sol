// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract DebtManagerCollateralTest is DebtManagerSetup {
    using SafeERC20 for IERC20;

    uint256 newLtv = 80e18;
    uint256 newLiquidationThreshold = 85e18;

    function setUp() public override {
        super.setUp();

        deal(address(usdc), alice, 1 ether);
        deal(address(weETH), alice, 1000 ether);
    }

    function test_CanAddOrRemoveSupportedCollateralTokens() public {
        address newCollateralToken = address(usdc);

        vm.startPrank(owner);
        debtManager.supportCollateralToken(
            newCollateralToken,
            newLtv,
            newLiquidationThreshold
        );

        (uint256 _ltv, uint256 _liquidationThreshold) = debtManager
            .collateralTokenConfig(newCollateralToken);

        assertEq(_ltv, newLtv);
        assertEq(_liquidationThreshold, newLiquidationThreshold);

        assertEq(debtManager.getCollateralTokens().length, 2);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));
        assertEq(debtManager.getCollateralTokens()[1], newCollateralToken);

        debtManager.unsupportCollateralToken(address(weETH));
        assertEq(debtManager.getCollateralTokens().length, 1);
        assertEq(debtManager.getCollateralTokens()[0], newCollateralToken);
        (uint256 _ltvWeETH, uint256 _liquidationThresholdWeETH) = debtManager
            .collateralTokenConfig(address(weETH));
        assertEq(_ltvWeETH, 0);
        assertEq(_liquidationThresholdWeETH, 0);

        vm.stopPrank();
    }

    function test_OnlyAdminCanSupportOrUnsupportCollateral() public {
        address newCollateralToken = address(usdc);

        vm.startPrank(alice);
        vm.expectRevert(
            buildAccessControlRevertData(alice, debtManager.ADMIN_ROLE())
        );
        debtManager.supportCollateralToken(newCollateralToken, 1, 1);
        vm.expectRevert(
            buildAccessControlRevertData(alice, debtManager.ADMIN_ROLE())
        );
        debtManager.unsupportCollateralToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotAddCollateralTokenIfAlreadySupported() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.AlreadyCollateralToken.selector);
        debtManager.supportCollateralToken(address(weETH), 1, 1);
        vm.stopPrank();
    }

    function test_CannotAddNullAddressAsCollateralToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.supportCollateralToken(address(0), 1, 1);
        vm.stopPrank();
    }

    function test_CannotUnsupportCollateralTokenIfTotalCollateralNotZeroForTheToken()
        public
    {
        uint256 amount = 0.1 ether;
        vm.startPrank(alice);
        weETH.safeIncreaseAllowance(address(debtManager), amount);
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
        weETH.safeIncreaseAllowance(address(debtManager), amount);

        debtManager.depositCollateral(address(weETH), alice, amount);

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

    function test_CannotDepositCollateralIfTokenNotSupported() public {
        vm.expectRevert(IL2DebtManager.UnsupportedCollateralToken.selector);
        debtManager.depositCollateral(address(usdc), alice, 1);
    }

    function test_CannotDepositCollateralIfAllownaceIsInsufficient() public {
        deal(address(weETH), notOwner, 2);

        vm.startPrank(notOwner);
        weETH.forceApprove(address(debtManager), 1);

        if (!isFork(chainId))
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
        vm.startPrank(notOwner);
        weETH.safeIncreaseAllowance(address(debtManager), 1);

        if (!isFork(chainId))
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
}
