// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeStorage, OwnerLib, ArrayDeDupTransient, UserSafeEventEmitter, UserSafeLib, SpendingLimit, SpendingLimitLib} from "./UserSafeStorage.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
    ) external view returns (bool, string memory) {
        amount = (amount * 10 ** 6) / 10 ** _getDecimals(token);
        if (amount == 0) revert AmountZeroWithSixDecimals();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) return (false, "Balance too low");

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
        if (tokenIndex != len) balance = balance - _pendingWithdrawalRequest.amounts[tokenIndex];
        if (balance < amount) return (false, "Tokens pending withdrawal");

        return _spendingLimit.canSpend(amount);
    }

    function processWithdrawal() external nonReentrant {
        if (_pendingWithdrawalRequest.finalizeTime > block.timestamp)
            revert CannotWithdrawYet();
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

    function transfer(
        address token,
        uint256 amount
    ) external onlyEtherFiWallet {
        if (!_isBorrowToken(token)) revert UnsupportedToken();

        _checkSpendingLimit(token, amount);
        _updateWithdrawalRequestIfNecessary(token, amount);

        IERC20(token).safeTransfer(
            _cashDataProvider.settlementDispatcher(),
            amount
        );

        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitTransferForSpending(token, amount);
    }

    function swapAndTransfer(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        uint256 outputAmountToTransfer,
        bytes calldata swapData
    ) external onlyEtherFiWallet {
        if (!_isBorrowToken(outputToken)) revert UnsupportedToken();

        _checkSpendingLimit(outputToken, outputAmountToTransfer);
        _updateWithdrawalRequestIfNecessary(
            inputTokenToSwap,
            inputAmountToSwap
        );

        uint256 balBefore = IERC20(outputToken).balanceOf(address(this));

        uint256 returnAmount = _swapFunds(
            inputTokenToSwap,
            outputToken,
            inputAmountToSwap,
            outputMinAmount,
            guaranteedOutputAmount,
            swapData
        );

        if (
            IERC20(outputToken).balanceOf(address(this)) !=
            balBefore + returnAmount
        ) revert IncorrectOutputAmount();

        if (outputAmountToTransfer > returnAmount)
            revert TransferAmountGreaterThanReceived();

        IERC20(outputToken).safeTransfer(
            _cashDataProvider.settlementDispatcher(),
            outputAmountToTransfer
        );

        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitSwapTransferForSpending(
            inputTokenToSwap, 
            inputAmountToSwap,
            outputToken,
            outputAmountToTransfer
        );
    }

    function addCollateral(
        address token,
        uint256 amount
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _addCollateral(debtManager, token, amount);
    }

    function addCollateralAndBorrow(
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _addCollateral(debtManager, collateralToken, collateralAmount);
        _borrow(debtManager, borrowToken, borrowAmount);
    }

    function borrow(address token, uint256 amount) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _borrow(debtManager, token, amount);
    }

    function repay(address token, uint256 amount) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _repay(debtManager, token, amount);
    }

    function withdrawCollateralFromDebtManager(
        address token,
        uint256 amount
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _withdrawCollateralFromDebtManager(debtManager, token, amount);
    }

    function closeAccountWithDebtManager() external onlyEtherFiWallet {
        IL2DebtManager(_cashDataProvider.etherFiCashDebtManager()).closeAccount();
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitCloseAccountWithDebtManager();
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
        return
            ISwapper(swapper).swap(
                inputTokenToSwap,
                outputToken,
                inputAmountToSwap,
                outputMinAmount,
                guaranteedOutputAmount,
                swapData
            );
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        uint8 tokenDecimals = _getDecimals(token);
        if (tokenDecimals != 6) amount = (amount * 1e6) / 10 ** tokenDecimals;
        _spendingLimit.spend(amount);
    }

    function _addCollateral(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        if (!_isCollateralToken(token)) revert UnsupportedToken();
        _updateWithdrawalRequestIfNecessary(token, amount);
        IERC20(token).forceApprove(debtManager, amount);
        IL2DebtManager(debtManager).depositCollateral(
            token,
            address(this),
            amount
        );
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitAddCollateralToDebtManager(token, amount);
    }

    function _borrow(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        if (!_isBorrowToken(token)) revert UnsupportedToken();

        _checkSpendingLimit(token, amount);

        IL2DebtManager(debtManager).borrow(token, amount);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitBorrowFromDebtManager(token, amount);
    }

    function _repay(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        // Repay token can either be borrow token or collateral token
        IERC20(token).forceApprove(debtManager, amount);

        IL2DebtManager(debtManager).repay(address(this), token, amount);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitRepayDebtManager(token, amount);
    }

    function _withdrawCollateralFromDebtManager(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        if (!_isCollateralToken(token)) revert UnsupportedToken();
        IL2DebtManager(debtManager).withdrawCollateral(token, amount);
        UserSafeEventEmitter(_cashDataProvider.userSafeEventEmitter()).emitWithdrawCollateralFromDebtManager(token, amount);
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

    function _isCollateralToken(address token) internal view returns (bool) {
        return IL2DebtManager(_cashDataProvider.etherFiCashDebtManager()).isCollateralToken(token);
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