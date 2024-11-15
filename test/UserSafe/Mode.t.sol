// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeLib, SpendingLimit, SpendingLimitLib, IUserSafe} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeModeTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_InitialModeIsDebit() public view {
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Debit));
    }

    function test_SwitchToCreditModeIncursDelay() public {
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Debit));
        _setMode(IUserSafe.Mode.Credit, bytes4(0));

        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Debit));
        assertEq(aliceSafe.incomingCreditModeStartTime(), block.timestamp + delay);
        
        vm.warp(block.timestamp + delay);
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Debit));

        vm.warp(block.timestamp + 1);
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Credit));
    }

    function test_SwitchToDebitModeDoesNotIncursDelay() public {
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Debit));
        _setMode(IUserSafe.Mode.Credit, bytes4(0));

        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Credit));

        _setMode(IUserSafe.Mode.Debit, bytes4(0));
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Debit));
        assertEq(aliceSafe.incomingCreditModeStartTime(), 0);
    }

    function test_CannotSetTheSameMode() public {
        _setMode(IUserSafe.Mode.Debit, IUserSafe.ModeAlreadySet.selector);

        _setMode(IUserSafe.Mode.Credit, bytes4(0));
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);
        assertEq(uint8(aliceSafe.mode()), uint8(IUserSafe.Mode.Credit));
        _setMode(IUserSafe.Mode.Credit, IUserSafe.ModeAlreadySet.selector);
    }

    function _setMode(IUserSafe.Mode mode, bytes4 errorSelector) internal {
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
        if (errorSelector != bytes4(0)) vm.expectRevert(errorSelector);
        aliceSafe.setMode(mode, signature);
    }
}