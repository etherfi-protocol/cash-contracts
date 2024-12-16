// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup, IL2DebtManager} from "../Setup.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DebtManagerDeployTest is Setup {
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

        assertEq(debtManager.getCollateralTokens().length, 2);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));
        assertEq(debtManager.getCollateralTokens()[1], address(usdc));

        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));

        (
            IL2DebtManager.TokenData[] memory borrowings,
            uint256 totalBorrowingsInUsd,
            IL2DebtManager.TokenData[] memory totalLiquidStableAmounts
        ) = debtManager.getCurrentState();

        assertEq(borrowings.length, 0);
        assertEq(totalBorrowingsInUsd, 0);
        assertEq(totalLiquidStableAmounts.length, 0);

        (
            IL2DebtManager.TokenData[] memory totalUserCollaterals,
            uint256 totalUserCollateralInUsd,
            IL2DebtManager.TokenData[] memory userBorrowings,
            uint256 totalUserBorrowings
        ) = debtManager.getUserCurrentState(address(aliceSafe));
        assertEq(totalUserCollaterals.length, 0);
        assertEq(totalUserCollateralInUsd, 0);
        
        assertEq(userBorrowings.length, 0);
        assertEq(totalUserBorrowings, 0);

        (
            IL2DebtManager.TokenData[] memory supplierBalances, 
            uint256 totalSupplierBalance
        ) = debtManager.supplierBalance(alice);
        assertEq(supplierBalances.length, 0);
        assertEq(totalSupplierBalance, 0);

        assertEq(debtManager.supplierBalance(alice, address(usdc)), 0);
        assertEq(debtManager.totalSupplies(address(usdc)), 0);

        (
            IL2DebtManager.TokenData[] memory suppliedTokenBalances, 
            uint256 totalSuppliedInUsd
        ) = debtManager.totalSupplies();
        assertEq(suppliedTokenBalances.length, 0);
        assertEq(totalSuppliedInUsd, 0);

        address unsupportedToken = makeAddr("unsupportedToken");
        vm.expectRevert(IL2DebtManager.UnsupportedCollateralToken.selector);
        debtManager.convertCollateralTokenToUsd(address(unsupportedToken), 1);
        
        vm.expectRevert(IL2DebtManager.UnsupportedCollateralToken.selector);
        debtManager.convertUsdToCollateralToken(address(unsupportedToken), 1);
    }
}
