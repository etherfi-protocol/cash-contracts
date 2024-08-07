// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";

abstract contract UserSafeRecovery is IUserSafe {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;

    bytes32 public constant RECOVERY_METHOD = keccak256("recoverUserSafe");
    bytes32 public constant TOGGLE_RECOVERY_METHOD =
        keccak256("toggleRecovery");

    // Address of the EtherFi Recovery safe
    address private immutable _etherFiRecoverySafe;
    // Address of the EtherFi Recovery Signer
    address private immutable _etherFiRecoverySigner;
    // Address of the Third Party Recovery Signer
    address private immutable _thirdPartyRecoverySigner;
    // Boolean to toggle recovery mechanism on or off
    bool private _isRecoveryActive;

    constructor(
        address __cashDataProvider,
        address __etherFiRecoverySigner,
        address __thirdPartyRecoverySigner
    ) {
        _etherFiRecoverySafe = ICashDataProvider(__cashDataProvider)
            .etherFiRecoverySafe();

        _etherFiRecoverySigner = __etherFiRecoverySigner;
        _thirdPartyRecoverySigner = __thirdPartyRecoverySigner;
    }

    function __UserSafeRecovery_init() internal {
        _isRecoveryActive = true;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function etherFiRecoverySafe() external view returns (address) {
        return _etherFiRecoverySafe;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function recoverySigners()
        external
        view
        returns (address[3] memory signers)
    {
        signers[0] = this.owner();
        signers[1] = _etherFiRecoverySigner;
        signers[2] = _thirdPartyRecoverySigner;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function isRecoveryActive() external view returns (bool) {
        return _isRecoveryActive;
    }

    function _toggleRecovery() internal {
        _isRecoveryActive = !_isRecoveryActive;
        emit ToggleRecovery(_isRecoveryActive);
    }

    function _toggleRecoveryWithPermit(
        uint256 userNonce,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal {
        bytes32 msgHash = keccak256(
            abi.encode(TOGGLE_RECOVERY_METHOD, address(this), userNonce)
        );

        msgHash.verifySig(this.owner(), r, s, v);
        _toggleRecovery();
    }

    function _recoverUserSafe(
        uint256 userNonce,
        Signature[2] memory signatures,
        FundsDetails[] memory fundsDetails
    ) internal {
        bytes32 msgHash = keccak256(
            abi.encode(RECOVERY_METHOD, address(this), fundsDetails, userNonce)
        );

        if (signatures[0].index == signatures[1].index)
            revert SignatureIndicesCannotBeSame();

        msgHash.verifySig(
            _getRecoveryOwner(signatures[0].index),
            signatures[0].r,
            signatures[0].s,
            signatures[0].v
        );

        msgHash.verifySig(
            _getRecoveryOwner(signatures[1].index),
            signatures[1].r,
            signatures[1].s,
            signatures[1].v
        );

        uint256 len = fundsDetails.length;
        for (uint256 i = 0; i < len; ) {
            IERC20(fundsDetails[i].token).safeTransfer(
                _etherFiRecoverySafe,
                fundsDetails[i].amount
            );

            unchecked {
                ++i;
            }
        }

        emit UserSafeRecovered(this.owner(), fundsDetails);
    }

    function _getRecoveryOwner(uint8 index) internal view returns (address) {
        if (index == 0) return this.owner();
        else if (index == 1) return _etherFiRecoverySigner;
        else if (index == 2) return _thirdPartyRecoverySigner;
        else revert InvalidSignatureIndex();
    }

    function _onlyWhenRecoveryActive() private view {
        if (!_isRecoveryActive) revert RecoveryNotActive();
    }

    modifier onlyWhenRecoveryActive() {
        _onlyWhenRecoveryActive();
        _;
    }
}
