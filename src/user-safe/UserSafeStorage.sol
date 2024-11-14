// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IL2DebtManager} from "../interfaces/IL2DebtManager.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {WebAuthn} from "../libraries/WebAuthn.sol";
import {OwnerLib} from "../libraries/OwnerLib.sol";
import {UserSafeLib} from "../libraries/UserSafeLib.sol";
import {ReentrancyGuardTransientUpgradeable} from "../utils/ReentrancyGuardTransientUpgradeable.sol";
import {ArrayDeDupTransient} from "../libraries/ArrayDeDupTransientLib.sol";
import {SpendingLimit, SpendingLimitLib} from "../libraries/SpendingLimitLib.sol";
import {UserSafeEventEmitter} from "./UserSafeEventEmitter.sol";

contract UserSafeStorage is Initializable, ReentrancyGuardTransientUpgradeable {
    using OwnerLib for bytes;

    enum Mode {
        Debit,
        Credit
    }
    
    struct Signature {
        uint8 index;
        bytes signature;
    }

    struct FundsDetails {
        address token;
        uint256 amount;
    }

    struct WithdrawalRequest {
        address[] tokens;
        uint256[] amounts;
        address recipient;
        uint96 finalizeTime;
    }

    error InsufficientBalance();
    error ArrayLengthMismatch();
    error CannotWithdrawYet();
    error UnauthorizedCall();
    error InvalidNonce();
    error TransferAmountGreaterThanReceived();
    error UnsupportedToken();
    error RecoveryNotActive();
    error InvalidSignatureIndex();
    error SignatureIndicesCannotBeSame();
    error AmountCannotBeZero();
    error RecoverySignersCannotBeSame();
    error InvalidRecoverySignerAddress();
    error UserRecoverySignerIsUnsetCannotUseIndexZero();
    error IncorrectOutputAmount();
    error AmountZeroWithSixDecimals();
    error OnlyUserSafeFactory();

    // Address of the Cash Data Provider
    ICashDataProvider internal immutable _cashDataProvider;
    // Address of the recovery signer set by the user
    address internal _userRecoverySigner;

    // Owner: if ethAddr -> abi.encode(owner), if passkey -> abi.encode(x,y)
    bytes internal _ownerBytes;
    // Owner: if ethAddr -> abi.encode(owner), if passkey -> abi.encode(x,y)
    bytes internal _incomingOwnerBytes;
    // Time when the incoming owner becomes the owner
    uint256 internal _incomingOwnerStartTime;

    // Withdrawal requests pending with the contract
    WithdrawalRequest internal _pendingWithdrawalRequest;
    // Nonce for permit operations
    uint256 internal _nonce;
    // Current spending limit
    SpendingLimit internal _spendingLimit;
    // Boolean to toggle recovery mechanism on or off
    bool internal _isRecoveryActive;
    // Debit/Credit mode
    Mode internal _mode;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address __cashDataProvider) {
        _cashDataProvider = ICashDataProvider(__cashDataProvider);
        _disableInitializers();
    }

    function owner() public view returns (OwnerLib.OwnerObject memory) {
        if (
            _incomingOwnerStartTime != 0 &&
            block.timestamp > _incomingOwnerStartTime
        ) return _incomingOwnerBytes.getOwnerObject();

        return _ownerBytes.getOwnerObject();
    }

    function _getDecimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }
}