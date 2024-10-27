// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe, UserSafeLib, SpendingLimit, SpendingLimitLib} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeCanSpendTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_CanSpendIfBalAvailable() public {
        uint256 bal = 100e6;
        deal(address(usdc), address(aliceSafe), bal);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), bal);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendFailsIfBalTooLow() public view {
        uint256 bal = usdc.balanceOf(address(aliceSafe));
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), bal + 1);
        assertEq(canSpend, false);
        assertEq(reason, "Balance too low");
    }

    function test_CanSpendIfWithdrawalIsLowerThanAmountRequested() public {
        uint256 totalBal = 1000e6;
        uint256 withdrawalBal = 900e6;
        uint256 balToTransfer = totalBal - withdrawalBal;
        deal(address(usdc), address(aliceSafe), totalBal);

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = balToTransfer;
        _requestWithdrawal(tokens, amounts, alice);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), balToTransfer);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendFailsIfWithdrawalRequestBlocksIt() public {
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
        assertEq(reason, "Tokens pending withdrawal");
    }

    function test_CanSpendFailsIfWithdrawalRequestBlocksIt2() public {
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
        assertEq(reason, "Tokens pending withdrawal");
    }

    function test_CanSpendFailsIfDailySpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(amountToSpend - 1, 1 ether);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");
    }

    function test_CanSpendFailsIfMonthlySpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(1 ether, amountToSpend - 1);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Monthly available spending limit less than amount requested");
    }

    function test_CanSpendFailsIfDailySpendingLimitIsExhausted() public {
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), defaultDailySpendingLimit - amountToSpend + 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");
    }

    function test_CanSpendFailsIfMonthlySpendingLimitIsExhausted() public {
        _updateSpendingLimit(1 ether, defaultMonthlySpendingLimit);
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), defaultMonthlySpendingLimit - amountToSpend + 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Monthly available spending limit less than amount requested");
    }

    function test_CanSpendIfSpendingLimitRenews() public {
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), defaultDailySpendingLimit - amountToSpend + 1);

        vm.warp(block.timestamp + aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendFailsIfIncomingDailySpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(amountToSpend - 1, 1 ether);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming daily available spending limit less than amount requested");
    }

    function test_CanSpendFailsIfIncomingMonthlySpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(1 ether, amountToSpend - 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming monthly available spending limit less than amount requested");
    }

    function test_CanSpendFailsIfIncomingDailySpendingLimitIsExhausted() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _updateSpendingLimit(amountToSpend - 1, 1 ether);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);
        (canSpend, reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Daily available spending limit less than amount requested");
    }

    function test_CanSpendFailsIfIncomingMonthlySpendingLimitIsExhausted() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _updateSpendingLimit(1 ether, amountToSpend - 1);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Monthly available spending limit less than amount requested");

        vm.warp(aliceSafe.applicableSpendingLimit().monthlyRenewalTimestamp + 1);
        (canSpend, reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Monthly available spending limit less than amount requested");
    }

    function test_CanSpendIfIncomingDailySpendingLimitRenews() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _updateSpendingLimit(amountToSpend, 1 ether);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), 1);

        vm.warp(aliceSafe.applicableSpendingLimit().dailyRenewalTimestamp + 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendIfIncomingMonthlySpendingLimitRenews() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _updateSpendingLimit(1 ether, amountToSpend);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), 1);

        vm.warp(aliceSafe.applicableSpendingLimit().monthlyRenewalTimestamp + 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CannotSpendIfDailyLimitIsLowerThanAmountUsed() external {
        deal(address(usdc), address(aliceSafe), 10 ether);

        uint256 amount = 100e6;
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        _updateSpendingLimit(amount - 1, 1 ether);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), 1);
        assertEq(canSpend, false);
        assertEq(reason, "Daily spending limit already exhausted");
    }

    function test_CannotSpendIfMonthlyLimitIsLowerThanAmountUsed() external {
        deal(address(usdc), address(aliceSafe), 10 ether);

        uint256 amount = 100e6;
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        _updateSpendingLimit(1 ether, amount - 1);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), 1);
        assertEq(canSpend, false);
        assertEq(reason, "Monthly spending limit already exhausted");
    }

    function test_CannotSpendIfIncomingDailyLimitIsLowerThanAmountUsed() external {
        deal(address(usdc), address(aliceSafe), 10 ether);

        uint256 amount = 100e6;
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        _updateSpendingLimit(amount - 1, 1 ether);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), 1);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming daily spending limit already exhausted");
    }

    function test_CannotSpendIfIncomingMonthlyLimitIsLowerThanAmountUsed() external {
        deal(address(usdc), address(aliceSafe), 10 ether);

        uint256 amount = 100e6;
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), amount);

        _updateSpendingLimit(1 ether, amount - 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), 1);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming monthly spending limit already exhausted");
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
}