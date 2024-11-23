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
    using SafeERC20 for IERC20;

    enum Mode {
        Credit,
        Debit
    }
    
    struct Signature {
        uint8 index;
        bytes signature;
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
    error AmountZero();
    error OnlyUserSafeFactory();
    error ModeAlreadySet();
    error NotACollateralToken();
    error OnlyDebtManager();
    error SwapAndSpendOnlyInDebitMode();
    error CollateralTokensBalancesZero();
    error OutputLessThanMinAmount();
    error OnlyCashbackDispatcher();
    error TransactionAlreadyCleared();

    uint256 public constant HUNDRED_PERCENT = 100e18;
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
    // Incoming time when you switch from Debit -> Credit mode
    uint256 internal _incomingCreditModeStartTime;
    // Pending cashback in USD
    uint256 internal _pendingCashbackInUsd;
    // Mapping of transaction ID to clearance
    mapping(bytes32 => bool) internal _transactionCleared;
    
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

    function _getCollateralBalanceWithTokenSubtracted(address token, uint256 amount, Mode __mode) internal view returns (IL2DebtManager.TokenData[] memory, string memory error) {
        address[] memory collateralTokens = IL2DebtManager(_cashDataProvider.etherFiCashDebtManager()).getCollateralTokens();
        uint256 len = collateralTokens.length;
        IL2DebtManager.TokenData[] memory tokenAmounts = new IL2DebtManager.TokenData[](collateralTokens.length);
        uint256 m = 0;
        for (uint256 i = 0; i < len; ) {
            uint256 balance = IERC20(collateralTokens[i]).balanceOf(address(this)); 
            uint256 pendingWithdrawalAmount = getPendingWithdrawalAmount(collateralTokens[i]);
            if (balance != 0) {
                balance = balance - pendingWithdrawalAmount;
                if (__mode == Mode.Debit && token == collateralTokens[i]) {
                    if (balance == 0 || balance < amount) return(new IL2DebtManager.TokenData[](0), "Insufficient effective balance after withdrawal to spend with debit mode");
                    balance = balance - amount;
                }
                tokenAmounts[m] = IL2DebtManager.TokenData({token: collateralTokens[i], amount: balance});
                unchecked {
                    ++m;
                }
            }
            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(tokenAmounts, m)
        }

        return (tokenAmounts, "");
    }

    function getPendingWithdrawalAmount(address token) public view returns (uint256) {
        uint256 len = _pendingWithdrawalRequest.tokens.length;
        uint256 tokenIndex = len;
        for (uint256 i = 0; i < len; ) {
            if (_pendingWithdrawalRequest.tokens[i] == token) {
                tokenIndex = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        return tokenIndex != len ? _pendingWithdrawalRequest.amounts[tokenIndex] : 0;
    }

    function getUserTotalCollateral() public view returns (IL2DebtManager.TokenData[] memory) {
        IL2DebtManager debtManager = IL2DebtManager(_cashDataProvider.etherFiCashDebtManager());
        address[] memory collateralTokens = debtManager.getCollateralTokens();
        uint256 len = collateralTokens.length;
        IL2DebtManager.TokenData[] memory tokenAmounts = new IL2DebtManager.TokenData[](collateralTokens.length);
        uint256 m = 0;
        for (uint256 i = 0; i < len; ) {
            uint256 balance = IERC20(collateralTokens[i]).balanceOf(address(this)); 
            uint256 pendingWithdrawalAmount = getPendingWithdrawalAmount(collateralTokens[i]);
            if (balance != 0) {
                balance = balance - pendingWithdrawalAmount;
                tokenAmounts[m] = IL2DebtManager.TokenData({token: collateralTokens[i], amount: balance});
                unchecked {
                    ++m;
                }
            }
            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(tokenAmounts, m)
        }

        return tokenAmounts;
    }

    function getUserCollateralForToken(address token) public view returns (uint256) {
        IL2DebtManager debtManager = IL2DebtManager(_cashDataProvider.etherFiCashDebtManager());
        if (!debtManager.isCollateralToken(token)) revert NotACollateralToken();
        uint256 balance = IERC20(token).balanceOf(address(this)); 
        uint256 pendingWithdrawalAmount = getPendingWithdrawalAmount(token);

        return balance - pendingWithdrawalAmount;
    }

    function _getDecimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
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

    function _swapFunds(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        bytes calldata swapData
    ) internal returns (uint256) {
        address swapper = _cashDataProvider.swapper();
        IERC20(inputTokenToSwap).safeTransfer(
            address(swapper),
            inputAmountToSwap
        );
        uint256 balBefore = IERC20(outputToken).balanceOf(address(this));

        uint256 outputAmount = ISwapper(swapper).swap(
            inputTokenToSwap,
            outputToken,
            inputAmountToSwap,
            outputMinAmount,
            guaranteedOutputAmount,
            swapData
        );

        if (
            IERC20(outputToken).balanceOf(address(this)) !=
            balBefore + outputAmount
        ) revert IncorrectOutputAmount();

        if (outputAmount < outputMinAmount) revert OutputLessThanMinAmount();

        return outputAmount;
    }

    modifier currentMode() {
        if (_incomingCreditModeStartTime != 0 && block.timestamp > _incomingCreditModeStartTime) {
            _mode = Mode.Credit;
            delete _incomingCreditModeStartTime;
        }
        
        _;
    }
}