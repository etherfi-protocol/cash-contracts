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
import {CashbackDispatcher} from "../cashback-dispatcher/CashbackDispatcher.sol";

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

    function pendingCashback() external view returns (uint256) {
        return _pendingCashbackInUsd;
    }

    function transactionCleared(bytes32 txId) external view returns (bool) {
        return _transactionCleared[txId];
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
        bytes32 txId,
        address token,
        uint256 amountInUsd
    ) public view returns (bool, string memory) {
        if (_transactionCleared[txId]) return (false, "Transaction already cleared");
        if (!_isBorrowToken(token)) return (false, "Not a supported stable token");
        
        address debtManager = _cashDataProvider.etherFiCashDebtManager();

        uint256 amount = IL2DebtManager(debtManager).convertUsdToCollateralToken(token, amountInUsd);
        if (amount == 0) return (false, "Amount zero");
        
        Mode __mode = _mode;
        if (_incomingCreditModeStartTime != 0) __mode = Mode.Credit;
        
        if (__mode == Mode.Debit) {
            uint256 withdrawalAmount = getPendingWithdrawalAmount(token);
            if (IERC20(token).balanceOf(address(this)) - withdrawalAmount < amount) return (false, "Insufficient effective balance to spend with Debit flow");
        } else {
            (uint256 totalMaxBorrow, uint256 totalBorrowings) = IL2DebtManager(debtManager).getBorrowingPowerAndTotalBorrowing(address(this));
            if (totalBorrowings > totalMaxBorrow) return (false, "Borrowings greater than max borrow");
            if (amountInUsd > totalMaxBorrow - totalBorrowings) return (false, "Insufficient borrowing power");        
            if (IERC20(token).balanceOf(debtManager) < amount) return (false, "Insufficient liquidity in debt manager to cover the loan");
        }

        return _spendingLimit.canSpend(amountInUsd);
    }

    function maxCanSpend(address token) external view returns (uint256) {
        uint256 returnAmtInUsd = 0;
        IL2DebtManager debtManager = IL2DebtManager(_cashDataProvider.etherFiCashDebtManager());
        
        Mode __mode = _mode;
        if (_incomingCreditModeStartTime != 0) __mode = Mode.Credit;

        if (__mode == Mode.Debit) {
            uint256 spendableAmt = IERC20(token).balanceOf(address(this)) - getPendingWithdrawalAmount(token);
            returnAmtInUsd = debtManager.convertCollateralTokenToUsd(token, spendableAmt);
        } else {
            (uint256 totalMaxBorrow, uint256 totalBorrowings) = debtManager.getBorrowingPowerAndTotalBorrowing(address(this));
            if (totalBorrowings > totalMaxBorrow) return 0;
            returnAmtInUsd = totalMaxBorrow - totalBorrowings;
        }

        returnAmtInUsd = Math.min(returnAmtInUsd, _spendingLimit.maxCanSpend());
        // removing dust
        return (returnAmtInUsd / 10**4) * 10**4; 
    }

    function spend(bytes32 txId, address token, uint256 amountInUsd) external currentMode onlyEtherFiWallet {
        uint256 amount = _spend(txId, token, amountInUsd);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSpend(token, amount, amountInUsd, _mode);
    }

    function swapAndSpend(    
        bytes32 txId, 
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        uint256 amountToSpendInUsd,
        bytes calldata swapData
    ) external currentMode onlyEtherFiWallet {
        if (_mode != Mode.Debit) revert SwapAndSpendOnlyInDebitMode();
        if (!_isBorrowToken(outputToken)) revert UnsupportedToken();

        uint256 outputAmount = _swapFunds(inputTokenToSwap, outputToken, inputAmountToSwap, outputMinAmount, guaranteedOutputAmount, swapData);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSwap(inputTokenToSwap, inputAmountToSwap, outputToken, outputAmount);
        
        if (amountToSpendInUsd > 0) {
            uint256 amount = _spend(txId, outputToken, amountToSpendInUsd);
            UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSpend(outputToken, amount, amountToSpendInUsd, _mode);
        }
    }

    function retrievePendingCashback() public {
        if (_pendingCashbackInUsd == 0) return;
        (address cashbackToken, uint256 cashbackAmount, bool paid) = CashbackDispatcher(_cashDataProvider.cashbackDispatcher()).clearPendingCashback();
        if (paid) {
            UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitPendingCashbackClearedEvent(cashbackToken, cashbackAmount, _pendingCashbackInUsd);
            delete _pendingCashbackInUsd;
        }
    }

    function _spend(bytes32 txId, address token, uint256 amountInUsd) internal returns (uint256) {
        if (_transactionCleared[txId]) revert TransactionAlreadyCleared();
        _transactionCleared[txId] = true;

        if (!_isBorrowToken(token)) revert UnsupportedToken();
        address debtManager = _cashDataProvider.etherFiCashDebtManager();

        uint256 amount = IL2DebtManager(debtManager).convertUsdToCollateralToken(token, amountInUsd);
        if (amount == 0) revert AmountZero();

        retrievePendingCashback();
        _spendingLimit.spend(amountInUsd);

        if (_mode == Mode.Debit) {
            _updateWithdrawalRequestIfNecessary(token, amount);
            IERC20(token).safeTransfer(_cashDataProvider.settlementDispatcher(), amount);
        } else {
            try IL2DebtManager(debtManager).borrow(token, amount) {}
            catch {
                _cancelOldWithdrawal();
                IL2DebtManager(debtManager).borrow(token, amount);
            }
        }

        (address cashbackToken, uint256 cashbackAmount, uint256 cashbackInUsd, bool paid) = CashbackDispatcher(_cashDataProvider.cashbackDispatcher()).cashback(amountInUsd);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitCashbackEvent(amountInUsd, cashbackToken, cashbackAmount, cashbackInUsd, paid);
        if (!paid) _pendingCashbackInUsd += cashbackInUsd;

        return amount;
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

    function repay(address token, uint256 amountInUsd) public onlyEtherFiWallet {
        if (!_isBorrowToken(token)) revert OnlyBorrowToken();
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _repay(debtManager, token, amountInUsd);
    }

    function swapAndRepay(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        uint256 outputAmountToRepayInUsd,
        bytes calldata swapData
    ) external onlyEtherFiWallet {
        if (!_isBorrowToken(outputToken)) revert UnsupportedToken();
        if (outputAmountToRepayInUsd == 0) revert AmountCannotBeZero();
        uint256 outputAmount = _swapFunds(inputTokenToSwap, outputToken, inputAmountToSwap, outputMinAmount, guaranteedOutputAmount, swapData);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSwap(inputTokenToSwap, inputAmountToSwap, outputToken, outputAmount);

        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _repay(debtManager, outputToken, outputAmountToRepayInUsd);
    }

    function _repay(
        address debtManager,
        address token,
        uint256 amountInUsd
    ) internal {
        uint256 amount = IL2DebtManager(debtManager).convertUsdToCollateralToken(token, amountInUsd);
        if (amount == 0) revert AmountZero();
        _updateWithdrawalRequestIfNecessary(token, amount);

        IERC20(token).forceApprove(debtManager, amount);

        IL2DebtManager(debtManager).repay(address(this), token, amount);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitRepayDebtManager(token, amount, amountInUsd);
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