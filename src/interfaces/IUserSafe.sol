// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnerLib} from "../libraries/OwnerLib.sol";

interface IUserSafe {
    enum SpendingLimitTypes {
        None,
        Daily,
        Weekly,
        Monthly,
        Yearly
    }

    struct Signature {
        uint8 index;
        bytes signature;
    }

    struct TokenData {
        address token;
        uint256 amount;
    }

    struct WithdrawalRequest {
        address[] tokens;
        uint256[] amounts;
        address recipient;
        uint96 finalizeTime;
    }

    struct SpendingLimitData {
        SpendingLimitTypes spendingLimitType;
        uint64 renewalTimestamp;
        uint256 spendingLimit; // in USD with 6 decimals
        uint256 usedUpAmount; // in USD with 6 decimals
    }

    event DepositFunds(address indexed token, uint256 amount);
    event WithdrawalRequested(
        address[] tokens,
        uint256[] amounts,
        address indexed recipient,
        uint256 finalizeTimestamp
    );
    event WithdrawalAmountUpdated(address indexed token, uint256 amount);
    event WithdrawalCancelled(
        address[] tokens,
        uint256[] amounts,
        address indexed recipient
    );
    event WithdrawalProcessed(
        address[] tokens,
        uint256[] amounts,
        address indexed recipient
    );
    event TransferForSpending(address indexed token, uint256 amount);
    event SwapTransferForSpending(
        address indexed inputToken,
        uint256 inputAmount,
        address indexed outputToken,
        uint256 outputTokenSent
    );
    event AddCollateral(address token, uint256 amount);
    event Borrow(address token, uint256 amount);
    event Repay(address token, uint256 debtAmount);
    event WithdrawCollateral(address token, uint256 amount);
    event ResetSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd,
        uint256 startTime
    );
    event UpdateSpendingLimit(
        uint256 oldLimitInUsd,
        uint256 newLimitInUsd,
        uint256 startTime
    );
    event SetCollateralLimit(
        uint256 oldLimitInUsd,
        uint256 newLimitInUsd,
        uint256 startTime
    );
    event IsRecoveryActiveSet(bool isActive);
    event UserSafeRecovered(
        OwnerLib.OwnerObject oldOwner,
        OwnerLib.OwnerObject newOwner
    );
    event SetOwner(
        OwnerLib.OwnerObject oldOwner,
        OwnerLib.OwnerObject newOwner
    );

    error InsufficientBalance();
    error ArrayLengthMismatch();
    error CannotWithdrawYet();
    error UnauthorizedCall();
    error InvalidNonce();
    error TransferAmountGreaterThanReceived();
    error ExceededSpendingLimit();
    error ExceededCollateralLimit();
    error InvalidSpendingLimitType();
    error UnsupportedToken();
    error RecoveryNotActive();
    error InvalidSignatureIndex();
    error SignatureIndicesCannotBeSame();
    error AmountCannotBeZero();
    error RecoverySignersCannotBeSame();

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
     * @notice Function to fetch the total collateral of the user.
     * @return TokenData struct containing collateral tokens and respective amounts
     * @return Total collateral in USDC
     */
    function getTotalCollateral()
        external
        view
        returns (TokenData[] memory, uint256);

    /**
     * @notice Function to fetch the total debt of the user.
     * @return TokenData struct containing borrow tokens and respective amounts
     * @return Total debt in USDC
     */
    function getTotalDebt() external view returns (TokenData[] memory, uint256);

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
    function applicableSpendingLimit()
        external
        view
        returns (SpendingLimitData memory);

    /**
     * @notice Function to get the current applicable collateral limit.
     * @notice This function gives incoming collateral limit if it is set and its start time is in the past.
     * @return Current applicable collateral limit
     */
    function applicableCollateralLimit() external view returns (uint256);

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
     * @notice Function to set the spending limit with permit.
     * @notice This resets the used up amount to 0 and specify a new limit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     * @param signature Must be a valid signature from the user.
     */
    function resetSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to set the collateral limit with permit.
     * @param limitInUsd Collateral limit in USD with 6 decimals.
     * @param signature Must be a valid signature from the user.
     */
    function setCollateralLimit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to set the spending limit with permit.
     * @notice This does not affect the used up amount and specify a new limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     * @param signature Must be a valid signature from the user.
     */
    function updateSpendingLimit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to receive funds from the user.
     * @param token Address of the token to receive.
     * @param amount Amount of the token to receive.
     */
    function receiveFunds(address token, uint256 amount) external;

    /**
     * @notice Function to receive funds with permit from the user.
     * @param owner Address of the owner of the token.
     * @param token Address of the token to receive.
     * @param amount Amount of the token to receive.
     * @param deadline Must be a timestamp in the future.
     * @param r Must be a valid r for the `secp256k1` signature from the user.
     * @param s Must be a valid s for the `secp256k1` signature from the user.
     * @param v Must be a valid v for the `secp256k1` signature from the user.
     */
    function receiveFundsWithPermit(
        address owner,
        address token,
        uint256 amount,
        uint256 deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
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
     * @notice The three recovery signers are: owner of the safe, ether fi signer, third party signer.
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
     * @notice Function to transfer tokens from the User Safe to EtherFiCash Safe.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only transfer supported tokens.
     * @param token Address of the token to transfer.
     * @param amount Amount of tokens to transfer.
     */
    function transfer(address token, uint256 amount) external;

    /**
     * @notice Function to add collateral to EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only transfer supported tokens.
     * @param token Address of token to transfer.
     * @param amount Amount of tokens to transfer.
     */
    function addCollateral(address token, uint256 amount) external;

    /**
     * @notice Function to add collateral to and borrow funds from EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only transfer supported tokens.
     * @param collateralToken Address of the collateral token.
     * @param collateralAmount Amount of the collateral token.
     * @param borrowToken Address of the borrow token.
     * @param borrowAmount Amount of the borrow token.
     */
    function addCollateralAndBorrow(
        address collateralToken,
        uint256 collateralAmount,
        address borrowToken,
        uint256 borrowAmount
    ) external;

    /**
     * @notice Function to borrow funds from EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @param token Address of token to borrow.
     * @param amount Amount of tokens to borrow.
     */
    function borrow(address token, uint256 amount) external;

    /**
     * @notice Function to repay funds to EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @param token Address of token to use for repayment. Can be USDC or the collateral tokens.
     * @param debtAmountInUsdc Amount of debt to be repaid in USDC.
     */
    function repay(address token, uint256 debtAmountInUsdc) external;

    /**
     * @notice Function to withdraw collateral from the Debt Manager.
     * @param  token Address of the collateral token to withdraw.
     * @param  amount Amount of the collateral token to withdraw.
     */
    function withdrawCollateralFromDebtManager(
        address token,
        uint256 amount
    ) external;

    /**
     * @notice Function to swap funds to output token and transfer it to EtherFiCash Safe.
     * @dev Can only be called by the EtherFi Cash Wallet.
     * @dev Can only swap to a supported token.
     * @param inputTokenToSwap Address of input token to swap.
     * @param outputToken Address of the output token of the swap.
     * @param inputAmountToSwap Amount of input token to swap.
     * @param outputMinAmount Min output amount of the output token to receive from the swap.
     * @param outputAmountToTransfer Amount of output token to send to the EtherFiCash Safe.
     * @param swapData Swap data received from the swapper API.
     */
    function swapAndTransfer(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 outputAmountToTransfer,
        bytes calldata swapData
    ) external;
}
