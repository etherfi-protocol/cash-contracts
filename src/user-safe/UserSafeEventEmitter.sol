// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SpendingLimit} from "../libraries/SpendingLimitLib.sol";
import {OwnerLib} from "../libraries/OwnerLib.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {UserSafeStorage} from "./UserSafeStorage.sol";

contract UserSafeEventEmitter is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    ICashDataProvider public cashDataProvider;

    error OnlyUserSafe();

    constructor() {
        _disableInitializers();
    }
        
    function initialize(address owner, address _cashDataProvider) external initializer {
        __UUPSUpgradeable_init();
        __AccessControlDefaultAdminRules_init_unchained(5 * 60, owner);
        cashDataProvider = ICashDataProvider(_cashDataProvider);
    }

    event WithdrawalRequested(address indexed userSafe, address[] tokens, uint256[] amounts, address indexed recipient, uint256 finalizeTimestamp);
    event WithdrawalAmountUpdated(address indexed userSafe, address indexed token, uint256 amount);
    event WithdrawalCancelled(address indexed userSafe, address[] tokens, uint256[] amounts, address indexed recipient);
    event WithdrawalProcessed(address indexed userSafe, address[] tokens, uint256[] amounts, address indexed recipient);
    event TransferForSpending(address indexed userSafe, address indexed token, uint256 amount);
    event SwapTransferForSpending(address indexed userSafe, address indexed inputToken, uint256 inputAmount, address indexed outputToken, uint256 outputTokenSent);
    event AddCollateralToDebtManager(address indexed userSafe, address indexed token, uint256 amount);
    event BorrowFromDebtManager(address indexed userSafe, address indexed token, uint256 amount);
    event RepayDebtManager(address indexed userSafe, address indexed token, uint256 debtAmount, uint256 debtAmountInUsd);
    event WithdrawCollateralFromDebtManager(address indexed userSafe, address indexed token, uint256 amount);
    event CloseAccountWithDebtManager(address indexed userSafe);
    event IsRecoveryActiveSet(address indexed userSafe, bool isActive);
    event OwnerSet(address indexed userSafe, OwnerLib.OwnerObject oldOwner, OwnerLib.OwnerObject newOwner);
    event IncomingOwnerSet(address indexed userSafe,  OwnerLib.OwnerObject incomingOwner, uint256 incomingOwnerStartTime);
    event UserRecoverySignerSet(address indexed userSafe,  address oldRecoverySigner, address newRecoverySigner);
    event SpendingLimitChanged(address indexed userSafe, SpendingLimit oldLimit, SpendingLimit newLimit);
    event ModeSet(address indexed userSafe, UserSafeStorage.Mode prevMode, UserSafeStorage.Mode newMode, uint256 incomingModeStartTime);
    event Spend(address indexed userSafe, address indexed token, uint256 amount, uint256 amountInUsd, UserSafeStorage.Mode mode);
    event Swap(address indexed userSafe, address indexed inputToken, uint256 inputAmount, address indexed outputToken, uint256 outputAmount);
    event Cashback(address indexed userSafe, uint256 spendingInUsd, address indexed cashbackToken, uint256 cashbackAmount, uint256 cashbackInUsd, bool paid);
    event PendingCashbackCleared(address indexed userSafe, address indexed cashbackToken, uint256 cashbackAmount, uint256 cashbackInUsd);

    function emitPendingCashbackClearedEvent(address cashbackToken, uint256 cashbackAmount, uint256 cashbackInUsd) external onlyUserSafe {
        emit PendingCashbackCleared(msg.sender, cashbackToken, cashbackAmount, cashbackInUsd);
    }

    function emitCashbackEvent(uint256 spendingInUsd, address cashbackToken, uint256 cashbackAmount, uint256 cashbackInUsd, bool paid) external onlyUserSafe {
        emit Cashback(msg.sender, spendingInUsd, cashbackToken, cashbackAmount, cashbackInUsd, paid);
    }

    function emitSpend(address token, uint256 amount, uint256 amountInUsd, UserSafeStorage.Mode mode) external onlyUserSafe {
        emit Spend(msg.sender, token, amount, amountInUsd, mode);
    }

    function emitSwap(address inputToken, uint256 inputAmount, address outputToken, uint256 outputAmount) external onlyUserSafe {
        emit Swap(msg.sender, inputToken, inputAmount, outputToken, outputAmount);
    }

    function emitSetMode(UserSafeStorage.Mode prevMode, UserSafeStorage.Mode newMode, uint256 incomingModeStartTime) external onlyUserSafe {
        emit ModeSet(msg.sender, prevMode, newMode, incomingModeStartTime);
    }

    function emitWithdrawalRequested(address[] memory tokens, uint256[] memory amounts, address recipient, uint256 finalizeTimestamp) external onlyUserSafe {
        emit WithdrawalRequested(msg.sender, tokens, amounts, recipient, finalizeTimestamp);
    }

    function emitWithdrawalAmountUpdated(address token, uint256 amount) external onlyUserSafe {
        emit WithdrawalAmountUpdated(msg.sender, token, amount);
    }

    function emitWithdrawalCancelled(address[] memory tokens, uint256[] memory amounts, address recipient) external onlyUserSafe {
        emit WithdrawalCancelled(msg.sender, tokens, amounts, recipient);
    }

    function emitWithdrawalProcessed(address[] memory tokens, uint256[] memory amounts, address recipient) external onlyUserSafe {
        emit WithdrawalProcessed(msg.sender, tokens, amounts, recipient);
    }

    function emitTransferForSpending(address token, uint256 amount) external onlyUserSafe {
        emit TransferForSpending(msg.sender, token, amount);
    }

    function emitSwapTransferForSpending(address inputToken, uint256 inputAmount, address outputToken, uint256 outputTokenSent) external onlyUserSafe {
        emit SwapTransferForSpending(msg.sender, inputToken, inputAmount, outputToken, outputTokenSent);
    }

    function emitAddCollateralToDebtManager(address token, uint256 amount) external onlyUserSafe {
        emit AddCollateralToDebtManager(msg.sender, token, amount);
    }

    function emitBorrowFromDebtManager(address token, uint256 amount) external onlyUserSafe {
        emit BorrowFromDebtManager(msg.sender, token, amount);
    }

    function emitRepayDebtManager(address token, uint256 amount, uint256 amountInUsd) external onlyUserSafe {
        emit RepayDebtManager(msg.sender, token, amount, amountInUsd);
    }

    function emitWithdrawCollateralFromDebtManager(address token, uint256 amount) external onlyUserSafe {
        emit WithdrawCollateralFromDebtManager(msg.sender, token, amount);
    }

    function emitCloseAccountWithDebtManager() external onlyUserSafe {
        emit CloseAccountWithDebtManager(msg.sender);
    }

    function emitIsRecoveryActiveSet(bool isActive) external onlyUserSafe {
        emit IsRecoveryActiveSet(msg.sender, isActive);
    }

    function emitOwnerSet(OwnerLib.OwnerObject memory oldOwner, OwnerLib.OwnerObject memory newOwner) external onlyUserSafe {
        emit OwnerSet(msg.sender, oldOwner, newOwner);
    }

    function emitIncomingOwnerSet(OwnerLib.OwnerObject memory incomingOwner, uint256 incomingOwnerStartTime) external onlyUserSafe {
        emit IncomingOwnerSet(msg.sender, incomingOwner, incomingOwnerStartTime);
    }

    function emitUserRecoverySignerSet(address oldRecoverySigner, address newRecoverySigner) external onlyUserSafe {
        emit UserRecoverySignerSet(msg.sender, oldRecoverySigner, newRecoverySigner);
    }

    function emitSpendingLimitChanged(SpendingLimit memory oldLimit, SpendingLimit memory newLimit) external onlyUserSafe {
        emit SpendingLimitChanged(msg.sender, oldLimit, newLimit);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
    
    function _onlyUserSafe() private view {
        if (!cashDataProvider.isUserSafe(msg.sender)) revert OnlyUserSafe();
    }

    modifier onlyUserSafe() {
        _onlyUserSafe();
        _;
    }
}