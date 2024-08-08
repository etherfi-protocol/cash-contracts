// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

contract UserSafeApproveTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_SetApproval() public {
        uint256 amount = 1000000;
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IUserSafe.ApprovalFunds(address(usdc), owner, amount);
        aliceSafe.approve(address(usdc), owner, amount);
    }

    function test_OnlyOwnerCanSetApproval() public {
        uint256 amount = 1000000;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerLib.OnlyOwner.selector));
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
                block.chainid,
                address(aliceSafe),
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

        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 approvalBefore = usdc.allowance(address(aliceSafe), notOwner);
        assertEq(approvalBefore, 0);

        vm.prank(notOwner);
        aliceSafe.approveWithPermit(token, spender, amount, nonce, signature);

        uint256 approvalAfter = usdc.allowance(address(aliceSafe), notOwner);
        assertEq(approvalAfter, amount);
    }
}
