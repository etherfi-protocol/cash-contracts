// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {OwnerLib} from "../libraries/OwnerLib.sol";

abstract contract UserSafeRecovery is IUserSafe {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;
    using OwnerLib for bytes;
    using OwnerLib for address;

    bytes32 public constant RECOVERY_METHOD = keccak256("recoverUserSafe");
    bytes32 public constant SET_IS_RECOVERY_ACTIVE_METHOD =
        keccak256("setIsRecoveryActive");

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
        returns (OwnerLib.OwnerObject[3] memory signers)
    {
        signers[0] = this.owner();
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

    function _setIsRecoveryActiveWithPermit(
        bool isActive,
        uint256 userNonce,
        bytes calldata signature
    ) internal {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_IS_RECOVERY_ACTIVE_METHOD,
                block.chainid,
                address(this),
                isActive,
                userNonce
            )
        );

        msgHash.verifySig(this.owner(), signature);
        _setIsRecoveryActive(isActive);
    }

    function _recoverUserSafe(
        uint256 userNonce,
        Signature[2] calldata signatures,
        address[] calldata tokensToPull
    ) internal {
        bytes32 msgHash = keccak256(
            abi.encode(
                RECOVERY_METHOD,
                block.chainid,
                address(this),
                tokensToPull,
                userNonce
            )
        );

        if (signatures[0].index == signatures[1].index)
            revert SignatureIndicesCannotBeSame();

        msgHash.verifySig(
            _getRecoveryOwner(signatures[0].index),
            signatures[0].signature
        );

        msgHash.verifySig(
            _getRecoveryOwner(signatures[1].index),
            signatures[1].signature
        );

        uint256 len = tokensToPull.length;
        FundsDetails[] memory fundsDetails = new FundsDetails[](len);
        uint256 numTokens = 0;
        for (uint256 i = 0; i < len; ) {
            uint256 bal = IERC20(tokensToPull[i]).balanceOf(address(this));
            if (bal > 0) {
                fundsDetails[numTokens] = FundsDetails({
                    token: tokensToPull[i],
                    amount: bal
                });
                numTokens++;
                IERC20(tokensToPull[i]).safeTransfer(_etherFiRecoverySafe, bal);
            }

            unchecked {
                ++i;
            }
        }

        assembly {
            mstore(fundsDetails, numTokens)
        }

        emit UserSafeRecovered(this.owner(), fundsDetails);
    }

    function _getRecoveryOwner(
        uint8 index
    ) internal view returns (OwnerLib.OwnerObject memory) {
        if (index == 0) return this.owner();
        else if (index == 1) return _etherFiRecoverySigner.getOwnerObject();
        else if (index == 2) return _thirdPartyRecoverySigner.getOwnerObject();
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
