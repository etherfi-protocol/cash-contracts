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

    struct FundsDetails {
        address token;
        uint256 amount;
    }

    struct WithdrawalRequest {
        address[] tokens;
        address recipient;
        uint96 finalizeTime;
    }

    struct WithdrawalData {
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

    event DepositFunds(address token, uint256 amount);
    event ApprovalFunds(address token, address spender, uint256 amount);
    event WithdrawalRequested(
        address[] tokens,
        uint256[] amounts,
        address recipient,
        uint256 finalizeTimestamp
    );
    event WithdrawalCancelled(
        address[] tokens,
        uint256[] amounts,
        address recipient
    );
    event WithdrawalProcessed(
        address[] tokens,
        uint256[] amounts,
        address recipient
    );
    event TransferForSpending(address token, uint256 amount);
    event SwapTransferForSpending(
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputTokenSent
    );
    event TransferCollateral(address token, uint256 amount);
    event ResetSpendingLimit(uint8 spendingLimitType, uint256 limitInUsd);
    event UpdateSpendingLimit(uint256 oldLimitInUsd, uint256 newLimitInUsd);
    event IsRecoveryActiveSet(bool isActive);
    event UserSafeRecovered(
        OwnerLib.OwnerObject owner,
        FundsDetails[] fundsDetails
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
    error InvalidSpendingLimitType();
    error UnsupportedToken();
    error RecoveryNotActive();
    error InvalidSignatureIndex();
    error SignatureIndicesCannotBeSame();

    /**
     * @notice Function to fetch the owner bytes for the User Safe.
     * @return owner bytes of the User Safe.
     */
    function ownerBytes() external view returns (bytes memory);

    /**
     * @notice Function to fetch the address of the owner of the User Safe.
     * @return address of the owner of the User Safe.
     */
    function owner() external view returns (OwnerLib.OwnerObject memory);

    /**
     * @notice Function to fetch the contract address of the USDC token.
     * @return contract address of the USDC token.
     */
    function usdc() external view returns (address);

    /**
     * @notice Function to fetch the contract address of the weETH token.
     * @return contract address of the weETH token.
     */
    function weETH() external view returns (address);

    /**
     * @notice Function to fetch the contract address of the Cash Data Provider.
     * @return contract address of the Cash Data Provider.
     */
    function cashDataProvider() external view returns (address);

    /**
     * @notice Function to fetch the contract address of the Price Provider.
     * @return contract address of the Price Provider.
     */
    function priceProvider() external view returns (address);

    /**
     * @notice Function to fetch the contract address of the Swapper.
     * @return contract address of the Swapper.
     */
    function swapper() external view returns (address);

    /**
     * @notice Function to fetch the pending withdrawal request.
     * @return WithdrawalData struct.
     */
    function pendingWithdrawalRequest()
        external
        view
        returns (WithdrawalData memory);

    /**
     * @notice Function to fetch the current nonce.
     * @return Nonce
     */
    function nonce() external view returns (uint256);

    /**
     * @notice Function to fetch whether the recovery is active.
     */
    function isRecoveryActive() external view returns (bool);

    /**
     * @notice Function to fetch the contract address of the EtherFi Recovery safe.
     * @return contract address of the EtherFi Recovery safe.
     */
    function etherFiRecoverySafe() external view returns (address);

    /**
     * @notice Function to fetch the recovery signers.
     * @return Array of recovery signers.
     */
    function recoverySigners()
        external
        view
        returns (OwnerLib.OwnerObject[3] memory);

    /**
     * @notice Function to get the spending limit for the user.
     * @return SpendingLimitData struct.
     */
    function spendingLimit() external view returns (SpendingLimitData memory);

    /**
     * @notice Function to get the current applicable spending limit.
     * @notice This function gives renewed limit as well based on if the renewal timestamp is in the past.
     * @return Current applicable spending limit
     */
    function applicableSpendingLimit()
        external
        view
        returns (SpendingLimitData memory);

    /**
     * @notice Function to set the owner of the contract.
     * @dev Can only be called by the owner if it is an Ethereum address.
     * @dev If owner is a passkey, setOwnerWithPermit should be called to set the new owner.
     * @param __owner Address of the new owner
     */
    function setOwner(bytes calldata __owner) external;

    /**
     * @notice Function to set the owner of the contract.
     * @param __owner Address of the new owner
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signature Must be a valid signature from the user.
     */
    function setOwnerWithPermit(
        bytes calldata __owner,
        uint256 userNonce,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to set the spending limit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     */
    function resetSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) external;

    /**
     * @notice Function to set the spending limit with permit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signature Must be a valid signature from the user.
     */
    function resetSpendingLimitWithPermit(
        uint8 spendingLimitType,
        uint256 limitInUsd,
        uint256 userNonce,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to update the spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     */
    function updateSpendingLimit(uint256 limitInUsd) external;

    /**
     * @notice Function to set the spending limit with permit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signature Must be a valid signature from the user.
     */
    function updateSpendingLimitWithPermit(
        uint256 limitInUsd,
        uint256 userNonce,
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
     * @notice Function to approve spendings of funds from this contract.
     * @param token Address of the token.
     * @param spender Address of the spender.
     * @param amount Amount of tokens to grant approval for.
     */
    function approve(address token, address spender, uint256 amount) external;
    /**
     * @notice Function to approve spendings of funds with permit from this contract.
     * @param token Address of the token.
     * @param spender Address of the spender.
     * @param amount Amount of tokens to grant approval for.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signature Must be a valid signature from the user.
     */
    function approveWithPermit(
        address token,
        address spender,
        uint256 amount,
        uint256 userNonce,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to request withdrawal of funds from this safe.
     * @notice Can be withdrawn with a configurable delay.
     * @param tokens Address of the tokens to withdraw.
     * @param amounts Amount of the tokens to withdraw.
     * @param recipient Address of the recipient of funds.
     */
    function requestWithdrawal(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient
    ) external;

    /**
     * @notice Function to request withdrawal of funds with permit from this safe.
     * @notice Can be withdrawn with a configurable delay.
     * @param tokens Address of the tokens to withdraw.
     * @param amounts Amount of the tokens to withdraw.
     * @param recipient Address of the recipient of funds.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signature Must be a valid signature from the user.
     */
    function requestWithdrawalWithPermit(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        uint256 userNonce,
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
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signatures Array of the signature struct containing any 2 out of 3 signers' signatures.
     * @param tokensToPull Array of the toen addresses to be recovered.
     */
    function recoverUserSafe(
        uint256 userNonce,
        Signature[2] calldata signatures,
        address[] calldata tokensToPull
    ) external;

    /**
     * @notice Function to set _isRecoveryActive boolean.
     */
    function setIsRecoveryActive(bool isRecoveryActive) external;

    /**
     * @notice Function to set _isRecoveryActive boolean with permit.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param signature Must be a valid signature from the user.
     */
    function setIsRecoveryActiveWithPermit(
        bool isRecoveryActive,
        uint256 userNonce,
        bytes calldata signature
    ) external;

    /**
     * @notice Function to transfer tokens from the User Safe to EtherFiCash Safe.
     * @dev Can only be called by the EtherFiCash Safe.
     * @dev Can only transfer supported tokens.
     * @param token Address of the token to transfer.
     * @param amount Amount of tokens to transfer.
     */
    function transfer(address token, uint256 amount) external;

    /**
     * @notice Function to transfer funds from the User Safe to EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFiCash Debt Manager.
     * @dev Can only transfer supported tokens.
     * @param token Address of token to transfer.
     * @param amount Amount of tokens to transfer.
     */
    function transferFundsToDebtManager(address token, uint256 amount) external;

    /**
     * @notice Function to swap funds to output token and transfer it to EtherFiCash Safe.
     * @dev Can only be called by the EtherFiCash Safe.
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
