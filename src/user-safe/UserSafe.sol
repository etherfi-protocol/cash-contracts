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
import {IUserSafe} from "../interfaces/IUserSafe.sol";

/**
 * @title UserSafe
 * @author ether.fi [shivam@ether.fi]
 * @notice User safe account for interactions with the EtherFi Cash contracts
 */
contract UserSafe is IUserSafe, Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;

    bytes32 public constant REQUEST_WITHDRAWAL_METHOD =
        keccak256("requestWithdrawal");
    bytes32 public constant APPROVE_METHOD = keccak256("approve");
    bytes32 public constant RESET_SPENDING_LIMIT_METHOD =
        keccak256("resetSpendingLimit");
    bytes32 public constant UPDATE_SPENDING_LIMIT_METHOD =
        keccak256("updateSpendingLimit");

    // Address of the USDC token
    address private immutable _usdc;
    // Address of the weETH token
    address private immutable _weETH;
    // Address of the Cash Data Provider
    ICashDataProvider private immutable _cashDataProvider;
    // Address of the price provider
    IPriceProvider private immutable _priceProvider;
    // Address of the swapper
    ISwapper private immutable _swapper;
    // Withdrawal requests pending with the contract
    WithdrawalRequest private _pendingWithdrawalRequest;
    // Funds blocked for withdrawal
    mapping(address token => uint256 amount) private blockedFundsForWithdrawal;
    // Nonce for permit operations
    uint256 private _nonce;
    // Current spending limit
    SpendingLimitData private _spendingLimit;

    constructor(address __cashDataProvider) {
        _cashDataProvider = ICashDataProvider(__cashDataProvider);
        _usdc = _cashDataProvider.usdc();
        _weETH = _cashDataProvider.weETH();
        _priceProvider = IPriceProvider(_cashDataProvider.priceProvider());
        _swapper = ISwapper(_cashDataProvider.swapper());
    }

    function initialize(
        address _owner,
        uint256 _defaultSpendingLimit
    ) external initializer {
        __Ownable_init(_owner);
        _resetSpendingLimit(
            uint8(SpendingLimitTypes.Monthly),
            _defaultSpendingLimit
        );
    }

    /**
     * @inheritdoc IUserSafe
     */
    function usdc() external view returns (address) {
        return _usdc;
    }

    /**
     * @inheritdoc IUserSafe
     */

    function weETH() external view returns (address) {
        return _weETH;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function cashDataProvider() external view returns (address) {
        return address(_cashDataProvider);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function priceProvider() external view returns (address) {
        return address(_priceProvider);
    }

    /**
     * @inheritdoc IUserSafe
     */

    function swapper() external view returns (address) {
        return address(_swapper);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function pendingWithdrawalRequest()
        public
        view
        returns (WithdrawalData memory)
    {
        address[] memory tokens = _pendingWithdrawalRequest.tokens;
        if (tokens.length == 0) {
            WithdrawalData memory withdrawalData;
            return withdrawalData;
        }

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
     * @inheritdoc IUserSafe
     */
    function nonce() external view returns (uint256) {
        return _nonce;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function spendingLimit() external view returns (SpendingLimitData memory) {
        return _spendingLimit;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function applicableSpendingLimit()
        external
        view
        returns (SpendingLimitData memory)
    {
        SpendingLimitData memory _applicableSpendingLimit = _spendingLimit;

        // If spending limit needs to be renewed, then renew it
        if (block.timestamp > _applicableSpendingLimit.renewalTimestamp) {
            _applicableSpendingLimit.usedUpAmount = 0;
            _applicableSpendingLimit
                .renewalTimestamp = _getSpendingLimitRenewalTimestamp(
                _applicableSpendingLimit.renewalTimestamp,
                _applicableSpendingLimit.spendingLimitType
            );
        }

        return _applicableSpendingLimit;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function resetSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) external onlyOwner {
        _resetSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function resetSpendingLimitWithPermit(
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
                RESET_SPENDING_LIMIT_METHOD,
                spendingLimitType,
                limitInUsd,
                userNonce
            )
        );

        msgHash.verifySig(owner(), r, s, v);
        _resetSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function updateSpendingLimit(uint256 limitInUsd) external onlyOwner {
        _updateSpendingLimit(limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function updateSpendingLimitWithPermit(
        uint256 limitInUsd,
        uint256 userNonce,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        _nonce++;
        if (userNonce != _nonce) revert InvalidNonce();

        bytes32 msgHash = keccak256(
            abi.encode(UPDATE_SPENDING_LIMIT_METHOD, limitInUsd, userNonce)
        );

        msgHash.verifySig(owner(), r, s, v);
        _updateSpendingLimit(limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function receiveFunds(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositFunds(token, amount);
    }

    /**
     * @inheritdoc IUserSafe
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
     * @inheritdoc IUserSafe
     */
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwner {
        _approve(token, spender, amount);
    }

    /**
     * @inheritdoc IUserSafe
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
     * @inheritdoc IUserSafe
     */
    function requestWithdrawal(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) external onlyOwner {
        _requestWithdrawal(tokens, amounts, recipient);
    }

    /**
     * @inheritdoc IUserSafe
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
     * @inheritdoc IUserSafe
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
     * @inheritdoc IUserSafe
     */
    function transfer(
        address token,
        uint256 amount
    ) external onlyEtherFiCashSafe {
        if (token != _usdc) revert UnsupportedToken();
        _checkSpendingLimit(token, amount);

        if (
            amount + blockedFundsForWithdrawal[token] >
            IERC20(token).balanceOf(address(this))
        ) revert InsufficientBalance();

        IERC20(token).safeTransfer(msg.sender, amount);
        emit TransferForSpending(token, amount);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function transferFundsToDebtManager(
        address token,
        uint256 amount
    ) external onlyEtherFiCashDebtManager {
        if (token != _weETH) revert UnsupportedToken();
        _checkSpendingLimit(token, amount);

        if (
            amount + blockedFundsForWithdrawal[token] >
            IERC20(token).balanceOf(address(this))
        ) revert InsufficientBalance();

        IERC20(token).safeTransfer(msg.sender, amount);
        emit TransferCollateral(token, amount);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function swapAndTransfer(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        uint256 outputAmountToTransfer,
        bytes calldata swapData
    ) external onlyEtherFiCashSafe {
        if (inputTokenToSwap != _weETH || outputToken != _usdc)
            revert UnsupportedToken();

        _checkSpendingLimit(outputToken, outputAmountToTransfer);

        if (
            inputAmountToSwap + blockedFundsForWithdrawal[_weETH] >
            IERC20(_weETH).balanceOf(address(this))
        ) revert InsufficientBalance();

        uint256 returnAmount = _swapFunds(
            inputTokenToSwap,
            outputToken,
            inputAmountToSwap,
            outputMinAmount,
            swapData
        );

        if (outputAmountToTransfer > returnAmount)
            revert TransferAmountGreaterThanReceived();

        IERC20(outputToken).safeTransfer(msg.sender, outputAmountToTransfer);

        emit SwapTransferForSpending(
            inputTokenToSwap,
            inputAmountToSwap,
            outputToken,
            outputAmountToTransfer
        );
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
        else if (spendingLimitType == SpendingLimitTypes.Yearly)
            return startTimestamp + 365 * 24 * 60 * 60;
        else revert InvalidSpendingLimitType();
    }

    function _swapFunds(
        address inputTokenToSwap,
        address outputToken,
        uint256 inputAmountToSwap,
        uint256 outputMinAmount,
        bytes calldata swapData
    ) internal returns (uint256) {
        IERC20(inputTokenToSwap).safeTransfer(
            address(_swapper),
            inputAmountToSwap
        );
        return
            _swapper.swap(
                inputTokenToSwap,
                outputToken,
                inputAmountToSwap,
                outputMinAmount,
                swapData
            );
    }

    function _resetSpendingLimit(
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

        emit ResetSpendingLimit(spendingLimitType, limitInUsd);
    }

    function _updateSpendingLimit(uint256 limitInUsd) internal {
        emit UpdateSpendingLimit(_spendingLimit.spendingLimit, limitInUsd);
        _spendingLimit.spendingLimit = limitInUsd;
    }

    function _requestWithdrawal(
        address[] memory tokens,
        uint256[] memory amounts,
        address recipient
    ) internal {
        _cancelOldWithdrawal();

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
            _cashDataProvider.withdrawalDelay();

        _pendingWithdrawalRequest = WithdrawalRequest({
            tokens: tokens,
            recipient: recipient,
            finalizeTime: finalTime
        });

        emit WithdrawalRequested(tokens, amounts, recipient, finalTime);
    }

    function _cancelOldWithdrawal() internal {
        uint256 oldDataLen = _pendingWithdrawalRequest.tokens.length;
        if (oldDataLen != 0) {
            address[] memory oldTokens = _pendingWithdrawalRequest.tokens;
            uint256[] memory oldAmounts = new uint256[](oldTokens.length);

            for (uint256 i = 0; i < oldDataLen; ) {
                oldAmounts[i] = blockedFundsForWithdrawal[oldTokens[i]];
                delete blockedFundsForWithdrawal[oldTokens[i]];
                unchecked {
                    ++i;
                }
            }

            emit WithdrawalCancelled(
                oldTokens,
                oldAmounts,
                _pendingWithdrawalRequest.recipient
            );

            delete _pendingWithdrawalRequest;
        }
    }

    function _approve(address token, address spender, uint256 amount) internal {
        IERC20(token).approve(spender, amount);
        emit ApprovalFunds(token, spender, amount);
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        // If spending limit needs to be renewed, then renew it
        if (block.timestamp > _spendingLimit.renewalTimestamp) {
            _spendingLimit.usedUpAmount = 0;
            _spendingLimit.renewalTimestamp = _getSpendingLimitRenewalTimestamp(
                _spendingLimit.renewalTimestamp,
                _spendingLimit.spendingLimitType
            );
        }

        // in current case, token can be either weETH or USDC only
        if (token == _weETH) {
            uint256 price = _priceProvider.getWeEthUsdPrice();
            // amount * price with 6 decimals / 1 ether will convert the weETH amount to USD amount with 6 decimals
            amount = (amount * price) / 1 ether;
        }

        if (amount + _spendingLimit.usedUpAmount > _spendingLimit.spendingLimit)
            revert ExceededSpendingLimit();

        _spendingLimit.usedUpAmount += amount;
    }

    function _onlyEtherFiCashSafe() private view {
        if (msg.sender != _cashDataProvider.etherFiCashMultiSig())
            revert UnauthorizedCall();
    }

    function _onlyEtherFiCashDebtManager() private view {
        if (msg.sender != _cashDataProvider.etherFiCashDebtManager())
            revert UnauthorizedCall();
    }

    modifier onlyEtherFiCashSafe() {
        _onlyEtherFiCashSafe();
        _;
    }

    modifier onlyEtherFiCashDebtManager() {
        _onlyEtherFiCashDebtManager();
        _;
    }
}
