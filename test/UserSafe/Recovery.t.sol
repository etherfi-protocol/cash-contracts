// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP1271SignatureUtils} from "../../src/libraries/EIP1271SignatureUtils.sol";
import {ERC20, UserSafeSetup} from "./UserSafeSetup.t.sol";
import {OwnerLib} from "../../src/libraries/OwnerLib.sol";

contract UserSafeRecoveryTest is UserSafeSetup {
    using MessageHashUtils for bytes32;
    using OwnerLib for address;

    address userRecoverySigner;
    uint256 userRecoverySignerPk;

    function setUp() public override {
        super.setUp();
        (userRecoverySigner, userRecoverySignerPk) = makeAddrAndKey(
            "userRecoverySigner"
        );
    }

    function test_IsRecoveryActive() public view {
        assertEq(aliceSafe.isRecoveryActive(), true);
    }

    function test_CanSetIsRecoveryActive() public {
        assertEq(aliceSafe.isRecoveryActive(), true);
        uint256 nonce = aliceSafe.nonce() + 1;
        bool setValue = false;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_IS_RECOVERY_ACTIVE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                setValue
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        aliceSafe.setIsRecoveryActive(setValue, signature);

        assertEq(aliceSafe.isRecoveryActive(), setValue);
    }

    function test_CanRecoverWithTwoAuthorizedSignatures() public {
        _setUserRecoverySigner(userRecoverySigner, bytes4(0));

        (address newOwner, uint256 newOwnerPk) = makeAddrAndKey("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);
        IUserSafe.Signature[2] memory signatures;

        for (uint8 i = 0; i < 3; ) {
            if (i > 0) {
                _setOwner(newOwnerPk, abi.encode(alice));
            }

            uint256 nonce = aliceSafe.nonce() + 1;

            bytes32 msgHash = keccak256(
                abi.encode(
                    UserSafeLib.RECOVERY_METHOD,
                    block.chainid,
                    address(aliceSafe),
                    nonce,
                    newOwnerBytes
                )
            );

            signatures = _signRecovery(msgHash, i, (i + 1) % 3);

            assertEq(aliceSafe.owner().ethAddr, alice);
            assertEq(aliceSafe.owner().x, 0);
            assertEq(aliceSafe.owner().y, 0);

            vm.expectEmit();
            emit UserSafeEventEmitter.IncomingOwnerSet(
                address(aliceSafe),
                newOwner.getOwnerObject(),
                block.timestamp + delay
            );
            aliceSafe.recoverUserSafe(newOwnerBytes, signatures);

            vm.warp(block.timestamp + delay + 1);
            assertEq(aliceSafe.owner().ethAddr, newOwner);
            assertEq(aliceSafe.owner().x, 0);
            assertEq(aliceSafe.owner().y, 0);

            unchecked {
                ++i;
            }
        }
    }

    function test_CannotRecoverIfRecoveryIndexIsInvalid() public {
        _setUserRecoverySigner(userRecoverySigner, bytes4(0));
        (address newOwner, ) = makeAddrAndKey("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);
        signatures[0].index = 3;
        vm.expectRevert(IUserSafe.InvalidSignatureIndex.selector);
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);
    }

    function test_UserCanCancelRecoveryIfMaliciousRecovery() public {
        _setUserRecoverySigner(userRecoverySigner, bytes4(0));
        (address newOwner, ) = makeAddrAndKey("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);

        vm.expectEmit();
        emit UserSafeEventEmitter.IncomingOwnerSet(
            address(aliceSafe),
            newOwner.getOwnerObject(),
            block.timestamp + delay
        );
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);

        bytes memory aliceOwnerBytes = abi.encode(alice);
        nonce += 1;
        msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_OWNER_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                aliceOwnerBytes
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory setOwnerSignature = abi.encodePacked(r, s, v);
        aliceSafe.setOwner(aliceOwnerBytes, setOwnerSignature);

        vm.warp(block.timestamp + delay + 1);
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(aliceSafe.owner().x, 0);
        assertEq(aliceSafe.owner().y, 0);
    }

    function test_CannotRecoverIfRecoveryIsInactive() public {
        _setUserRecoverySigner(userRecoverySigner, bytes4(0));

        vm.prank(alice);
        _setIsRecoveryActive(false);

        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);

        vm.expectRevert(IUserSafe.RecoveryNotActive.selector);
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);
    }

    function test_RecoveryFailsIfSignatureIndicesAreSame() public {
        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 0);

        vm.expectRevert(IUserSafe.SignatureIndicesCannotBeSame.selector);
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);
    }

    function test_RecoveryFailsIfSignatureIsInvalid() public {
        _setUserRecoverySigner(userRecoverySigner, bytes4(0));

        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);
        // This makes signature 0 invalid
        signatures[0].signature = signatures[1].signature;

        vm.expectRevert(EIP1271SignatureUtils.InvalidSigner.selector);
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);
    }

    function test_RecoveryFailsIfRecoveryOwnerIsNotSetAndIndexPassedIsZero()
        public
    {
        address newOwner = makeAddr("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        IUserSafe.Signature[2] memory signatures = _signRecovery(msgHash, 0, 1);
        vm.expectRevert(
            IUserSafe.UserRecoverySignerIsUnsetCannotUseIndexZero.selector
        );
        aliceSafe.recoverUserSafe(newOwnerBytes, signatures);
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
        if (index == 0) return userRecoverySignerPk;
        else if (index == 1) return etherFiRecoverySignerPk;
        else if (index == 2) return thirdPartyRecoverySignerPk;
        else revert("Invalid recovery owner");
    }

    function _setIsRecoveryActive(bool isActive) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_IS_RECOVERY_ACTIVE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                isActive
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        aliceSafe.setIsRecoveryActive(isActive, signature);
    }

    function _setOwner(uint256 signerPk, bytes memory ownerBytes) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_OWNER_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                ownerBytes
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.setOwner(ownerBytes, signature);
    }

    function _setUserRecoverySigner(address signer, bytes4 errorSelector) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_USER_RECOVERY_SIGNER_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                signer
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);

        if (errorSelector != bytes4(0)) vm.expectRevert(errorSelector);
        aliceSafe.setUserRecoverySigner(signer, signature);
    }
}
