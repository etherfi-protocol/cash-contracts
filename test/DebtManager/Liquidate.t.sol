// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {Setup, PriceProvider, MockPriceProvider, MockERC20} from "../Setup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract DebtManagerLiquidateTest is Setup {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    uint256 collateralAmount = 0.01 ether;
    uint256 collateralValueInUsdc;
    uint256 borrowAmt;

    function setUp() public override {
        super.setUp();

        collateralValueInUsdc = debtManager.convertCollateralTokenToUsd(
            address(weETH),
            collateralAmount
        );

        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_MODE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                IUserSafe.Mode.Credit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.setMode(IUserSafe.Mode.Credit, signature);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        deal(address(usdc), owner, 1 ether);
        deal(address(weETH), address(aliceSafe), collateralAmount);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);
        borrowAmt = debtManager.remainingBorrowingCapacityInUSD(address(aliceSafe));

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);
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

        IL2DebtManager.CollateralTokenConfig memory configFromContract = debtManager.collateralTokenConfig(address(weETH));
        assertEq(configFromContract.liquidationThreshold, newThreshold);
    }

    function test_OnlyAdminCanSetLiquidationThreshold() public {
        uint80 newThreshold = 70e18;
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig = debtManager.collateralTokenConfig(address(weETH));
        collateralTokenConfig.liquidationThreshold = newThreshold;

        vm.startPrank(notOwner);
        vm.expectRevert(
            buildAccessControlRevertData(notOwner, ADMIN_ROLE)
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
        assertEq(debtManager.liquidatable(address(aliceSafe)), true);

        address[] memory collateralTokenPreference = debtManager.getCollateralTokens();

        IERC20(address(usdc)).forceApprove(address(debtManager), borrowAmt);
        debtManager.liquidate(address(aliceSafe), address(usdc), collateralTokenPreference);

        vm.stopPrank();

        uint256 aliceSafeCollateralAfter = debtManager.getCollateralValueInUsd(address(aliceSafe));
        uint256 aliceSafeDebtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        uint256 liquidatorWeEthBalAfter = weETH.balanceOf(owner);

        uint256 liquidatedUsdcCollateralAmt = debtManager.convertUsdToCollateralToken(address(weETH), borrowAmt);
        uint256 liquidationBonusReceived =  (
            liquidatedUsdcCollateralAmt * collateralTokenConfig.liquidationBonus
        ) / HUNDRED_PERCENT;
        uint256 liquidationBonusInUsdc = debtManager.convertCollateralTokenToUsd(address(weETH), liquidationBonusReceived);

        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsd(
                address(weETH),
                liquidatorWeEthBalAfter - liquidatorWeEthBalBefore - liquidationBonusReceived
            ),
            borrowAmt,
            10
        );
        assertApproxEqAbs(aliceSafeCollateralAfter, collateralValueInUsdc - borrowAmt - liquidationBonusInUsdc, 1);
        assertEq(aliceSafeDebtAfter, 0);
    }

    function test_CannotLiquidateIfNotLiquidatable() public {
        vm.startPrank(owner);
        assertEq(debtManager.liquidatable(address(aliceSafe)), false);
        IERC20(address(usdc)).forceApprove(address(debtManager), borrowAmt);

        address[] memory collateralTokens = debtManager.getCollateralTokens();
        vm.expectRevert(IL2DebtManager.CannotLiquidateYet.selector);
        debtManager.liquidate(address(aliceSafe), address(usdc), collateralTokens);

        vm.stopPrank();
    }

    function test_LiquidatorIsChargedRightAmountOfBorrowTokens() public {
        deal(address(usdc), address(aliceSafe), borrowAmt);
        vm.prank(etherFiWallet);
        aliceSafe.repay(address(usdc), borrowAmt);

        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd, address(usdc)))
        );
        vm.prank(owner);
        cashDataProvider.setPriceProvider(address(priceProvider));

        borrowAmt = debtManager.remainingBorrowingCapacityInUSD(address(aliceSafe));
        // aliceSafe should borrow at new price for our calculations to be correct
        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);

        vm.startPrank(owner);
        uint256 newPrice = 1000e6; // 1000 USD per weETH
        MockPriceProvider(address(priceProvider)).setPrice(newPrice);
        
        // Lower the thresholds for weETH as well
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigWeETH;
        collateralTokenConfigWeETH.ltv = 5e18;
        collateralTokenConfigWeETH.liquidationThreshold = 10e18;
        collateralTokenConfigWeETH.liquidationBonus = 5e18;
        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfigWeETH);

        // Now price of collateral token is 1000 USD per weETH
        // total collateral = 0.01 weETH => 10 USD
        // total debt = based on price 3000 USD per weETH and 50% LTV -> 15 USD
        // So total collateral < total debt
        // Also the user is liquidatable since liquidation threshold is 10% 
        
        // Debt is 15 USD 
        // total collateral -> 0.01 WETH = 10 USD
        // total bonus -> 0.01 * 5% = 0.0005 weETH -> 0.5 USD
        // weETH amt -> 15 / 1000 = 0.015 weETH
        // bonus -> 5% -> 0.015 * 5% = 0.00075 weETH
        // total debt liquidated -> 10 - 0.5 USD -> 9.5 USD
        // total collateral gone -> 0.01 weETH

        uint256 liquidationAmt = 9.5 * 1e6;

        address[] memory collateralTokenPreference = new address[](1);
        collateralTokenPreference[0] = address(weETH);

        uint256 ownerWeETHBalBefore = weETH.balanceOf(owner);
        uint256 ownerUsdcBalBefore = IERC20(address(usdc)).balanceOf(owner);
        uint256 aliceSafeDebtBefore = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        uint256 aliceSafeCollateralBefore = debtManager.getCollateralValueInUsd(address(aliceSafe));

        IERC20(address(usdc)).forceApprove(address(debtManager), liquidationAmt);
        debtManager.liquidate(address(aliceSafe), address(usdc), collateralTokenPreference);

        uint256 ownerWeETHBalAfter = weETH.balanceOf(owner);
        uint256 ownerUsdcBalAfter = IERC20(address(usdc)).balanceOf(owner);
        uint256 aliceSafeDebtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        uint256 aliceSafeCollateralAfter = debtManager.getCollateralValueInUsd(address(aliceSafe));

        assertEq(ownerWeETHBalAfter - ownerWeETHBalBefore, collateralAmount);
        assertEq(ownerUsdcBalBefore - ownerUsdcBalAfter, liquidationAmt);
        assertEq(aliceSafeDebtBefore, borrowAmt);
        assertEq(aliceSafeDebtAfter, borrowAmt - liquidationAmt);
        assertEq(aliceSafeCollateralBefore, 10e6); // price dropped to 1000 USD and 0.01 weETH was collateral
        assertEq(aliceSafeCollateralAfter, 0);

        vm.stopPrank();
    }

    function test_ChooseCollateralPreferenceWhenLiquidating() public {
        deal(address(usdc), address(aliceSafe), borrowAmt);
        vm.prank(etherFiWallet);
        aliceSafe.repay(address(usdc), borrowAmt);
                
        priceProvider = PriceProvider(
            address(new MockPriceProvider(mockWeETHPriceInUsd, address(usdc)))
        );
        vm.prank(owner);
        cashDataProvider.setPriceProvider(address(priceProvider));

        borrowAmt = debtManager.remainingBorrowingCapacityInUSD(address(aliceSafe));
        // Alice should borrow at new price for our calculations to be correct
        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);
        
        address newCollateralToken = address(new MockERC20("collateral", "CTK", 18));
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigNewCollateralToken;
        collateralTokenConfigNewCollateralToken.ltv = 5e18;
        collateralTokenConfigNewCollateralToken.liquidationThreshold = 10e18;
        collateralTokenConfigNewCollateralToken.liquidationBonus = 10e18;

        vm.startPrank(owner);
        debtManager.supportCollateralToken(
            newCollateralToken,
            collateralTokenConfigNewCollateralToken
        );

        uint256 collateralAmtNewToken = 0.003 ether;
        deal(newCollateralToken, address(aliceSafe), collateralAmtNewToken);

        // Lower the thresholds for weETH as well
        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfigWeETH;
        collateralTokenConfigWeETH.ltv = 5e18;
        collateralTokenConfigWeETH.liquidationThreshold = 10e18;
        collateralTokenConfigWeETH.liquidationBonus = 5e18;
        debtManager.setCollateralTokenConfig(address(weETH), collateralTokenConfigWeETH);

        address[] memory collateralTokenPreference = new address[](2);
        collateralTokenPreference[0] = newCollateralToken;
        collateralTokenPreference[1] = address(weETH);

        assertEq(debtManager.liquidatable(address(aliceSafe)), true);

        // currently, alice collateral -> 
        // 0.01 weETH + 0.003 newToken  => 30 + 9 = 39 USDC (since 3000 is the default price in mock price provider)
        // alice debt -> 30 * 50% = 15 USD (initial collateral 30 USD, LTV: 50%)
        // When we liquidate -> user should receive the following:
        
        // for a debt of 15 USD ->

        // new token
        // total collateral in new token -> 0.003 * 3000 = 9 USDC
        // total bonus = 0.003 * 10% = 0.0003 -> 0.9 USDC
        // total debt liquidated = 9 - 0.9 = 8.1 USDC
                
        // weETH 
        // total collateral in weETH -> 0.01 * 3000 = 30 USDC
        // total debt left = 15 - 8.1 = 6.9 USDC
        // total collateral worth 6.9 USDC in weETH -> 6.9 / 3000 -> 0.0023
        // total bonus on 0.0023 weETH => 0.0023 * 5% = 0.000115

        // In total
        // borrow wiped by new token -> 8.1 USDC
        // borrow wiped by weETH -> 6.9 USDC
        // total liquidation bonus new token -> 0.0003
        // total liquidation bonus weETH -> 0.000115

        uint256 ownerWeETHBalBefore = weETH.balanceOf(owner);
        uint256 ownerNewTokenBalBefore = IERC20(newCollateralToken).balanceOf(owner);
        uint256 aliceSafeDebtBefore = debtManager.borrowingOf(address(aliceSafe), address(usdc));

        IERC20(address(usdc)).forceApprove(address(debtManager), borrowAmt);
        debtManager.liquidate(address(aliceSafe), address(usdc), collateralTokenPreference);

        vm.stopPrank();

        _validate(newCollateralToken, ownerNewTokenBalBefore, ownerWeETHBalBefore, aliceSafeDebtBefore);
    }

    function _validate(
        address newCollateralToken,
        uint256 ownerNewTokenBalBefore,
        uint256 ownerWeETHBalBefore,
        uint256 aliceDebtBefore
    ) internal view {
        uint256 ownerWeETHBalAfter = weETH.balanceOf(owner);
        uint256 ownerNewTokenBalAfter = IERC20(newCollateralToken).balanceOf(owner);
        uint256 aliceSafeDebtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));

        uint256 borrowWipedByNewToken =  8.1 * 1e6;
        uint256 borrowWipedByWeETH = 6.9 * 1e6;
        uint256 liquidationBonusNewToken =  0.0003 ether;
        uint256 liquidationBonusWeETH = 0.000115 ether;

        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsd(
                address(newCollateralToken),
                ownerNewTokenBalAfter - ownerNewTokenBalBefore - liquidationBonusNewToken
            ),
            borrowWipedByNewToken,
            10
        );
        
        assertApproxEqAbs(
            debtManager.convertCollateralTokenToUsd(
                address(weETH),
                ownerWeETHBalAfter - ownerWeETHBalBefore - liquidationBonusWeETH
            ),
            borrowWipedByWeETH,
            10
        );

        assertEq(aliceDebtBefore, borrowAmt);
        assertEq(aliceSafeDebtAfter, 0);
    }
}
