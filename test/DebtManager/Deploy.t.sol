// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";

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

        (uint256 _ltv, uint256 _liquidationThreshold) = debtManager.collateralTokenConfig(address(weETH));
        assertEq(_ltv, ltv);
        assertEq(_liquidationThreshold, liquidationThreshold);
        assertEq(debtManager.borrowApyPerSecond(address(usdc)), borrowApyPerSecond);

        assertEq(debtManager.getCollateralTokens().length, 1);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));

        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));
    }
}
