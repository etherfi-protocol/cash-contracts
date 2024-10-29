// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureUtils} from "./SignatureUtils.sol";
import {OwnerLib} from "./OwnerLib.sol";
import {UserSafeStorage} from "../user-safe/UserSafeStorage.sol";

library UserSafeLib {
    using SignatureUtils for bytes32;

    bytes32 public constant REQUEST_WITHDRAWAL_METHOD =
        keccak256("requestWithdrawal");
    bytes32 public constant UPDATE_SPENDING_LIMIT_METHOD =
        keccak256("updateSpendingLimit");
    bytes32 public constant SET_COLLATERAL_LIMIT_METHOD =
        keccak256("setCollateralLimit");
    bytes32 public constant SET_OWNER_METHOD = keccak256("setOwner");
    bytes32 public constant RECOVERY_METHOD = keccak256("recoverUserSafe");
    bytes32 public constant SET_IS_RECOVERY_ACTIVE_METHOD =
        keccak256("setIsRecoveryActive");
    bytes32 public constant SET_USER_RECOVERY_SIGNER_METHOD =
        keccak256("setUserRecoverySigner");

    function verifySetOwnerSig(
        OwnerLib.OwnerObject memory currentOwner,
        uint256 nonce,
        bytes calldata owner,
        bytes calldata signature
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_OWNER_METHOD,
                block.chainid,
                address(this),
                nonce,
                owner
            )
        );

        msgHash.verifySig(currentOwner, signature);
    }

    function verifyUpdateSpendingLimitSig(
        OwnerLib.OwnerObject memory currentOwner,
        uint256 nonce,
        uint256 dailyLimitInUsd,
        uint256 monthlyLimitInUsd,
        bytes calldata signature
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(this),
                nonce,
                dailyLimitInUsd,
                monthlyLimitInUsd
            )
        );

        msgHash.verifySig(currentOwner, signature);
    }

    function verifySetCollateralLimitSig(
        OwnerLib.OwnerObject memory currentOwner,
        uint256 nonce,
        uint256 limitInUsd,
        bytes calldata signature
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_COLLATERAL_LIMIT_METHOD,
                block.chainid,
                address(this),
                nonce,
                limitInUsd
            )
        );

        msgHash.verifySig(currentOwner, signature);
    }

    function verifyRequestWithdrawalSig(
        OwnerLib.OwnerObject memory currentOwner,
        uint256 nonce,
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata signature
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(this),
                nonce,
                tokens,
                amounts,
                recipient
            )
        );

        msgHash.verifySig(currentOwner, signature);
    }

    function verifySetUserRecoverySigner(
        OwnerLib.OwnerObject memory currentOwner,
        uint256 nonce,
        address recoverySigner,
        bytes calldata signature
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_USER_RECOVERY_SIGNER_METHOD,
                block.chainid,
                address(this),
                nonce,
                recoverySigner
            )
        );

        msgHash.verifySig(currentOwner, signature);
    }

    function verifySetRecoverySig(
        OwnerLib.OwnerObject memory currentOwner,
        uint256 nonce,
        bool isActive,
        bytes calldata signature
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_IS_RECOVERY_ACTIVE_METHOD,
                block.chainid,
                address(this),
                nonce,
                isActive
            )
        );

        msgHash.verifySig(currentOwner, signature);
    }

    function verifyRecoverSig(
        uint256 nonce,
        UserSafeStorage.Signature[2] calldata signatures,
        OwnerLib.OwnerObject[2] memory recoveryOwners,
        bytes calldata newOwner
    ) internal view {
        bytes32 msgHash = keccak256(
            abi.encode(
                RECOVERY_METHOD,
                block.chainid,
                address(this),
                nonce,
                newOwner
            )
        );

        msgHash.verifySig(recoveryOwners[0], signatures[0].signature);

        msgHash.verifySig(recoveryOwners[1], signatures[1].signature);
    }
}
