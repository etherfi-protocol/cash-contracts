// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnerLib} from "../libraries/OwnerLib.sol";
import {SpendingLimit} from "../libraries/SpendingLimitLib.sol";
import {DebtManagerStorage} from "../debt-manager/DebtManagerStorage.sol";

interface IUserSafe {
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
    error RepayBorrowBeforeSwitchToDebitMode();
    error BorrowingGreaterThanMaxBorrowAfterWithdrawal();
    error BorrowingGreaterThanMaxBorrow();
    error InsufficientBorrowingPower();

    /**
     * @notice Function to fetch the current mode of the safe (Debit/Credit)
     */
    function mode() external view returns (Mode);

    /**
     * @notice Function to fetch the incoming credit mode start time
     */
    function incomingCreditModeStartTime() external view returns (uint256);

    /**
     * @notice Function to fetch the address of the owner of the User Safe.
     * @return address of the owner of the User Safe.
     */
    function owner() external view returns (OwnerLib.OwnerObject memory);

    /**
     * @notice Function to fetch the contract address of the Cash Data Provider.
     * @return contract address of the Cash Data Provider.
     */
    function cashDataProvider() external view returns (address);

    /**
     * @notice Function to fetch the pending withdrawal request.
     * @return WithdrawalRequest struct.
     */
    function pendingWithdrawalRequest()
        external
        view
        returns (WithdrawalRequest memory);

    /**
     * @notice Function to fetch the current nonce.
     * @return Nonce
     */
    function nonce() external view returns (uint256);

    /**
     * @notice Function to fetch if a transaction is already cleared.
     * @param txId Transaction ID.
     * @return true it already cleared.
     */
    function transactionCleared(bytes32 txId) external view returns (bool);

    /**
     * @notice Function to fetch the user collateral.
     * @return The collateral tokens data.
     */
    function getUserTotalCollateral() external view returns (DebtManagerStorage.TokenData[] memory);

    /**
     * @notice Function to fetch the user collateral for a particular token.
     * @param token Address of the token.
     * @return Amount of collateral in the token.
     */
    function getUserCollateralForToken(address token) external view returns (uint256);
    
    /**
     * @notice Function to fetch the pending withdrawal amount for a particular token.
     * @param token Address of the token.
     * @return Pending withdrawal amount.
     */
    function getPendingWithdrawalAmount(address token) external view returns (uint256);

    /**
     * @notice Function to fetch the pending cashback amount in USD.
     * @return Pending cashback amount in USD.
     */
    function pendingCashback() external view returns (uint256);

    /**
     * @notice Function to fetch whether the recovery is active.
     */
    function isRecoveryActive() external view returns (bool);

    /**
     * @notice Function to fetch the recovery signers.
     * @return Array of recovery signers.
     */
    function recoverySigners()
        external
        view
        returns (OwnerLib.OwnerObject[3] memory);

    /**
     * @notice Function to get the current applicable spending limit.
     * @notice This function gives incoming spending limit if it is set and its start time is in the past.
     * @notice This function gives renewed limit based on if the renewal timestamp is in the past.
     * @return Current applicable spending limit
     */
    function applicableSpendingLimit() external view returns (SpendingLimit memory);

    /**
     * @notice Function to fetch if a user can spend. 
     * @notice This is a utility function for the backend to put checks on spendings.
     * @param token Address of the token to spend.
     * @param amountInUsd Amount of USD to spend in 6 decimals.
     */
    function canSpend(address token, uint256 amountInUsd) external view returns (bool, string memory);

    /**
     * @notice Function to fetch the max amount the user can spend in the current mode.
     * @param token Address of the token to spend.
     * @return max spend the user can make in USD with 6 decimals.
     */
    function maxCanSpend(address token) external view returns (uint256);

    /**
     * @notice Function to set the owner of the contract.
     * @param __owner Address of the new owner
     * @param signature Must be a valid signature from the user.
     */
    function setOwner(
        bytes calldata __owner,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to set the mode of the user safe (Debit/Credit)
     * @param mode Debit/Credit mode
     * @param signature Must be a valid signature from the user.
     */
    function setMode(Mode mode, bytes calldata signature) external;

    /**
     * @notice Function to set the spending limit with permit.
     * @notice This does not affect the used up amount and specify a new limit.
     * @param dailyLimitInUsd Daily spending limit in USD with 6 decimals.
     * @param dailyLimitInUsd Monthly spending limit in USD with 6 decimals.
     * @param signature Must be a valid signature from the user.
     */
    function updateSpendingLimit(
        uint256 dailyLimitInUsd,
        uint256 monthlyLimitInUsd,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to request withdrawal of funds with permit from this safe.
     * @notice Can be withdrawn with a configurable delay.
     * @param tokens Address of the tokens to withdraw.
     * @param amounts Amount of the tokens to withdraw.
     * @param recipient Address of the recipient of funds.
     * @param signature Must be a valid signature from the user.
     */
    function requestWithdrawal(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to process pending withdrawal post the delay.
     * @dev Can be called by any wallet.
     */
    function processWithdrawal() external;

    /**
     * @notice Function to recover a user safe.
     * @notice Can only be recovered when the isRecoveryActive boolean is set to true.
     * @notice Can only be recovered if atleast 2 of the three recovery signers sign the transaction.
     * @notice The three recovery signers are: userRecoverySigner set by the owner of the safe, ether fi signer, third party signer.
     * @notice On recovery, funds are sent to the etherFiRecoverySafe contract which can be distributed to the user.
     * @param signatures Array of the signature struct containing any 2 out of 3 signers' signatures.
     * @param newOwner Owner bytes for new owner. If ethAddr, abi.encode(addr) and if passkey, abi.encode(x,y).
     */
    function recoverUserSafe(
        bytes calldata newOwner,
        Signature[2] calldata signatures
    ) external;

    /**
     * @notice Function to set _isRecoveryActive boolean.
     * @param isActive Boolean value suggesting if recover should be active.
     * @param signature Must be a valid signature from the user.
     */
    function setIsRecoveryActive(
        bool isActive,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to set a user recovery signer.
     * @param userRecoverySigner Address of the user recovery signer.
     * @param signature Must be a valid signature from the user.
     */
    function setUserRecoverySigner(
        address userRecoverySigner,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to swap funds inside the user safe.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @param inputTokenToSwap Address of input token to swap.
     * @param outputToken Address of the output token of the swap.
     * @param inputAmountToSwap Amount of input token to swap.
     * @param outputMinAmount Min output amount of the output token to receive from the swap.
     * @param guaranteedOutputAmount Guaranteed amount of output token (only for openocean swap).
     * @param swapData Swap data received from the swapper API.
     * @param signature Signature from the user.
     */
    function swap(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        bytes calldata swapData,
        bytes calldata signature
    ) external;

    /**
     * @notice Function called by liquidate function in DebtManager to cancel withdrawals
     */
    function preLiquidate() external;

    /**
     * @notice Function called by liquidate function in DebtManager to transfer collateral to the liquidator
     * @param liquidator Address of the liquidator.
     * @param tokensToSend Tokens to send to the liquidator.
     */
    function postLiquidate(address liquidator, DebtManagerStorage.LiquidationTokenData[] memory tokensToSend) external;

    /**
     * @notice Function to credit the pending cashback from the cashback dispatcher to the user safe.
     */
    function retrievePendingCashback() external;

    /**
     * @notice Function to spend via debit or credit mode.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only spend supported tokens.
     * @param txId Transaction ID.
     * @param token Address of the token to transfer.
     * @param amountInUsd Amount of USD to transfer in 6 decimals.
     */
    function spend(bytes32 txId, address token, uint256 amountInUsd) external;

    /**
     * @notice Function to repay funds to EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @param token Address of token to use for repayment. Can be USD or the collateral tokens.
     * @param amount Amount of tokens to be repaid.
     */
    function repay(address token, uint256 amount) external;

    /**
     * @notice Function to swap funds to output token and repay loan to Debt Manager.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only swap to a supported token.
     * @param inputTokenToSwap Address of input token to swap.
     * @param outputToken Address of the output token of the swap.
     * @param inputAmountToSwap Amount of input token to swap.
     * @param outputMinAmount Min output amount of the output token to receive from the swap.
     * @param guaranteedOutputAmount Guaranteed amount of output token (only for openocean swap).
     * @param outputAmountToRepayInUsd Amount of output token to repay the loan.
     * @param swapData Swap data received from the swapper API.
     */
    function swapAndRepay(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        uint256 outputAmountToRepayInUsd,
        bytes calldata swapData
    ) external;

    /**
     * @notice Function to swap funds to output token and transfer it to EtherFiCash Safe.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only swap to a supported token.
     * @param txId Transaction ID..
     * @param inputTokenToSwap Address of input token to swap.
     * @param outputToken Address of the output token of the swap.
     * @param inputAmountToSwap Amount of input token to swap.
     * @param outputMinAmount Min output amount of the output token to receive from the swap.
     * @param guaranteedOutputAmount Guaranteed amount of output token (only for openocean swap).
     * @param outputAmountToTransfer Amount of output token to send to the EtherFiCash Safe.
     * @param swapData Swap data received from the swapper API.
     */
    function swapAndSpend(    
        bytes32 txId,
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 guaranteedOutputAmount,
        uint256 outputAmountToTransfer,
        bytes calldata swapData
    ) external;
}