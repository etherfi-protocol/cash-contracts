// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerSetup, PriceProvider, MockPriceProvider} from "./DebtManagerSetup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract DebtManagerEModeTest is DebtManagerSetup {
    function test_SetEMode() external {
        if (!isFork(chainId)) return;

        vm.assertEq(aavePool.getUserEMode(address(debtManager)), 0);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.EModeCategorySetOnAave(1);
        debtManager.setEModeCategoryOnAave(1);

        vm.assertEq(aavePool.getUserEMode(address(debtManager)), 1);
    }

    function test_OnlyAdminCanSetEMode() external {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setEModeCategoryOnAave(1);
    }
}