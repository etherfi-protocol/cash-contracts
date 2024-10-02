// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, IL2DebtManager} from "./DebtManagerSetup.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DebtManagerDeployTest is DebtManagerSetup {
    function test_Deploy() public {
        assertEq(
            address(debtManager.cashDataProvider()),
            address(cashDataProvider)
        );

        assertEq(
            IAccessControl(address(debtManager)).hasRole(DEFAULT_ADMIN_ROLE, owner),
            true
        );
        assertEq(IAccessControl(address(debtManager)).hasRole(ADMIN_ROLE, owner), true);
        assertEq(
            IAccessControl(address(debtManager)).hasRole(DEFAULT_ADMIN_ROLE, notOwner),
            false
        );
        assertEq(
            IAccessControl(address(debtManager)).hasRole(ADMIN_ROLE, notOwner),
            false
        );

        IL2DebtManager.CollateralTokenConfig memory config = debtManager.collateralTokenConfig(address(weETH));
        assertEq(config.ltv, ltv);
        assertEq(config.liquidationThreshold, liquidationThreshold);
        assertEq(config.liquidationBonus, liquidationBonus);
        assertEq(debtManager.borrowApyPerSecond(address(usdc)), borrowApyPerSecond);
        assertEq(debtManager.borrowTokenMinShares(address(usdc)), minShares);

        assertEq(debtManager.getCollateralTokens().length, 1);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));

        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));

        (
            IL2DebtManager.TokenData[] memory totalCollaterals,
            uint256 totalCollateralInUsd,
            IL2DebtManager.TokenData[] memory borrowings,
            uint256 totalBorrowingsInUsd,
            IL2DebtManager.TokenData[] memory totalLiquidCollateralAmounts,
            IL2DebtManager.TokenData[] memory totalLiquidStableAmounts
        ) = debtManager.getCurrentState();

        assertEq(totalCollaterals.length, 1);
        assertEq(totalCollaterals[0].token, address(weETH));
        assertEq(totalCollaterals[0].amount, 0);
        assertEq(totalCollateralInUsd, 0);
        assertEq(borrowings.length, 1);
        assertEq(borrowings[0].token, address(usdc));
        assertEq(borrowings[0].amount, 0);
        assertEq(totalBorrowingsInUsd, 0);
        assertEq(totalLiquidCollateralAmounts.length, 1);
        assertEq(totalLiquidCollateralAmounts[0].token, address(weETH));
        assertEq(totalLiquidCollateralAmounts[0].amount, 0);
        assertEq(totalLiquidStableAmounts.length, 1);
        assertEq(totalLiquidStableAmounts[0].token, address(usdc));
        assertEq(totalLiquidStableAmounts[0].amount, 0);

        (
            IL2DebtManager.TokenData[] memory totalUserCollaterals,
            uint256 totalUserCollateralInUsd,
            IL2DebtManager.TokenData[] memory userBorrowings,
            uint256 totalUserBorrowings
        ) = debtManager.getUserCurrentState(alice);
        assertEq(totalUserCollaterals.length, 1);
        assertEq(totalUserCollaterals[0].token, address(weETH));
        assertEq(totalUserCollaterals[0].amount, 0);
        assertEq(totalUserCollateralInUsd, 0);
        
        assertEq(userBorrowings.length, 1);
        assertEq(userBorrowings[0].token, address(usdc));
        assertEq(userBorrowings[0].amount, 0);
        assertEq(totalUserBorrowings, 0);

        (
            IL2DebtManager.TokenData[] memory supplierBalances, 
            uint256 totalSupplierBalance
        ) = debtManager.supplierBalance(alice);
        assertEq(supplierBalances.length, 1);
        assertEq(supplierBalances[0].token, address(usdc));
        assertEq(supplierBalances[0].amount, 0);
        assertEq(totalSupplierBalance, 0);

        assertEq(debtManager.supplierBalance(alice, address(usdc)), 0);
        assertEq(debtManager.totalSupplies(address(usdc)), 0);

        (
            IL2DebtManager.TokenData[] memory suppliedTokenBalances, 
            uint256 totalSuppliedInUsd
        ) = debtManager.totalSupplies();
        assertEq(suppliedTokenBalances.length, 1);
        assertEq(suppliedTokenBalances[0].token, address(usdc));
        assertEq(suppliedTokenBalances[0].amount, 0);
        assertEq(totalSuppliedInUsd, 0);

        vm.expectRevert(IL2DebtManager.UnsupportedCollateralToken.selector);
        debtManager.convertCollateralTokenToUsd(address(usdc), 1);
        
        vm.expectRevert(IL2DebtManager.UnsupportedCollateralToken.selector);
        debtManager.convertUsdToCollateralToken(address(usdc), 1);
    }
}