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
import {UserSafeRecovery} from "./UserSafeRecovery.sol";
import {WebAuthn} from "../libraries/WebAuthn.sol";
import {OwnerLib} from "../libraries/OwnerLib.sol";
import {UserSafeLib} from "../libraries/UserSafeLib.sol";

/**
 * @title UserSafe
 * @author ether.fi [shivam@ether.fi]
 * @notice User safe account for interactions with the EtherFi Cash contracts
 */
contract UserSafe is IUserSafe, Initializable, UserSafeRecovery {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;
    using OwnerLib for bytes;
    using UserSafeLib for OwnerLib.OwnerObject;

    // Address of the Cash Data Provider
    ICashDataProvider private immutable _cashDataProvider;

    // Owner: if ethAddr -> abi.encode(owner), if passkey -> abi.encode(x,y)
    bytes private _ownerBytes;
    // Withdrawal requests pending with the contract
    WithdrawalRequest private _pendingWithdrawalRequest;
    // Nonce for permit operations
    uint256 private _nonce;
    // Current spending limit
    SpendingLimitData private _spendingLimit;
    // Collateral limit
    uint256 private _collateralLimit;

    // Incoming spending limit -> we want a delay between spending limit changes so we can deduct funds in between to settle account
    SpendingLimitData private _incomingSpendingLimit;
    // Incoming spending limit start timestamp
    uint256 _incomingSpendingLimitStartTime;
    // Incoming collateral limit -> we want a delay between collateral limit changes so we can deduct funds in between to settle account
    uint256 private _incomingCollateralLimit;
    // Incoming collateral limit start timestamp
    uint256 private _incomingCollateralLimitStartTime;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address __cashDataProvider,
        address __etherFiRecoverySigner,
        address __thirdPartyRecoverySigner
    ) UserSafeRecovery(__etherFiRecoverySigner, __thirdPartyRecoverySigner) {
        _cashDataProvider = ICashDataProvider(__cashDataProvider);
        _disableInitializers();
    }

    function initialize(
        bytes calldata __owner,
        uint256 __spendingLimit,
        uint256 __collateralLimit
    ) external initializer {
        _ownerBytes = __owner;

        _spendingLimit = SpendingLimitData({
            spendingLimitType: SpendingLimitTypes(SpendingLimitTypes.Monthly),
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(
                uint64(block.timestamp),
                SpendingLimitTypes.Monthly
            ),
            spendingLimit: __spendingLimit,
            usedUpAmount: 0
        });

        _collateralLimit = __collateralLimit;

        __UserSafeRecovery_init();
    }

    /**
     * @inheritdoc IUserSafe
     */
    function owner() public view returns (OwnerLib.OwnerObject memory) {
        return _ownerBytes.getOwnerObject();
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
    function pendingWithdrawalRequest()
        public
        view
        returns (WithdrawalRequest memory)
    {
        return _pendingWithdrawalRequest;
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
    function applicableSpendingLimit()
        external
        view
        returns (SpendingLimitData memory)
    {
        SpendingLimitData memory _applicableSpendingLimit;
        if (
            _incomingSpendingLimitStartTime != 0 &&
            block.timestamp > _incomingSpendingLimitStartTime
        ) _applicableSpendingLimit = _incomingSpendingLimit;
        else _applicableSpendingLimit = _spendingLimit;

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
    function applicableCollateralLimit() external view returns (uint256) {
        if (
            _incomingCollateralLimitStartTime > 0 &&
            block.timestamp > _incomingCollateralLimitStartTime
        ) return _incomingCollateralLimit;

        return _collateralLimit;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setOwner(
        bytes calldata __owner,
        bytes calldata signature
    ) external incrementNonce {
        owner().verifySetOwnerSig(_nonce, __owner, signature);
        _setOwner(__owner);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function resetSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd,
        bytes calldata signature
    ) external incrementNonce {
        owner().verifyResetSpendingLimitSig(
            _nonce,
            spendingLimitType,
            limitInUsd,
            signature
        );
        _resetSpendingLimit(spendingLimitType, limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function updateSpendingLimit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external incrementNonce {
        owner().verifyUpdateSpendingLimitSig(_nonce, limitInUsd, signature);
        _updateSpendingLimit(limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setCollateralLimit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external incrementNonce {
        owner().verifySetCollateralLimitSig(_nonce, limitInUsd, signature);
        _setCollateralLimit(limitInUsd);
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
        address fundsOwner,
        address token,
        uint256 amount,
        uint256 deadline,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        try
            IERC20Permit(token).permit(
                fundsOwner,
                address(this),
                amount,
                deadline,
                v,
                r,
                s
            )
        {} catch {}

        IERC20(token).safeTransferFrom(fundsOwner, address(this), amount);
        emit DepositFunds(token, amount);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function requestWithdrawal(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata signature
    ) external incrementNonce {
        owner().verifyRequestWithdrawalSig(
            _nonce,
            tokens,
            amounts,
            recipient,
            signature
        );
        _requestWithdrawal(tokens, amounts, recipient);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function processWithdrawal() external {
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

        emit WithdrawalProcessed(
            _pendingWithdrawalRequest.tokens,
            _pendingWithdrawalRequest.amounts,
            recipient
        );

        delete _pendingWithdrawalRequest;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setIsRecoveryActive(
        bool isActive,
        bytes calldata signature
    ) external incrementNonce {
        _setIsRecoveryActive(isActive, _nonce, signature);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function recoverUserSafe(
        bytes calldata newOwner,
        Signature[2] calldata signatures
    ) external onlyWhenRecoveryActive incrementNonce {
        _recoverUserSafe(_nonce, signatures, newOwner);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function transfer(
        address token,
        uint256 amount
    ) external onlyEtherFiWallet {
        if (!_isBorrowToken(token)) revert UnsupportedToken();

        _checkSpendingLimit(token, amount);
        _updateWithdrawalRequestIfNecessary(token, amount);

        IERC20(token).safeTransfer(
            _cashDataProvider.etherFiCashMultiSig(),
            amount
        );
        emit TransferForSpending(token, amount);
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
    ) external onlyEtherFiWallet {
        if (
            !_isCollateralToken(inputTokenToSwap) ||
            !_isBorrowToken(outputToken)
        ) revert UnsupportedToken();

        _checkSpendingLimit(outputToken, outputAmountToTransfer);
        _updateWithdrawalRequestIfNecessary(
            inputTokenToSwap,
            inputAmountToSwap
        );

        uint256 returnAmount = _swapFunds(
            inputTokenToSwap,
            outputToken,
            inputAmountToSwap,
            outputMinAmount,
            swapData
        );

        if (outputAmountToTransfer > returnAmount)
            revert TransferAmountGreaterThanReceived();

        IERC20(outputToken).safeTransfer(
            _cashDataProvider.etherFiCashMultiSig(),
            outputAmountToTransfer
        );

        emit SwapTransferForSpending(
            inputTokenToSwap,
            inputAmountToSwap,
            outputToken,
            outputAmountToTransfer
        );
    }

    /**
     * @inheritdoc IUserSafe
     */
    function addCollateral(
        address token,
        uint256 amount
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _addCollateral(debtManager, token, amount);
    }

    /**
     * @inheritdoc IUserSafe
     */
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

    /**
     * @inheritdoc IUserSafe
     */
    function borrow(address token, uint256 amount) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _borrow(debtManager, token, amount);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function repay(
        address token,
        uint256 repayDebtUsdcAmt
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _repay(debtManager, token, repayDebtUsdcAmt);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function withdrawCollateralFromDebtManager(
        address token,
        uint256 amount
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _withdrawCollateralFromDebtManager(debtManager, token, amount);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function closeAccountWithDebtManager() external onlyEtherFiWallet {
        IL2DebtManager(_cashDataProvider.etherFiCashDebtManager())
            .closeAccount();
        emit CloseAccountWithDebtManager();
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
                swapData
            );
    }

    function _resetSpendingLimit(
        uint8 spendingLimitType,
        uint256 limitInUsd
    ) internal {
        _currentSpendingLimit();

        uint256 startTime = block.timestamp + _cashDataProvider.delay();
        _incomingSpendingLimitStartTime = startTime;

        _incomingSpendingLimit = SpendingLimitData({
            spendingLimitType: SpendingLimitTypes(spendingLimitType),
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(
                uint64(startTime),
                SpendingLimitTypes(spendingLimitType)
            ),
            spendingLimit: limitInUsd,
            usedUpAmount: 0
        });

        emit ResetSpendingLimit(spendingLimitType, limitInUsd, startTime);
    }

    function _updateSpendingLimit(uint256 limitInUsd) internal {
        _currentSpendingLimit();

        _incomingSpendingLimit = _spendingLimit;
        _incomingSpendingLimit.spendingLimit = limitInUsd;

        _incomingSpendingLimitStartTime =
            block.timestamp +
            _cashDataProvider.delay();

        emit UpdateSpendingLimit(
            _spendingLimit.spendingLimit,
            limitInUsd,
            _incomingSpendingLimitStartTime
        );
    }

    function _setCollateralLimit(uint256 limitInUsd) internal {
        _currentCollateralLimit();

        _incomingCollateralLimitStartTime =
            block.timestamp +
            _cashDataProvider.delay();
        _incomingCollateralLimit = limitInUsd;

        emit SetCollateralLimit(
            _collateralLimit,
            limitInUsd,
            _incomingCollateralLimitStartTime
        );
    }

    function _requestWithdrawal(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient
    ) internal {
        _cancelOldWithdrawal();

        uint256 len = tokens.length;
        if (len != amounts.length) revert ArrayLengthMismatch();

        uint96 finalTime = uint96(block.timestamp) + _cashDataProvider.delay();

        for (uint256 i = 0; i < len; ) {
            if (IERC20(tokens[i]).balanceOf(address(this)) < amounts[i])
                revert InsufficientBalance();

            unchecked {
                ++i;
            }
        }

        _pendingWithdrawalRequest = WithdrawalRequest({
            tokens: tokens,
            amounts: amounts,
            recipient: recipient,
            finalizeTime: finalTime
        });

        emit WithdrawalRequested(tokens, amounts, recipient, finalTime);
    }

    function _cancelOldWithdrawal() internal {
        emit WithdrawalCancelled(
            _pendingWithdrawalRequest.tokens,
            _pendingWithdrawalRequest.amounts,
            _pendingWithdrawalRequest.recipient
        );

        delete _pendingWithdrawalRequest;
    }

    function _setOwner(bytes calldata __owner) internal override {
        emit SetOwner(_ownerBytes.getOwnerObject(), __owner.getOwnerObject());
        _ownerBytes = __owner;
    }

    function _getDecimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        _currentSpendingLimit();

        // If spending limit needs to be renewed, then renew it
        if (block.timestamp > _spendingLimit.renewalTimestamp) {
            _spendingLimit.usedUpAmount = 0;
            _spendingLimit.renewalTimestamp = _getSpendingLimitRenewalTimestamp(
                _spendingLimit.renewalTimestamp,
                _spendingLimit.spendingLimitType
            );
        }

        uint8 tokenDecimals = _getDecimals(token);

        // in current case, token can be either collateral tokens or borrow tokens
        if (_isCollateralToken(token)) {
            uint256 price = IPriceProvider(_cashDataProvider.priceProvider())
                .price(token);
            // token amount * price with 6 decimals / 10**decimals will convert the collateral token amount to USD amount with 6 decimals
            amount = (amount * price) / 10 ** tokenDecimals;
        } else {
            if (tokenDecimals != 6)
                // get amount in 6 decimals
                amount = (amount * 1e6) / 10 ** tokenDecimals;
        }

        if (amount + _spendingLimit.usedUpAmount > _spendingLimit.spendingLimit)
            revert ExceededSpendingLimit();

        _spendingLimit.usedUpAmount += amount;
    }

    function _checkCollateralLimit(
        address debtManager,
        address token,
        uint256 amountToAdd
    ) internal {
        _currentCollateralLimit();

        uint256 currentCollateral = IL2DebtManager(debtManager)
            .getCollateralValueInUsdc(address(this));

        uint256 price = IPriceProvider(_cashDataProvider.priceProvider()).price(
            token
        );

        // amount * price with 6 decimals / 10 ** tokenDecimals will convert the collateral amount to USD amount with 6 decimals
        amountToAdd = (amountToAdd * price) / 10 ** _getDecimals(token);

        if (currentCollateral + amountToAdd > _collateralLimit)
            revert ExceededCollateralLimit();
    }

    function _incrementNonce() private {
        _nonce++;
    }

    function _addCollateral(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        if (!_isCollateralToken(token)) revert UnsupportedToken();

        _checkCollateralLimit(debtManager, token, amount);
        _updateWithdrawalRequestIfNecessary(token, amount);

        IERC20(token).forceApprove(debtManager, amount);
        IL2DebtManager(debtManager).depositCollateral(
            token,
            address(this),
            amount
        );

        emit AddCollateralToDebtManager(token, amount);
    }

    function _borrow(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        if (!_isBorrowToken(token)) revert UnsupportedToken();

        _checkSpendingLimit(token, amount);

        IL2DebtManager(debtManager).borrow(token, amount);
        emit BorrowFromDebtManager(token, amount);
    }

    function _repay(
        address debtManager,
        address token,
        uint256 repayDebtUsdcAmt
    ) internal {
        // Repay token can either be borrow token or collateral token
        if (_isBorrowToken(token))
            IERC20(token).forceApprove(debtManager, repayDebtUsdcAmt);
        else if (!_isCollateralToken(token)) revert UnsupportedToken();

        IL2DebtManager(debtManager).repay(
            address(this),
            token,
            repayDebtUsdcAmt
        );
        emit RepayDebtManager(token, repayDebtUsdcAmt);
    }

    function _withdrawCollateralFromDebtManager(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        if (!_isCollateralToken(token)) revert UnsupportedToken();
        IL2DebtManager(debtManager).withdrawCollateral(token, amount);
        emit WithdrawCollateralFromDebtManager(token, amount);
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
            emit WithdrawalAmountUpdated(token, balance - amount);
        }
    }

    function _currentSpendingLimit() internal {
        if (
            _incomingSpendingLimitStartTime != 0 &&
            block.timestamp > _incomingSpendingLimitStartTime
        ) {
            _spendingLimit = _incomingSpendingLimit;
            delete _incomingSpendingLimit;
            delete _incomingSpendingLimitStartTime;
        }
    }

    function _currentCollateralLimit() internal {
        if (
            _incomingCollateralLimitStartTime != 0 &&
            block.timestamp > _incomingCollateralLimitStartTime
        ) {
            _collateralLimit = _incomingCollateralLimit;
            delete _incomingCollateralLimit;
            delete _incomingCollateralLimitStartTime;
        }
    }

    function _isCollateralToken(address token) internal view returns (bool) {
        return
            IL2DebtManager(_cashDataProvider.etherFiCashDebtManager())
                .isCollateralToken(token);
    }

    function _isBorrowToken(address token) internal view returns (bool) {
        return
            IL2DebtManager(_cashDataProvider.etherFiCashDebtManager())
                .isBorrowToken(token);
    }

    function _onlyEtherFiWallet() private view {
        if (msg.sender != _cashDataProvider.etherFiWallet())
            revert UnauthorizedCall();
    }

    modifier onlyEtherFiWallet() {
        _onlyEtherFiWallet();
        _;
    }

    modifier onlyOwner() {
        _ownerBytes._onlyOwner();
        _;
    }

    modifier incrementNonce() {
        _incrementNonce();
        _;
    }
}
