// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, IL2DebtManager} from "./DebtManagerSetup.t.sol";

contract DebtManagerDeployTest is DebtManagerSetup {
    function test_Deploy() public view {
        assertEq(
            address(debtManager.cashDataProvider()),
            address(cashDataProvider)
        );

        assertEq(
            debtManager.hasRole(debtManager.DEFAULT_ADMIN_ROLE(), owner),
            true
        );
        assertEq(debtManager.hasRole(debtManager.ADMIN_ROLE(), owner), true);
        assertEq(
            debtManager.hasRole(debtManager.DEFAULT_ADMIN_ROLE(), notOwner),
            false
        );
        assertEq(
            debtManager.hasRole(debtManager.ADMIN_ROLE(), notOwner),
            false
        );

        IL2DebtManager.CollateralTokenConfig memory config = debtManager.collateralTokenConfig(address(weETH));
        assertEq(config.ltv, ltv);
        assertEq(config.liquidationThreshold, liquidationThreshold);
        assertEq(config.liquidationBonus, liquidationBonus);
        assertEq(debtManager.borrowApyPerSecond(address(usdc)), borrowApyPerSecond);

        assertEq(debtManager.getCollateralTokens().length, 1);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));

        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));
    }
}
