// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeStorage, OwnerLib, ArrayDeDupTransient, UserSafeEventEmitter, UserSafeLib, SpendingLimit, SpendingLimitLib} from "./UserSafeStorage.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {IL2DebtManager} from "../interfaces/IL2DebtManager.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {UserSafeFactory} from "./UserSafeFactory.sol";

contract UserSafeCore is UserSafeStorage {
    using OwnerLib for bytes;
    using OwnerLib for address;
    using OwnerLib for OwnerLib.OwnerObject;
    using UserSafeLib for OwnerLib.OwnerObject;
    using SpendingLimitLib for SpendingLimit;
    using SafeERC20 for IERC20;
    using ArrayDeDupTransient for address[];
    using Math for uint256;

    constructor(address __cashDataProvider) UserSafeStorage(__cashDataProvider) {}

    function initialize(
        bytes calldata __owner,
        uint256 __dailySpendingLimit,
        uint256 __monthlySpendingLimit,
        int256 __timezoneOffset
    ) external initializer {        
        __ReentrancyGuardTransient_init();
        __owner.getOwnerObject()._ownerNotZero();
        
        _isRecoveryActive = true;
        _ownerBytes = __owner;
        SpendingLimit memory newLimit = _spendingLimit.initialize(
            __dailySpendingLimit,
            __monthlySpendingLimit,
            __timezoneOffset
        );

        emitInitializeEvents(newLimit, __owner);
    }

    function emitInitializeEvents(SpendingLimit memory newLimit, bytes memory __owner) internal {
        OwnerLib.OwnerObject memory dummyOwner;
        SpendingLimit memory dummyLimit;

        UserSafeEventEmitter eventEmitter = UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter());
        eventEmitter.emitSpendingLimitChanged(dummyLimit, newLimit);
        eventEmitter.emitOwnerSet(dummyOwner, __owner.getOwnerObject());
    }

    function cashDataProvider() external view returns (address) {
        return address(_cashDataProvider);
    }

    function mode() external view returns (Mode) {
        if (_incomingCreditModeStartTime != 0 && block.timestamp > _incomingCreditModeStartTime) return Mode.Credit;
        return _mode;
    }

    function incomingCreditModeStartTime() external view returns (uint256) {
        return _incomingCreditModeStartTime;
    }

    function pendingWithdrawalRequest()
        public
        view
        returns (WithdrawalRequest memory)
    {
        return _pendingWithdrawalRequest;
    }

    function nonce() external view returns (uint256) {
        return _nonce;
    }

    function applicableSpendingLimit()
        external
        view
        returns (SpendingLimit memory)
    {
        return _spendingLimit.getCurrentLimit();
    }

    function recoverySigners()
        external
        view
        returns (OwnerLib.OwnerObject[3] memory signers)
    {
        signers[0] = _userRecoverySigner.getOwnerObject();
        signers[1] = _cashDataProvider.etherFiRecoverySigner().getOwnerObject();
        signers[2] = _cashDataProvider.thirdPartyRecoverySigner().getOwnerObject();
    }

    function isRecoveryActive() external view returns (bool) {
        return _isRecoveryActive;
    }

    function canSpend(
        address token,
        uint256 amount
    ) public view returns (bool, string memory) {
        if (!_isBorrowToken(token)) return (false, "Not a supported stable token");
        address debtManager = _cashDataProvider.etherFiCashDebtManager();

        uint256 amountInUsd = IL2DebtManager(debtManager).convertCollateralTokenToUsd(token, amount);
        if (amountInUsd == 0) return (false, "Amount zero with 6 decimals");

        Mode __mode = _mode;
        if (_incomingCreditModeStartTime != 0) __mode = Mode.Credit;
        if (__mode == Mode.Debit && IERC20(token).balanceOf(address(this)) < amount) return (false, "Insufficient balance to spend with Debit flow");

        (IL2DebtManager.TokenData[] memory collateralTokenAmounts, string memory error) = _getCollateralBalanceWithTokenSubtracted(token, amount, __mode);
        if (bytes(error).length != 0) return (false, error);
        if (collateralTokenAmounts.length == 0) return (false, "Collateral tokens balances zero");
        (uint256 totalMaxBorrow, uint256 totalBorrowings) = 
            IL2DebtManager(debtManager).getBorrowingPowerAndTotalBorrowing(address(this), collateralTokenAmounts);
        if (totalBorrowings > totalMaxBorrow) return (false, "Borrowings greater than max borrow after spending");
        if (__mode == Mode.Credit) {
            if (amountInUsd > totalMaxBorrow - totalBorrowings) return (false, "Insufficient borrowing power");        
            if (IERC20(token).balanceOf(debtManager) < amount) return (false, "Insufficient liquidity in debt manager to cover the loan");
        } 

        return _spendingLimit.canSpend(amount);
    }

    function maxCanSpend(address token) external view returns (uint256) {
        uint256 returnAmt = 0;
        IL2DebtManager debtManager = IL2DebtManager(_cashDataProvider.etherFiCashDebtManager());

        (IL2DebtManager.TokenData[] memory collateralTokenAmounts, string memory error) = _getCollateralBalanceWithTokenSubtracted(token, 0, _mode);
        if (bytes(error).length != 0) revert(error);
        if (collateralTokenAmounts.length == 0) revert CollateralTokensBalancesZero();
        (uint256 totalMaxBorrow, uint256 totalBorrowings) = 
            debtManager.getBorrowingPowerAndTotalBorrowing(address(this), collateralTokenAmounts);
        if (totalBorrowings > totalMaxBorrow) revert("Borrowings greater than max borrow after spending");

        Mode __mode = _mode;
        if (_incomingCreditModeStartTime != 0) __mode = Mode.Credit;
        
        if (__mode == Mode.Credit) returnAmt = totalMaxBorrow - totalBorrowings;
        else {
            uint256 withdrawalAmount = getPendingWithdrawalAmount(token);
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            uint256 effectiveBal = tokenBalance - withdrawalAmount;
            if (effectiveBal == 0) revert ("Zero effective token balance");
            (collateralTokenAmounts, error) = _getCollateralBalanceWithTokenSubtracted(token, effectiveBal, _mode);
            if (bytes(error).length != 0) revert(error);
            (totalMaxBorrow, totalBorrowings) = debtManager.getBorrowingPowerAndTotalBorrowing(address(this), collateralTokenAmounts);
            
            if (totalMaxBorrow < totalBorrowings) {
                uint256 deficit = totalBorrowings - totalMaxBorrow;
                uint80 ltv = debtManager.collateralTokenConfig(token).ltv;
                uint256 amountRequiredToCoverDebt = deficit.mulDiv(HUNDRED_PERCENT, ltv, Math.Rounding.Ceil);
                returnAmt = effectiveBal - amountRequiredToCoverDebt;
            } else returnAmt = effectiveBal;
        }

        uint256 spendingLimitAllowanceRemaining = _spendingLimit.maxCanSpend();
        returnAmt = Math.min(returnAmt, spendingLimitAllowanceRemaining);

        // removing dust
        return (returnAmt / 10**4) * 10**4; 
    }

    function spend(address token, uint256 amount) external currentMode onlyEtherFiWallet {
        _spend(token, amount);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSpend(token, amount, _mode);
    }

    function swapAndSpend(    
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        uint256 outputAmountToTransfer,
        bytes calldata swapData
    ) external currentMode onlyEtherFiWallet {
        if (_mode != Mode.Debit) revert SwapAndSpendOnlyInDebitMode();
        uint256 outputAmount = _swapFunds(inputTokenToSwap, outputToken, inputAmountToSwap, outputMinAmount, guaranteedOutputAmount, swapData);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSwap(inputTokenToSwap, inputAmountToSwap, outputToken, outputAmount);
        
        if (outputAmountToTransfer > 0) {
            _spend(outputToken, outputAmountToTransfer);
            UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSpend(outputToken, outputAmountToTransfer, _mode);
        } else if (!_isBorrowToken(outputToken)) revert UnsupportedToken();
    }

    function _spend(address token, uint256 amount) internal {
        if (!_isBorrowToken(token)) revert UnsupportedToken();
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        
        uint256 amountInUsd = IL2DebtManager(debtManager).convertCollateralTokenToUsd(token, amount);
        if (amountInUsd == 0) revert AmountZeroWithSixDecimals();

        if (_mode == Mode.Debit && IERC20(token).balanceOf(address(this)) < amount) revert ("Insufficient balance to spend with Debit flow");
        (IL2DebtManager.TokenData[] memory collateralTokenAmounts, string memory error) = _getCollateralBalanceWithTokenSubtracted(token, amount, _mode);
        if (keccak256(bytes(error)) == keccak256("Insufficient effective balance after withdrawal to spend with debit mode")) {
            _updateWithdrawalRequestIfNecessary(token, amount);
            (collateralTokenAmounts, error) = _getCollateralBalanceWithTokenSubtracted(token, amount, _mode);
            if (bytes(error).length != 0) revert (error);
        }

        (uint256 totalMaxBorrow, uint256 totalBorrowings) =  IL2DebtManager(debtManager).getBorrowingPowerAndTotalBorrowing(address(this), collateralTokenAmounts);
        
        if (totalBorrowings > totalMaxBorrow || (_mode == Mode.Credit && amountInUsd > totalMaxBorrow - totalBorrowings)) {
            if (_pendingWithdrawalRequest.tokens.length != 0) {
                _cancelOldWithdrawal();
                (collateralTokenAmounts, error) = _getCollateralBalanceWithTokenSubtracted(token, amount, _mode);
                if (bytes(error).length != 0) revert(error);

                (totalMaxBorrow, totalBorrowings) = 
                    IL2DebtManager(_cashDataProvider.etherFiCashDebtManager()).getBorrowingPowerAndTotalBorrowing(address(this), collateralTokenAmounts);
            }
        }

        if (totalBorrowings > totalMaxBorrow) revert ("Borrowings greater than max borrow after spending");
        if (_mode == Mode.Credit && amountInUsd > totalMaxBorrow - totalBorrowings) revert("Insufficient borrowing power");

        _spendingLimit.spend(amountInUsd);

        if (_mode == Mode.Debit) IERC20(token).safeTransfer(_cashDataProvider.settlementDispatcher(), amount);
        else IL2DebtManager(_cashDataProvider.etherFiCashDebtManager()).borrow(token, amount);
    }

    function preLiquidate() external {
        if (msg.sender != _cashDataProvider.etherFiCashDebtManager()) revert OnlyDebtManager();
        _cancelOldWithdrawal();
    }

    function postLiquidate(address liquidator, IL2DebtManager.LiquidationTokenData[] memory tokensToSend) external {
        if (msg.sender != _cashDataProvider.etherFiCashDebtManager()) revert OnlyDebtManager();

        uint256 len = tokensToSend.length;

        for (uint256 i = 0; i < len; ) {
            if (tokensToSend[i].amount > 0) IERC20(tokensToSend[i].token).safeTransfer(liquidator, tokensToSend[i].amount);
            unchecked {
                ++i;
            }
        }
    }

    function processWithdrawal() external nonReentrant {
        if (_pendingWithdrawalRequest.finalizeTime > block.timestamp) revert CannotWithdrawYet();
        address recipient = _pendingWithdrawalRequest.recipient;
        uint256 len = _pendingWithdrawalRequest.tokens.length;

        for (uint256 i = 0; i < len; ) {
            IERC20(_pendingWithdrawalRequest.tokens[i]).safeTransfer(
                recipient,
                _pendingWithdrawalRequest.amounts[i]
            );

            unchecked {
                ++i;
            }
        }

        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitWithdrawalProcessed(_pendingWithdrawalRequest.tokens, _pendingWithdrawalRequest.amounts, recipient);
        delete _pendingWithdrawalRequest;
    }

    function repay(address token, uint256 amount) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _repay(debtManager, token, amount);
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        uint8 tokenDecimals = _getDecimals(token);
        if (tokenDecimals != 6) amount = (amount * 1e6) / 10 ** tokenDecimals;
        _spendingLimit.spend(amount);
    }

    function _repay(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        IERC20(token).forceApprove(debtManager, amount);

        IL2DebtManager(debtManager).repay(address(this), token, amount);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitRepayDebtManager(token, amount);
    }

    function _updateWithdrawalRequestIfNecessary(
        address token,
        uint256 amount
    ) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));

        if (amount > balance) revert InsufficientBalance();

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

        // If the token does not exist in withdrawal request
        if (tokenIndex == len) return;

        if (amount + _pendingWithdrawalRequest.amounts[tokenIndex] > balance) {
            _pendingWithdrawalRequest.amounts[tokenIndex] = balance - amount;
            UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitWithdrawalAmountUpdated(token, balance - amount);
        }
    }

    function _isBorrowToken(address token) internal view returns (bool) {
        return IL2DebtManager(_cashDataProvider.etherFiCashDebtManager()).isBorrowToken(token);
    }

    function _onlyEtherFiWallet() private view {
        if (!_cashDataProvider.isEtherFiWallet(msg.sender))
            revert UnauthorizedCall();
    }

    modifier onlyEtherFiWallet() {
        _onlyEtherFiWallet();
        _;
    }

    /**
     * @dev Falldown to the admin implementation
     * @notice This is a catch all for all functions not declared in core
     */
    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        address transfersImpl = UserSafeFactory(_cashDataProvider.userSafeFactory()).userSafeSettersImpl();
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(
                gas(),
                transfersImpl,
                0,
                calldatasize(),
                0,
                0
            )

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}