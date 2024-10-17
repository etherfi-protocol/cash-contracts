// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe, UserSafeLib} from "../../src/user-safe/UserSafe.sol";
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

    function test_CanSpendFailsIfSpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _updateSpendingLimit(amountToSpend - 1);
        
        vm.warp(block.timestamp + delay + 1);
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Spending limit too low");
    }

    function test_CanSpendFailsIfSpendingLimitIsExhausted() public {
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), defaultSpendingLimit - amountToSpend + 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Spending limit too low");
    }

    function test_CanSpendIfSpendingLimitRenews() public {
        deal(address(usdc), address(aliceSafe), 100 ether);
        uint256 amountToSpend = 100e6;
        
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), defaultSpendingLimit - amountToSpend + 1);

        vm.warp(block.timestamp + aliceSafe.applicableSpendingLimit().renewalTimestamp);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function test_CanSpendFailsIfIncomingSpendingLimitIsTooLow() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), amountToSpend);
        _resetSpendingLimit(3, amountToSpend - 1);
        
        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Incoming spending limit too low");
    }

    function test_CanSpendFailsIfIncomingSpendingLimitIsExhausted() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _resetSpendingLimit(3, amountToSpend - 1);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Spending limit too low");

        vm.warp(aliceSafe.applicableSpendingLimit().renewalTimestamp + 1);
        (canSpend, reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, false);
        assertEq(reason, "Spending limit too low");
    }

    function test_CanSpendIfIncomingSpendingLimitRenews() public {
        uint256 amountToSpend = 100e6;
        deal(address(usdc), address(aliceSafe), 10 ether);
        _resetSpendingLimit(3, amountToSpend);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        aliceSafe.transfer(address(usdc), 1);

        vm.warp(aliceSafe.applicableSpendingLimit().renewalTimestamp + 1);

        (bool canSpend, string memory reason) = aliceSafe.canSpend(address(usdc), amountToSpend);
        assertEq(canSpend, true);
        assertEq(reason, "");
    }

    function _updateSpendingLimit(uint256 spendingLimitInUsd) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                spendingLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.updateSpendingLimit(spendingLimitInUsd, signature);
    }

    function _resetSpendingLimit(
        uint8 spendingLimitType,
        uint256 spendingLimitInUsd
    ) internal {
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RESET_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                spendingLimitType,
                spendingLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.resetSpendingLimit(
            spendingLimitType,
            spendingLimitInUsd,
            signature
        );
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