// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeLib, SpendingLimit, SpendingLimitLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup, IUserSafe} from "../Setup.t.sol";

contract UserSafeCanSpendTest is Setup {
    using MessageHashUtils for bytes32;

    function test_CanSpendWithDebitModeIfBalAvailable() public {
        uint256 bal = 100e6;
        deal(address(usdc), address(aliceSafe), bal);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), bal);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }
    
    function test_CanSpendWithCreditModeIfBalAvailable() public {
        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        deal(address(weETH), address(aliceSafe), 1 ether);
        deal(address(usdc), address(debtManager), 100e6);
        uint256 spendingAmt = 100e6;
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), spendingAmt);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }
    
    function test_CanSpendWithDebitModeFailsIfBalTooLow() public {
        deal(address(usdc), address(aliceSafe), 1000e6);
        uint256 bal = usdc.balanceOf(address(aliceSafe));
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), bal + 1);
        assertEq(canSpend, false);
        assertEq(reason, "Insufficient balance to spend with Debit flow");
    }

    function test_CannotSpendWithCreditModeIfLiquidityAvailableInDebtManager() public {
        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        deal(address(weETH), address(aliceSafe), 1 ether);
        uint256 spendingAmt = 100e6;
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), spendingAmt);
        assertEq(canSpend, false);
        assertEq(reason, "Insufficient liquidity in debt manager to cover the loan");
    }

    function test_CanSpendWithDebitModeIfWithdrawalIsLowerThanAmountRequested() public {
        uint256 totalBal = 1000e6;
        uint256 withdrawalBal = 900e6;
        uint256 balToTransfer = totalBal - withdrawalBal;
        deal(address(usdc), address(aliceSafe), totalBal);

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = withdrawalBal;
        _requestWithdrawal(tokens, amounts, alice);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), balToTransfer);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendWithCreditModeIfAfterWithdrawalAmountIsStillBorrowable() public {
        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);
        
        deal(address(usdc), address(debtManager), 1 ether);
        uint256 totalBal = 1000e6;
        uint256 withdrawalAmt = 200e6;
        uint256 balToTransfer = 400e6; // still with 800 USDC after withdrawal we can borrow 400 USDC as ltv = 50%
        deal(address(usdc), address(aliceSafe), totalBal);

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = withdrawalAmt;
        _requestWithdrawal(tokens, amounts, alice);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), balToTransfer);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendWithDebitModeFailsIfWithdrawalRequestBlocksIt() public {
        address token = address(usdc);
        uint256 bal = 100e6;
        deal(token, address(aliceSafe), bal);

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e6;
        _requestWithdrawal(tokens, amounts, alice);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(token, bal);
        assertEq(canSpend, false);
        assertEq(reason, "Insufficient effective balance after withdrawal to spend with debit mode");
    }

    function test_CanSpendWithCreditModeFailsIfWithdrawalRequestBlocksIt() public {
        address token = address(usdc);
        uint256 bal = 100e6;
        deal(token, address(aliceSafe), bal);

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e6;
        _requestWithdrawal(tokens, amounts, alice);
        
        _setMode(IUserSafe.Mode.Credit);

        // since we have 100 USDC and 10 is in withdrawal, also incoming mode is credit
        // with 50% ltv, max borrowable is (100 - 10) * 50% = 45 USDC
        // if we want to borrow 50 USDC, it should fail

        (bool canSpend, string memory reason) = aliceSafe.canSpend(token, 50e6);
        assertEq(canSpend, false);
        assertEq(reason, "Insufficient borrowing power");
    }

    function test_CanSpendWithCreditModeFailsIfCollateralBalanceIsZero() public {
        _setMode(IUserSafe.Mode.Credit);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), 50e6);
        assertEq(canSpend, false);
        assertEq(reason, "Collateral tokens balances zero");
    }

    function test_CanSpendWithDebitModeFailsIfWithdrawalRequestBlocksIt2() public {
        address token = address(usdc);
        uint256 bal = 100e6;
        deal(token, address(aliceSafe), bal);
        deal(address(weETH), address(aliceSafe), bal);

        address[] memory tokens = new address[](2);
        tokens[0] = address(weETH);
        tokens[1] = token;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e6;
        amounts[1] = 10e6;
        _requestWithdrawal(tokens, amounts, alice);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(token, bal);
        assertEq(canSpend, false);
        assertEq(reason, "Insufficient effective balance after withdrawal to spend with debit mode");
    }

    function test_CanSpendWithDebitModeFailsIfDailySpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(amountToSpend - 1, 1 ether);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");
    }

    function test_CanSpendWithDebitModeFailsIfDailySpendingLimitIsExhausted() public {
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), defaultDailySpendingLimit - amountToSpend + 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");
    }

    function test_CanSpendWithDebitModeIfSpendingLimitRenews() public {
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), defaultDailySpendingLimit - amountToSpend + 1);

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendWithDebitModeFailsIfIncomingDailySpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(amountToSpend - 1, 1 ether);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming daily available spending limit less than amount requested");
    }

    function test_CanSpendWithDebitModeFailsIfIncomingDailySpendingLimitIsExhausted() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _updateSpendingLimit(amountToSpend - 1, 1 ether);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);
        (canSpend, reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");
    }

    function test_CanSpendWithDebitModeIfIncomingDailySpendingLimitRenews() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _updateSpendingLimit(amountToSpend, 1 ether);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), 1);

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendWithDebitModeFailsIfDailyLimitIsLowerThanAmountUsed() external {
        deal(address(usdc), address(aliceSafe), 10 ether);

        uint256 amount = 100e6;
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), amount);

        _updateSpendingLimit(amount - 1, 1 ether);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amount);
        assertEq(canSpend, false);
        assertEq(reason, "Daily spending limit already exhausted");
    }

    function test_CanSpendWithDebitModeFailsIfIncomingDailyLimitIsLowerThanAmountUsed() external {
        deal(address(usdc), address(aliceSafe), 10 ether);

        uint256 amount = 100e6;
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), amount);

        _updateSpendingLimit(amount - 1, 1 ether);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amount);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming daily spending limit already exhausted");
    }

    function _updateSpendingLimit(uint256 dailySpendingLimitInUsd, uint256 monthlySpendingLimitInUsd) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                dailySpendingLimitInUsd,
                monthlySpendingLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.updateSpendingLimit(dailySpendingLimitInUsd, monthlySpendingLimitInUsd, signature);
    }

    function _requestWithdrawal(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) internal {
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                tokens,
                amounts,
                recipient
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);
    }

    function _setMode(IUserSafe.Mode mode) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_MODE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                mode
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.setMode(mode, signature);
    }
}