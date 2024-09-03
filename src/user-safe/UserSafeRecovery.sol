// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {OwnerLib} from "../libraries/OwnerLib.sol";
import {UserSafeLib} from "../libraries/UserSafeLib.sol";

abstract contract UserSafeRecovery is IUserSafe {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;
    using OwnerLib for bytes;
    using OwnerLib for address;
    using UserSafeLib for OwnerLib.OwnerObject;

    address private _userRecoverySigner;
    // Address of the EtherFi Recovery Signer
    address private immutable _etherFiRecoverySigner;
    // Address of the Third Party Recovery Signer
    address private immutable _thirdPartyRecoverySigner;
    // Boolean to toggle recovery mechanism on or off
    bool private _isRecoveryActive;

    constructor(
        address __etherFiRecoverySigner,
        address __thirdPartyRecoverySigner
    ) {
        if (__etherFiRecoverySigner == __thirdPartyRecoverySigner)
            revert RecoverySignersCannotBeSame();
        _etherFiRecoverySigner = __etherFiRecoverySigner;
        _thirdPartyRecoverySigner = __thirdPartyRecoverySigner;
    }

    function __UserSafeRecovery_init() internal {
        _isRecoveryActive = true;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function recoverySigners()
        external
        view
        returns (OwnerLib.OwnerObject[3] memory signers)
    {
        signers[0] = _userRecoverySigner.getOwnerObject();
        signers[1] = _etherFiRecoverySigner.getOwnerObject();
        signers[2] = _thirdPartyRecoverySigner.getOwnerObject();
    }

    /**
     * @inheritdoc IUserSafe
     */
    function isRecoveryActive() external view returns (bool) {
        return _isRecoveryActive;
    }

    function _setIsRecoveryActive(bool isActive) internal {
        _isRecoveryActive = isActive;
        emit IsRecoveryActiveSet(_isRecoveryActive);
    }

    function _setIsRecoveryActive(
        bool isActive,
        uint256 _nonce,
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

    function _setUserRecoverySigner(address _recoverySigner) internal {
        if (_recoverySigner == address(0))
            revert InvalidRecoverySignerAddress();

        emit UserRecoverySignerSet(_userRecoverySigner, _recoverySigner);
        _userRecoverySigner = _recoverySigner;
    }

    function _setUserRecoverySigner(
        address _recoverySigner,
        uint256 _nonce,
        bytes calldata signature
    ) internal {
        UserSafeLib.verifySetUserRecoverySigner(
            this.owner(),
            _nonce,
            _recoverySigner,
            signature
        );
        _setUserRecoverySigner(_recoverySigner);
    }

    function _recoverUserSafe(
        uint256 _nonce,
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

        OwnerLib.OwnerObject memory oldOwner = this.owner();
        _setOwner(newOwner);

        emit UserSafeRecovered(oldOwner, this.owner());
    }

    function _getRecoveryOwner(
        uint8 index
    ) internal view returns (OwnerLib.OwnerObject memory) {
        if (index == 0) {
            if (_userRecoverySigner == address(0))
                revert UserRecoverySignerIsUnsetCannotUseIndexZero();

            return _userRecoverySigner.getOwnerObject();
        } else if (index == 1) return _etherFiRecoverySigner.getOwnerObject();
        else if (index == 2) return _thirdPartyRecoverySigner.getOwnerObject();
        else revert InvalidSignatureIndex();
    }

    function _onlyWhenRecoveryActive() private view {
        if (!_isRecoveryActive) revert RecoveryNotActive();
    }

    function _setOwner(bytes calldata __owner) internal virtual;

    modifier onlyWhenRecoveryActive() {
        _onlyWhenRecoveryActive();
        _;
    }
}
