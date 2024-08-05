// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @title UserSafe
 * @author ether.fi [shivam@ether.fi]
 * @notice User safe account for interactions with the EtherFi Cash contracts
 */
contract UserSafe is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;

    enum SpendingLimitTypes {
        Daily,
        Weekly,
        Monthly,
        Yearly
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

    bytes32 public constant REQUEST_WITHDRAWAL_METHOD =
        keccak256("requestWithdrawal");
    bytes32 public constant APPROVE_METHOD = keccak256("approve");
    bytes32 public constant SET_SPENDING_LIMIT_METHOD =
        keccak256("setSpendingLimit");
    bytes32 public constant SET_INCOMING_SPENDING_LIMIT_METHOD =
        keccak256("setIncomingSpendingLimit");

    // Address of the USDC token
    address public immutable usdc;
    // Address of the weETH token
    address public immutable weETH;
    // Address of the Cash Data Provider
    ICashDataProvider public immutable cashDataProvider;
    // Address of the price provider
    IPriceProvider public immutable priceProvider;
    // Address of the swapper
    ISwapper public immutable _swapper;
    // Withdrawal requests pending with the contract
    WithdrawalRequest private _pendingWithdrawalRequest;
    // Funds blocked for withdrawal
    mapping(address token => uint256 amount) private blockedFundsForWithdrawal;
    // Nonce for permit operations
    uint256 private _nonce;
    // Current spending limit
    SpendingLimitData private _spendingLimit;
    // This spending limit gets activated once the _spendingLimit time is over
    SpendingLimitData private _incomingSpendingLimit;

    event DepositFunds(address token, uint256 amount);
    event ApprovalFunds(address token, address spender, uint256 amount);
    event WithdrawalRequested(
        address[] tokens,
        uint256[] amounts,
        address recipient,
        uint256 finalizeTimestamp
    );
    event WithdrawalProcessed(
        address[] tokens,
        uint256[] amounts,
        address recipient
    );
    event TransferUSDCForSpending(uint256 amount);
    event SwapTransferForSpending(uint256 weETHAmount, uint256 usdcAmount);
    event TransferWeETHAsCollateral(uint256 amount);
    event SetSpendingLimit(uint8 spendingLimitType, uint256 limitInUsd);
    event SetIncomingSpendingLimit(uint8 spendingLimitType, uint256 limitInUsd);

    error InsufficientBalance();
    error ArrayLengthMismatch();
    error CannotWithdrawYet();
    error UnauthorizedCall();
    error InvalidNonce();
    error AmountGreaterThanUsdcReceived();
    error ExceededSpendingLimit();

    constructor(
        address _usdc,
        address _weETH,
        address _priceProvider,
        address _cashDataProvider,
        address __swapper
    ) {
        usdc = _usdc;
        weETH = _weETH;
        priceProvider = IPriceProvider(_priceProvider);
        cashDataProvider = ICashDataProvider(_cashDataProvider);
        _swapper = ISwapper(__swapper);
    }

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    /**
     * @notice Function to fetch the pending withdrawal request.
     * @return WithdrawalData struct.
     */
    function pendingWithdrawalRequest()
        external
        view
        returns (WithdrawalData memory)
    {
        address[] memory tokens = _pendingWithdrawalRequest.tokens;
        uint256[] memory amounts = new uint256[](tokens.length);
        address recipient = _pendingWithdrawalRequest.recipient;
        uint256 len = tokens.length;

        for (uint256 i = 0; i < len; ) {
            amounts[i] = blockedFundsForWithdrawal[tokens[i]];
            unchecked {
                ++i;
            }
        }

        return
            WithdrawalData({
                tokens: tokens,
                amounts: amounts,
                recipient: recipient,
                finalizeTime: _pendingWithdrawalRequest.finalizeTime
            });
    }

    /**
     * @notice Function to fetch the address of the Swapper contract.
     * @return Address of the Swapper contract.
     */
    function swapper() external view returns (address) {
        return address(_swapper);
    }

    function nonce() external view returns (uint256) {
        return _nonce;
    }

    /**
     * @notice Function to get the spending limit for the user.
     * @return SpendingLimitData struct.
     */
    function applicableSpendingLimit()
        external
        view
        returns (SpendingLimitData memory)
    {
        if (block.timestamp < _spendingLimit.renewalTimestamp)
            return _spendingLimit;
        else {
            if (_incomingSpendingLimit.renewalTimestamp > block.timestamp) {
                return _incomingSpendingLimit;
            } else {
                SpendingLimitData memory spendingLimitData;
                spendingLimitData.usedUpAmount = 0;
                spendingLimitData
                    .renewalTimestamp = _getSpendingLimitRenewalTimestamp(
                    _spendingLimit.renewalTimestamp,
                    _spendingLimit.spendingLimitType
                );
                spendingLimitData.spendingLimit = _spendingLimit.spendingLimit;
                spendingLimitData.spendingLimitType = _spendingLimit
                    .spendingLimitType;

                return spendingLimitData;
            }
        }
    }

    /**
     * @notice Function to get the spending limit for the user.
     * @return SpendingLimitData struct.
     */
    function spendingLimit() external view returns (SpendingLimitData memory) {
        return _spendingLimit;
    }

    /**
     * @notice Function to get the incoming spending limit for the user.
     * @return SpendingLimitData struct.
     */
    function incomingSpendingLimit()
        external
        view
        returns (SpendingLimitData memory)
    {
        return _incomingSpendingLimit;
    }

    /**
     * @notice Function to set the spending limit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     */
    function setSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) external onlyOwner {
        _setSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @notice Function to set the spending limit with permit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param r Must be a valid r for the `secp256k1` signature from the user.
     * @param s Must be a valid s for the `secp256k1` signature from the user.
     * @param v Must be a valid v for the `secp256k1` signature from the user.
     */
    function setSpendingLimitWithPermit(
        uint8 spendingLimitType,
        uint256 limitInUsd,
        uint256 userNonce,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        _nonce++;
        if (userNonce != _nonce) revert InvalidNonce();

        bytes32 msgHash = keccak256(
            abi.encode(
                SET_SPENDING_LIMIT_METHOD,
                spendingLimitType,
                limitInUsd,
                userNonce
            )
        );

        msgHash.verifySig(owner(), r, s, v);
        _setSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @notice Function to set the incoming spending limit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     */
    function setIncomingSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) external onlyOwner {
        _setIncomingSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @notice Function to set the incoming spending limit with permit.
     * @param spendingLimitType Type of spending limit.
     * @param limitInUsd Spending limit in USD with 6 decimals.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param r Must be a valid r for the `secp256k1` signature from the user.
     * @param s Must be a valid s for the `secp256k1` signature from the user.
     * @param v Must be a valid v for the `secp256k1` signature from the user.
     */
    function setIncomingSpendingLimitWithPermit(
        uint8 spendingLimitType,
        uint256 limitInUsd,
        uint256 userNonce,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        _nonce++;
        if (userNonce != _nonce) revert InvalidNonce();

        bytes32 msgHash = keccak256(
            abi.encode(
                SET_INCOMING_SPENDING_LIMIT_METHOD,
                spendingLimitType,
                limitInUsd,
                userNonce
            )
        );

        msgHash.verifySig(owner(), r, s, v);
        _setIncomingSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @notice Function to receive funds from the user.
     * @param token Address of the token to receive.
     * @param amount Amount of the token to receive.
     */
    function receiveFunds(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositFunds(token, amount);
    }

    /**
     * @notice Function to receive funds with permit from the user.
     * @param owner Address of the owner of the token.
     * @param token Address of the token to receive.
     * @param amount Amount of the token to receive.
     * @param deadline Must be a timestamp in the future.
     * @param r Must be a valid r for the `secp256k1` signature from the user.
     * @param s Must be a valid s for the `secp256k1` signature from the user.
     * @param v Must be a valid v for the `secp256k1` signature from the user.
     *
     */
    function receiveFundsWithPermit(
        address owner,
        address token,
        uint256 amount,
        uint256 deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        try
            IERC20Permit(token).permit(
                owner,
                address(this),
                amount,
                deadline,
                v,
                r,
                s
            )
        {} catch {}

        IERC20(token).safeTransferFrom(owner, address(this), amount);
        emit DepositFunds(token, amount);
    }

    /**
     * @notice Function to approve spendings of funds from this contract.
     * @param token Address of the token.
     * @param spender Address of the spender.
     * @param amount Amount of tokens to grant approval for.
     */
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwner {
        _approve(token, spender, amount);
    }

    /**
     * @notice Function to approve spendings of funds with permit from this contract.
     * @param token Address of the token.
     * @param spender Address of the spender.
     * @param amount Amount of tokens to grant approval for.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param r Must be a valid r for the `secp256k1` signature from the user.
     * @param s Must be a valid s for the `secp256k1` signature from the user.
     * @param v Must be a valid v for the `secp256k1` signature from the user.
     */
    function approveWithPermit(
        address token,
        address spender,
        uint256 amount,
        uint256 userNonce,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        _nonce++;
        if (userNonce != _nonce) revert InvalidNonce();

        bytes32 msgHash = keccak256(
            abi.encode(APPROVE_METHOD, token, spender, amount, userNonce)
        );

        msgHash.verifySig(owner(), r, s, v);
        _approve(token, spender, amount);
    }

    /**
     * @notice Function to request withdrawal of funds from this safe.
     * @notice Can be withdrawn with a configurable delay.
     * @param tokens Address of the tokens to withdraw.
     * @param amounts Amount of the tokens to withdraw.
     * @param recipient Address of the recipient of funds.
     */
    function requestWithdrawal(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) external onlyOwner {
        _requestWithdrawal(tokens, amounts, recipient);
    }

    /**
     * @notice Function to request withdrawal of funds with permit from this safe.
     * @notice Can be withdrawn with a configurable delay.
     * @param tokens Address of the tokens to withdraw.
     * @param amounts Amount of the tokens to withdraw.
     * @param recipient Address of the recipient of funds.
     * @param userNonce Nonce for this call. Must be equal to current nonce.
     * @param r Must be a valid r for the `secp256k1` signature from the user.
     * @param s Must be a valid s for the `secp256k1` signature from the user.
     * @param v Must be a valid v for the `secp256k1` signature from the user.
     */
    function requestWithdrawalWithPermit(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient,
        uint256 userNonce,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        _nonce++;
        if (userNonce != _nonce) revert InvalidNonce();
        bytes32 msgHash = keccak256(
            abi.encode(
                REQUEST_WITHDRAWAL_METHOD,
                tokens,
                amounts,
                recipient,
                userNonce
            )
        );

        msgHash.verifySig(owner(), r, s, v);

        _requestWithdrawal(tokens, amounts, recipient);
    }

    /**
     * @notice Function to process pending withdrawal post the delay.
     * @dev Can be called by any wallet.
     */
    function processWithdrawal() external {
        if (_pendingWithdrawalRequest.finalizeTime > block.timestamp)
            revert CannotWithdrawYet();
        address[] memory tokens = _pendingWithdrawalRequest.tokens;
        uint256[] memory amounts = new uint256[](tokens.length);
        address recipient = _pendingWithdrawalRequest.recipient;
        uint256 len = tokens.length;

        for (uint256 i = 0; i < len; ) {
            amounts[i] = blockedFundsForWithdrawal[tokens[i]];
            IERC20(tokens[i]).safeTransfer(recipient, amounts[i]);

            unchecked {
                ++i;
            }
        }

        emit WithdrawalProcessed(tokens, amounts, recipient);
    }

    /**
     * @notice Function to transfer USDC from the User Safe to EtherFiCash Safe.
     * @dev Can only be called by the EtherFiCash Safe.
     * @param amount Amount of USDC to transfer.
     */
    function transfer(uint256 amount) external onlyEtherFiCashSafe {
        _checkSpendingLimit(usdc, amount);

        if (
            amount + blockedFundsForWithdrawal[usdc] >
            IERC20(usdc).balanceOf(address(this))
        ) revert InsufficientBalance();

        IERC20(usdc).safeTransfer(msg.sender, amount);
        emit TransferUSDCForSpending(amount);
    }

    /**
     * @notice Function to transfer WeETH from the User Safe to EtherFiCash Debt Manager.
     * @dev Can only be called by the EtherFiCash Debt Manager.
     * @param amount Amount of WeETH to transfer.
     */
    function transferWeETHToDebtManager(
        uint256 amount
    ) external onlyEtherFiCashDebtManager {
        _checkSpendingLimit(weETH, amount);

        if (
            amount + blockedFundsForWithdrawal[weETH] >
            IERC20(weETH).balanceOf(address(this))
        ) revert InsufficientBalance();

        IERC20(weETH).safeTransfer(msg.sender, amount);
        emit TransferWeETHAsCollateral(amount);
    }

    /**
     * @notice Function to swap WeETH to USDC and transfer it to EtherFiCash Safe.
     * @dev Can only be called by the EtherFiCash Safe.
     * @param amountWeETHToSwap Amount of WeETH to swap.
     * @param minUsdcAmount Min amount of USDC to receive from the swap.
     * @param amountUsdcToSend Amount of USDC to send to the EtherFiCash Safe.
     * @param swapData Swap data received from the swapper API.
     */
    function swapAndTransfer(
        uint256 amountWeETHToSwap,
        uint256 minUsdcAmount,
        uint256 amountUsdcToSend,
        bytes calldata swapData
    ) external onlyEtherFiCashSafe {
        if (
            amountWeETHToSwap + blockedFundsForWithdrawal[weETH] >
            IERC20(weETH).balanceOf(address(this))
        ) revert InsufficientBalance();

        uint256 returnAmount = _swapWeETHToUsdc(
            amountWeETHToSwap,
            minUsdcAmount,
            swapData
        );
        if (amountUsdcToSend > returnAmount)
            revert AmountGreaterThanUsdcReceived();

        _checkSpendingLimit(usdc, amountUsdcToSend);
        IERC20(usdc).safeTransfer(msg.sender, amountUsdcToSend);

        emit SwapTransferForSpending(amountWeETHToSwap, amountUsdcToSend);
    }

    function _getSpendingLimitRenewalTimestamp(
        uint64 startTimestamp,
        SpendingLimitTypes spendingLimitType
    ) internal pure returns (uint64 renewalTimestamp) {
        if (spendingLimitType == SpendingLimitTypes.Daily)
            return startTimestamp + 24 * 60 * 60;
        else if (spendingLimitType == SpendingLimitTypes.Weekly)
            return startTimestamp + 7 * 24 * 60 * 60;
        else if (spendingLimitType == SpendingLimitTypes.Monthly)
            return startTimestamp + 30 * 24 * 60 * 60;
        else return startTimestamp + 365 * 24 * 60 * 60;
    }

    function _swapWeETHToUsdc(
        uint256 amount,
        uint256 minUsdcAmount,
        bytes calldata swapData
    ) internal returns (uint256) {
        IERC20(weETH).safeTransfer(address(_swapper), amount);
        return _swapper.swap(weETH, usdc, amount, minUsdcAmount, swapData);
    }

    function _setSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) internal {
        _spendingLimit = SpendingLimitData({
            spendingLimitType: SpendingLimitTypes(spendingLimitType),
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(
                uint64(block.timestamp),
                SpendingLimitTypes(spendingLimitType)
            ),
            spendingLimit: limitInUsd,
            usedUpAmount: 0
        });

        emit SetSpendingLimit(spendingLimitType, limitInUsd);
    }

    function _setIncomingSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) internal {
        _incomingSpendingLimit = SpendingLimitData({
            spendingLimitType: SpendingLimitTypes(spendingLimitType),
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(
                _spendingLimit.renewalTimestamp,
                SpendingLimitTypes(spendingLimitType)
            ),
            spendingLimit: limitInUsd,
            usedUpAmount: 0
        });

        emit SetIncomingSpendingLimit(spendingLimitType, limitInUsd);
    }

    function _requestWithdrawal(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) internal {
        uint256 len = tokens.length;
        if (len != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < len; ) {
            if (IERC20(tokens[i]).balanceOf(address(this)) < amounts[i])
                revert InsufficientBalance();
            blockedFundsForWithdrawal[tokens[i]] = amounts[i];

            unchecked {
                ++i;
            }
        }

        uint96 finalTime = uint96(block.timestamp) +
            cashDataProvider.withdrawalDelay();

        _pendingWithdrawalRequest = WithdrawalRequest({
            tokens: tokens,
            recipient: recipient,
            finalizeTime: finalTime
        });

        emit WithdrawalRequested(
            tokens,
            amounts,
            recipient,
            block.timestamp + cashDataProvider.withdrawalDelay()
        );
    }

    function _approve(address token, address spender, uint256 amount) internal {
        IERC20(token).approve(spender, amount);
        emit ApprovalFunds(token, spender, amount);
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        // If spending limit needs to be renewed, then renew it
        if (block.timestamp > _spendingLimit.renewalTimestamp) {
            if (_incomingSpendingLimit.renewalTimestamp > block.timestamp) {
                _spendingLimit = _incomingSpendingLimit;
                delete _incomingSpendingLimit;
            } else {
                _spendingLimit.usedUpAmount = 0;
                _spendingLimit
                    .renewalTimestamp = _getSpendingLimitRenewalTimestamp(
                    _spendingLimit.renewalTimestamp,
                    _spendingLimit.spendingLimitType
                );
            }
        }

        // in current case, token can be either weETH or USDC only
        if (token == weETH) {
            uint256 price = priceProvider.getWeEthUsdPrice();
            // amount * price with 6 decimals / 1 ether will convert the weETH amount to USD amount with 6 decimals
            amount = (amount * price) / 1 ether;
        }

        if (amount + _spendingLimit.usedUpAmount > _spendingLimit.spendingLimit)
            revert ExceededSpendingLimit();

        _spendingLimit.usedUpAmount += amount;
    }

    modifier onlyEtherFiCashSafe() {
        if (msg.sender != cashDataProvider.etherFiCashMultiSig())
            revert UnauthorizedCall();
        _;
    }

    modifier onlyEtherFiCashDebtManager() {
        if (msg.sender != cashDataProvider.etherFiCashDebtManager())
            revert UnauthorizedCall();
        _;
    }
}
