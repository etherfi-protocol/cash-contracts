// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafe} from "../../src/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

error OwnableUnauthorizedAccount(address account);
event ApprovalFunds(address token, address spender, uint256 amount);

contract UserSafeApproveTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_SetApproval() public {
        uint256 amount = 1000000;
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ApprovalFunds(address(usdc), owner, amount);
        aliceSafe.approve(address(usdc), owner, amount);
    }

    function test_OnlyOwnerCanSetApproval() public {
        uint256 amount = 1000000;

        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        aliceSafe.approve(address(usdc), owner, amount);
    }

    function test_SetApprovalWithPermit() public {
        address token = address(usdc);
        address spender = notOwner;
        uint256 amount = 1000000;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.APPROVE_METHOD(),
                token,
                spender,
                amount,
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        uint256 approvalBefore = usdc.allowance(address(aliceSafe), notOwner);
        assertEq(approvalBefore, 0);

        vm.prank(notOwner);
        aliceSafe.approveWithPermit(token, spender, amount, nonce, r, s, v);

        uint256 approvalAfter = usdc.allowance(address(aliceSafe), notOwner);
        assertEq(approvalAfter, amount);
    }
}
