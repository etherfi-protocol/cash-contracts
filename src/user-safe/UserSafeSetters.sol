// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeStorage, OwnerLib, ArrayDeDupTransient, UserSafeEventEmitter, UserSafeLib, SpendingLimit, SpendingLimitLib} from "./UserSafeStorage.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {UserSafeFactory} from "./UserSafeFactory.sol";

contract UserSafeSetters is UserSafeStorage {
    using OwnerLib for bytes;
    using OwnerLib for address;
    using OwnerLib for OwnerLib.OwnerObject;
    using UserSafeLib for OwnerLib.OwnerObject;
    using SpendingLimitLib for SpendingLimit;
    using SafeERC20 for IERC20;
    using ArrayDeDupTransient for address[];

    constructor(address __cashDataProvider) UserSafeStorage(__cashDataProvider) {}

    function setOwner(
        bytes calldata __owner,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        // Since owner is setting a new owner, an incoming owner does not make sense
        delete _incomingOwnerBytes;
        delete _incomingOwnerStartTime;

        owner().verifySetOwnerSig(_nonce, __owner, signature);

        // Owner should not be zero
        __owner.getOwnerObject()._ownerNotZero();
        _setOwner(__owner);
    }

    function setMode(Mode mode, bytes calldata signature) external incrementNonce currentOwner {
        owner().verifySetModeSig(_nonce, mode, signature);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSetMode(_mode, mode);
        _mode = mode;
    }


    function updateSpendingLimit(
        uint256 dailyLimitInUsd,
        uint256 monthlyLimitInUsd,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        owner().verifyUpdateSpendingLimitSig(
            _nonce,
            dailyLimitInUsd,
            monthlyLimitInUsd,
            signature
        );
        (SpendingLimit memory oldLimit, SpendingLimit memory newLimit) = _spendingLimit.updateSpendingLimit(
            dailyLimitInUsd,
            monthlyLimitInUsd,
            _cashDataProvider.delay()
        );

        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSpendingLimitChanged(oldLimit, newLimit);
    }

    function requestWithdrawal(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        if (tokens.length > 1) tokens.checkDuplicates();

        owner().verifyRequestWithdrawalSig(
            _nonce,
            tokens,
            amounts,
            recipient,
            signature
        );
        _requestWithdrawal(tokens, amounts, recipient);
    }

    function setIsRecoveryActive(
        bool isActive,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        _setIsRecoveryActive(isActive, signature);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitIsRecoveryActiveSet(isActive);
    }

    function setUserRecoverySigner(
        address userRecoverySigner,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        address _oldSigner = _setUserRecoverySigner(userRecoverySigner, signature);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitUserRecoverySignerSet(_oldSigner, userRecoverySigner);
    }

    function recoverUserSafe(
        bytes calldata newOwner,
        Signature[2] calldata signatures
    ) external onlyWhenRecoveryActive incrementNonce currentOwner {
        _recoverUserSafe(signatures, newOwner);
    }

    function _requestWithdrawal(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient
    ) internal {
        _cancelOldWithdrawal();

        uint256 len = tokens.length;
        if (len != amounts.length) revert ArrayLengthMismatch();
        uint96 finalTime = uint96(block.timestamp) + _cashDataProvider.delay();
        for (uint256 i = 0; i < len; ) {
            if (IERC20(tokens[i]).balanceOf(address(this)) < amounts[i])
                revert InsufficientBalance();

            unchecked {
                ++i;
            }
        }

        _pendingWithdrawalRequest = WithdrawalRequest({
            tokens: tokens,
            amounts: amounts,
            recipient: recipient,
            finalizeTime: finalTime
        });

        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitWithdrawalRequested(tokens, amounts, recipient, finalTime);
    }

    function _cancelOldWithdrawal() internal {
        if (_pendingWithdrawalRequest.tokens.length > 0) {
            UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitWithdrawalCancelled(
                _pendingWithdrawalRequest.tokens,
                _pendingWithdrawalRequest.amounts,
                _pendingWithdrawalRequest.recipient
            );

            delete _pendingWithdrawalRequest;
        }
    }

    function _setOwner(bytes calldata __owner) internal {
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitOwnerSet(_ownerBytes.getOwnerObject(), __owner.getOwnerObject());
        _ownerBytes = __owner;
    }

    function _setIsRecoveryActive(bool isActive) internal {
        _isRecoveryActive = isActive;
    }

    function _setIsRecoveryActive(
        bool isActive,
        bytes calldata signature
    ) internal {
        UserSafeLib.verifySetRecoverySig(
            this.owner(),
            _nonce,
            isActive,
            signature
        );
        _setIsRecoveryActive(isActive);
    }

    function _setUserRecoverySigner(address _recoverySigner) internal returns (address oldSigner) {
        oldSigner = _userRecoverySigner;
        if (_recoverySigner == address(0))
            revert InvalidRecoverySignerAddress();
        _userRecoverySigner = _recoverySigner;
    }

    function _setUserRecoverySigner(
        address _recoverySigner,
        bytes calldata signature
    ) internal returns (address) {
        UserSafeLib.verifySetUserRecoverySigner(
            this.owner(),
            _nonce,
            _recoverySigner,
            signature
        );
        return _setUserRecoverySigner(_recoverySigner);
    }

    function _recoverUserSafe(
        Signature[2] calldata signatures,
        bytes calldata newOwner
    ) internal {
        if (signatures[0].index == signatures[1].index)
            revert SignatureIndicesCannotBeSame();

        OwnerLib.OwnerObject[2] memory recoveryOwners;
        recoveryOwners[0] = _getRecoveryOwner(signatures[0].index);
        recoveryOwners[1] = _getRecoveryOwner(signatures[1].index);

        UserSafeLib.verifyRecoverSig(
            _nonce,
            signatures,
            recoveryOwners,
            newOwner
        );

        _setIncomingOwner(newOwner);
    }

    function _getRecoveryOwner(
        uint8 index
    ) internal view returns (OwnerLib.OwnerObject memory) {
        if (index == 0) {
            if (_userRecoverySigner == address(0)) revert UserRecoverySignerIsUnsetCannotUseIndexZero();
            return _userRecoverySigner.getOwnerObject();
        } else if (index == 1) return _cashDataProvider.etherFiRecoverySigner().getOwnerObject();
        else if (index == 2) return _cashDataProvider.thirdPartyRecoverySigner().getOwnerObject();
        else revert InvalidSignatureIndex();
    }

    function _setIncomingOwner(bytes calldata __owner) internal {
        _incomingOwnerStartTime = block.timestamp + _cashDataProvider.delay();
        OwnerLib.OwnerObject memory ownerObj = __owner.getOwnerObject();
        ownerObj._ownerNotZero();

        _incomingOwnerBytes = __owner;
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitIncomingOwnerSet(ownerObj, _incomingOwnerStartTime);
    }

    function _currentOwner() internal {
        if (
            _incomingOwnerStartTime != 0 &&
            block.timestamp > _incomingOwnerStartTime
        ) {
            _ownerBytes = _incomingOwnerBytes;
            delete _incomingOwnerBytes;
            delete _incomingOwnerStartTime;
        }
    }

    function _onlyWhenRecoveryActive() private view {
        if (!_isRecoveryActive) revert RecoveryNotActive();
    }

    modifier incrementNonce() {
        _nonce++;
        _;
    }

    modifier currentOwner() {
        _currentOwner();
        _;
    }

    modifier onlyWhenRecoveryActive() {
        _onlyWhenRecoveryActive();
        _;
    }
}