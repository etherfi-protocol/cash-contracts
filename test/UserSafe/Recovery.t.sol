// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP1271SignatureUtils} from "../../src/libraries/EIP1271SignatureUtils.sol";
import {ERC20, UserSafeSetup} from "./UserSafeSetup.sol";
import {OwnerLib} from "../../src/libraries/OwnerLib.sol";

contract UserSafeRecoveryTest is UserSafeSetup {
    using MessageHashUtils for bytes32;
    using OwnerLib for address;

    function test_IsRecoveryActive() public view {
        assertEq(aliceSafe.isRecoveryActive(), true);
    }

    function test_CanSetIsRecoveryActive() public {
        assertEq(aliceSafe.isRecoveryActive(), true);

        vm.prank(alice);
        aliceSafe.setIsRecoveryActive(false);

        assertEq(aliceSafe.isRecoveryActive(), false);

        vm.prank(alice);
        aliceSafe.setIsRecoveryActive(true);

        assertEq(aliceSafe.isRecoveryActive(), true);
    }

    function test_OnlyOwnerCanSetIsRecoveryActive() public {
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnerLib.OnlyOwner.selector));
        aliceSafe.setIsRecoveryActive(false);
    }

    function test_CanSetIsRecoveryActiveWithPermit() public {
        assertEq(aliceSafe.isRecoveryActive(), true);
        uint256 nonce = aliceSafe.nonce() + 1;
        bool setValue = false;
        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.SET_IS_RECOVERY_ACTIVE_METHOD(),
                block.chainid,
                address(aliceSafe),
                setValue,
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        aliceSafe.setIsRecoveryActiveWithPermit(setValue, nonce, signature);

        assertEq(aliceSafe.isRecoveryActive(), setValue);
    }

    function test_CanRecoverWithTwoAuthorizedSignatures() public {
        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        address[] memory tokensToPull = new address[](2);
        IUserSafe.FundsDetails[]
            memory fundsDetails = new IUserSafe.FundsDetails[](2);
        fundsDetails[0] = IUserSafe.FundsDetails({
            token: address(usdc),
            amount: usdcAmount
        });
        tokensToPull[0] = fundsDetails[0].token;

        fundsDetails[1] = IUserSafe.FundsDetails({
            token: address(weETH),
            amount: weETHAmount
        });
        tokensToPull[1] = fundsDetails[1].token;

        IUserSafe.Signature[2] memory signatures;

        for (uint8 i = 0; i < 3; ) {
            deal(address(usdc), address(aliceSafe), usdcAmount);
            deal(address(weETH), address(aliceSafe), weETHAmount);

            uint256 nonce = aliceSafe.nonce() + 1;

            bytes32 msgHash = keccak256(
                abi.encode(
                    aliceSafe.RECOVERY_METHOD(),
                    block.chainid,
                    address(aliceSafe),
                    tokensToPull,
                    nonce
                )
            );

            signatures = _signRecovery(msgHash, i, (i + 1) % 3);

            uint256 usdcEtherFiRecoverySafeBalBefore = usdc.balanceOf(
                etherFiRecoverySafe
            );
            uint256 weEthEtherFiRecoverySafeBalBefore = weETH.balanceOf(
                etherFiRecoverySafe
            );
            uint256 usdcAliceSafeBalBefore = usdc.balanceOf(address(aliceSafe));
            uint256 weEthAliceSafeBalBefore = weETH.balanceOf(
                address(aliceSafe)
            );

            vm.expectEmit();
            emit IUserSafe.UserSafeRecovered(
                alice.getOwnerObject(),
                fundsDetails
            );
            aliceSafe.recoverUserSafe(nonce, signatures, tokensToPull);

            assertEq(
                usdc.balanceOf(etherFiRecoverySafe) -
                    usdcEtherFiRecoverySafeBalBefore,
                usdcAmount
            );
            assertEq(
                weETH.balanceOf(etherFiRecoverySafe) -
                    weEthEtherFiRecoverySafeBalBefore,
                weETHAmount
            );
            assertEq(
                usdcAliceSafeBalBefore - usdc.balanceOf(address(aliceSafe)),
                usdcAmount
            );
            assertEq(
                weEthAliceSafeBalBefore - weETH.balanceOf(address(aliceSafe)),
                weETHAmount
            );

            unchecked {
                ++i;
            }
        }
    }

    function test_CannotRecoverIfRecoveryIsInactive() public {
        vm.prank(alice);
        aliceSafe.setIsRecoveryActive(false);

        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount);
        deal(address(weETH), address(aliceSafe), weETHAmount);

        address[] memory tokensToPull = new address[](2);

        tokensToPull[0] = address(usdc);
        tokensToPull[1] = address(weETH);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                block.chainid,
                address(aliceSafe),
                tokensToPull,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);

        vm.expectRevert(IUserSafe.RecoveryNotActive.selector);
        aliceSafe.recoverUserSafe(nonce, signatures, tokensToPull);
    }

    function test_RecoveryFailsIfSignatureIndicesAreSame() public {
        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount);
        deal(address(weETH), address(aliceSafe), weETHAmount);

        address[] memory tokensToPull = new address[](2);

        tokensToPull[0] = address(usdc);
        tokensToPull[1] = address(weETH);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                block.chainid,
                address(aliceSafe),
                tokensToPull,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 0);

        vm.expectRevert(IUserSafe.SignatureIndicesCannotBeSame.selector);
        aliceSafe.recoverUserSafe(nonce, signatures, tokensToPull);
    }

    function test_RecoveryFailsIfSignatureIsInvalid() public {
        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount);
        deal(address(weETH), address(aliceSafe), weETHAmount);

        address[] memory tokensToPull = new address[](2);

        tokensToPull[0] = address(usdc);
        tokensToPull[1] = address(weETH);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                block.chainid,
                address(aliceSafe),
                tokensToPull,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);
        // This makes signature 0 invalid
        signatures[0].signature = signatures[1].signature;

        vm.expectRevert(EIP1271SignatureUtils.InvalidSigner.selector);
        aliceSafe.recoverUserSafe(nonce, signatures, tokensToPull);
    }

    function _signRecovery(
        bytes32 msgHash,
        uint8 index1,
        uint8 index2
    ) internal view returns (IUserSafe.Signature[2] memory signatures) {
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(
            _getRecoveryOwnerPk(index1),
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            _getRecoveryOwnerPk(index2),
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        signatures[0] = IUserSafe.Signature({
            index: index1,
            signature: signature1
        });
        signatures[1] = IUserSafe.Signature({
            index: index2,
            signature: signature2
        });
    }

    function _getRecoveryOwnerPk(uint8 index) internal view returns (uint256) {
        if (index == 0) return alicePk;
        else if (index == 1) return etherFiRecoverySignerPk;
        else if (index == 2) return thirdPartyRecoverySignerPk;
        else revert("Invalid recovery owner");
    }
}
