// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup} from "./DebtManagerSetup.t.sol";

contract DebtManagerDeployTest is DebtManagerSetup {
    function test_Deploy() public view {
        assertEq(address(debtManager.weETH()), address(weETH));
        assertEq(address(debtManager.usdc()), address(usdc));
        assertEq(address(debtManager.etherFiCashSafe()), etherFiCashSafe);
        assertEq(address(debtManager.priceProvider()), address(priceProvider));
        assertEq(address(debtManager.aaveV3Adapter()), address(aaveV3Adapter));

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
    }
}
