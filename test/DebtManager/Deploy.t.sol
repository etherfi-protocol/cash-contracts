// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, IL2DebtManager} from "./DebtManagerSetup.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DebtManagerDeployTest is DebtManagerSetup {
    function test_Deploy() public view {
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

        assertEq(debtManager.getCollateralTokens().length, 1);
        assertEq(debtManager.getCollateralTokens()[0], address(weETH));

        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));

        IL2DebtManager.BorrowTokenConfig memory borrowTokenConfig = debtManager.borrowTokenConfig(address(usdc));
        assertEq(borrowTokenConfig.interestIndexSnapshot, 0);
        assertEq(borrowTokenConfig.totalBorrowingAmount, 0);
        assertEq(borrowTokenConfig.totalSharesOfBorrowTokens, 0);
        assertEq(borrowTokenConfig.lastUpdateTimestamp, block.timestamp);
        assertEq(borrowTokenConfig.borrowApy, borrowApyPerSecond);
        assertEq(borrowTokenConfig.minShares, minShares);
        assertEq(debtManager.totalBorrowingAmount(address(usdc)), 0);
        
        (, uint256 totalBorrowings) = debtManager.totalBorrowingAmounts();
        assertEq(totalBorrowings, 0);

        (, uint256 totalCollateral) = debtManager.totalCollateralAmounts();
        assertEq(totalCollateral, 0);
    }
}
