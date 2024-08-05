// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafe} from "../../src/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

event DepositFunds(address token, uint256 amount);
// keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
bytes32 constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

struct Permit {
    address owner;
    address spender;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
}

contract UserSafeReceiveFundsTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_ReceiveFunds() public {
        uint256 amount = 1000e6;
        vm.startPrank(alice);
        usdc.approve(address(aliceSafe), amount);
        vm.expectEmit(true, true, true, true);
        emit DepositFunds(address(usdc), amount);
        aliceSafe.receiveFunds(address(usdc), amount);
        vm.stopPrank();
    }

    function test_ReceiveFundsWithPermit() public {
        uint256 amount = 10 ether;
        uint256 deadline = type(uint256).max;
        bytes32 DOMAIN_SEPARATOR_WEETH = 0x2dcc2f01a01098023cfce9f6b30f72af3d7809ae69a1ea8b5ac6f012e91b3248;

        Permit memory permit = Permit({
            owner: alice,
            spender: address(aliceSafe),
            value: amount,
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = getTypedDataHash(DOMAIN_SEPARATOR_WEETH, permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        vm.prank(notOwner);
        vm.expectEmit(true, true, true, true);
        emit DepositFunds(address(weETH), amount);
        aliceSafe.receiveFundsWithPermit(
            alice,
            address(weETH),
            amount,
            deadline,
            r,
            s,
            v
        );
        vm.stopPrank();
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(
        bytes32 DOMAIN_SEPARATOR,
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_permit)
                )
            );
    }

    // computes the hash of a permit
    function getStructHash(
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }
}
