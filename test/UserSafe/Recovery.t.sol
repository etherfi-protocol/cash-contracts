// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";
import {ERC20, UserSafeSetup} from "./UserSafeSetup.sol";

error OwnableUnauthorizedAccount(address account);

contract UserSafeRecoveryTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    function test_IsRecoveryActive() public view {
        assertEq(aliceSafe.isRecoveryActive(), true);
    }

    function test_CanToggleRecovery() public {
        assertEq(aliceSafe.isRecoveryActive(), true);

        vm.prank(alice);
        aliceSafe.toggleRecovery();

        assertEq(aliceSafe.isRecoveryActive(), false);

        vm.prank(alice);
        aliceSafe.toggleRecovery();

        assertEq(aliceSafe.isRecoveryActive(), true);
    }

    function test_OnlyOwnerCanToggleRecovery() public {
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        aliceSafe.toggleRecovery();
    }

    function test_CanToggleRecoveryWithPermit() public {
        assertEq(aliceSafe.isRecoveryActive(), true);
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.TOGGLE_RECOVERY_METHOD(),
                address(aliceSafe),
                nonce
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        vm.prank(alice);
        aliceSafe.toggleRecoveryWithPermit(nonce, r, s, v);

        assertEq(aliceSafe.isRecoveryActive(), false);
    }

    function test_CanRecoverWithTwoAuthorizedSignatures() public {
        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        IUserSafe.FundsDetails[]
            memory fundsDetails = new IUserSafe.FundsDetails[](2);
        fundsDetails[0] = IUserSafe.FundsDetails({
            token: address(usdc),
            amount: usdcAmount
        });
        fundsDetails[1] = IUserSafe.FundsDetails({
            token: address(weETH),
            amount: weETHAmount
        });

        IUserSafe.Signature[2] memory signatures;

        for (uint8 i = 0; i < 3; ) {
            deal(address(usdc), address(aliceSafe), usdcAmount);
            deal(address(weETH), address(aliceSafe), weETHAmount);

            uint256 nonce = aliceSafe.nonce() + 1;

            bytes32 msgHash = keccak256(
                abi.encode(
                    aliceSafe.RECOVERY_METHOD(),
                    address(aliceSafe),
                    fundsDetails,
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
            emit IUserSafe.UserSafeRecovered(alice, fundsDetails);
            aliceSafe.recoverUserSafe(nonce, signatures, fundsDetails);

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
        aliceSafe.toggleRecovery();

        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount);
        deal(address(weETH), address(aliceSafe), weETHAmount);

        IUserSafe.FundsDetails[]
            memory fundsDetails = new IUserSafe.FundsDetails[](2);
        fundsDetails[0] = IUserSafe.FundsDetails({
            token: address(usdc),
            amount: usdcAmount
        });
        fundsDetails[1] = IUserSafe.FundsDetails({
            token: address(weETH),
            amount: weETHAmount
        });

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                address(aliceSafe),
                fundsDetails,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);

        vm.expectRevert(IUserSafe.RecoveryNotActive.selector);
        aliceSafe.recoverUserSafe(nonce, signatures, fundsDetails);
    }

    function test_RecoveryFailsIfSignatureIndicesAreSame() public {
        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount);
        deal(address(weETH), address(aliceSafe), weETHAmount);

        IUserSafe.FundsDetails[]
            memory fundsDetails = new IUserSafe.FundsDetails[](2);
        fundsDetails[0] = IUserSafe.FundsDetails({
            token: address(usdc),
            amount: usdcAmount
        });
        fundsDetails[1] = IUserSafe.FundsDetails({
            token: address(weETH),
            amount: weETHAmount
        });

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                address(aliceSafe),
                fundsDetails,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 0);

        vm.expectRevert(IUserSafe.SignatureIndicesCannotBeSame.selector);
        aliceSafe.recoverUserSafe(nonce, signatures, fundsDetails);
    }

    function test_RecoveryFailsIfSignatureIsInvalid() public {
        uint256 usdcAmount = 1 ether;
        uint256 weETHAmount = 1000 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount);
        deal(address(weETH), address(aliceSafe), weETHAmount);

        IUserSafe.FundsDetails[]
            memory fundsDetails = new IUserSafe.FundsDetails[](2);
        fundsDetails[0] = IUserSafe.FundsDetails({
            token: address(usdc),
            amount: usdcAmount
        });
        fundsDetails[1] = IUserSafe.FundsDetails({
            token: address(weETH),
            amount: weETHAmount
        });

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                address(aliceSafe),
                fundsDetails,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);
        // This makes signature 0 invalid
        signatures[0].r = signatures[1].r;

        vm.expectRevert(SignatureUtils.InvalidSigner.selector);
        aliceSafe.recoverUserSafe(nonce, signatures, fundsDetails);
    }

    function test_RecoveryFailsIfFundsAreInsufficient() public {
        uint256 usdcAmount = 1 ether;

        deal(address(usdc), address(aliceSafe), usdcAmount - 1);

        IUserSafe.FundsDetails[]
            memory fundsDetails = new IUserSafe.FundsDetails[](1);
        fundsDetails[0] = IUserSafe.FundsDetails({
            token: address(usdc),
            amount: usdcAmount
        });

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                aliceSafe.RECOVERY_METHOD(),
                address(aliceSafe),
                fundsDetails,
                nonce
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        aliceSafe.recoverUserSafe(nonce, signatures, fundsDetails);
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

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            _getRecoveryOwnerPk(index2),
            msgHash.toEthSignedMessageHash()
        );

        signatures[0] = IUserSafe.Signature({
            index: index1,
            r: r1,
            s: s1,
            v: v1
        });
        signatures[1] = IUserSafe.Signature({
            index: index2,
            r: r2,
            s: s2,
            v: v2
        });
    }

    function _getRecoveryOwnerPk(uint8 index) internal view returns (uint256) {
        if (index == 0) return alicePk;
        else if (index == 1) return etherFiRecoverySignerPk;
        else if (index == 2) return thirdPartyRecoverySignerPk;
        else revert("Invalid recovery owner");
    }
}
