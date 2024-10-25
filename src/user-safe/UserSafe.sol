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
import {ReentrancyGuardTransientUpgradeable} from "../utils/ReentrancyGuardTransientUpgradeable.sol";
import {ArrayDeDupTransient} from "../libraries/ArrayDeDupTransientLib.sol";

/**
 * @title UserSafe
 * @author ether.fi [shivam@ether.fi]
 * @notice User safe account for interactions with the EtherFi Cash contracts
 */
contract UserSafe is IUserSafe, Initializable, ReentrancyGuardTransientUpgradeable, UserSafeRecovery {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;
    using OwnerLib for bytes;
    using UserSafeLib for OwnerLib.OwnerObject;
    using OwnerLib for OwnerLib.OwnerObject;
    using ArrayDeDupTransient for address[];

    // Address of the Cash Data Provider
    ICashDataProvider private immutable _cashDataProvider;

    // Owner: if ethAddr -> abi.encode(owner), if passkey -> abi.encode(x,y)
    bytes private _ownerBytes;
    // Owner: if ethAddr -> abi.encode(owner), if passkey -> abi.encode(x,y)
    bytes private _incomingOwnerBytes;
    // Time when the incoming owner becomes the owner
    uint256 private _incomingOwnerStartTime;

    // Withdrawal requests pending with the contract
    WithdrawalRequest private _pendingWithdrawalRequest;
    // Nonce for permit operations
    uint256 private _nonce;
    // Current spending limit
    SpendingLimitData private _spendingLimit;
    // Collateral limit
    uint256 private _collateralLimit;

    // Incoming spending limit -> we want a delay between spending limit changes so we can deduct funds in between to settle account
    uint256 private _incomingSpendingLimit;
    // Incoming spending limit start timestamp
    uint256 private _incomingSpendingLimitStartTime;
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
        __ReentrancyGuardTransient_init();
        _ownerBytes = __owner;

        _spendingLimit = SpendingLimitData({
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(uint64(block.timestamp)),
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
        if (
            _incomingOwnerStartTime != 0 &&
            block.timestamp > _incomingOwnerStartTime
        ) return _incomingOwnerBytes.getOwnerObject();

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
        SpendingLimitData memory _applicableSpendingLimit = _spendingLimit;
        if (
            _incomingSpendingLimitStartTime != 0 &&
            block.timestamp > _incomingSpendingLimitStartTime
        ) {
            _applicableSpendingLimit.spendingLimit = _incomingSpendingLimit;
            _applicableSpendingLimit.renewalTimestamp = _getSpendingLimitRenewalTimestamp(uint64(_incomingSpendingLimitStartTime));
        }

        // If spending limit needs to be renewed, then renew it
        if (block.timestamp > _applicableSpendingLimit.renewalTimestamp) {
            _applicableSpendingLimit.usedUpAmount = 0;

            do _applicableSpendingLimit.renewalTimestamp = _getSpendingLimitRenewalTimestamp(_applicableSpendingLimit.renewalTimestamp);
            while (block.timestamp > _applicableSpendingLimit.renewalTimestamp);
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
    ) external incrementNonce currentOwner {
        // Since owner is setting a new owner, an incoming owner does not make sense
        delete _incomingOwnerBytes;
        delete _incomingOwnerStartTime;

        owner().verifySetOwnerSig(_nonce, __owner, signature);

        // Owner should not be zero
        __owner.getOwnerObject()._ownerNotZero();
        _setOwner(__owner);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function updateSpendingLimit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        owner().verifyUpdateSpendingLimitSig(_nonce, limitInUsd, signature);
        _updateSpendingLimit(limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setCollateralLimit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external incrementNonce currentOwner {
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
    ) external incrementNonce currentOwner {
        if (tokens.length > 1) tokens.checkDuplicates();

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
    ) external incrementNonce currentOwner {
        _setIsRecoveryActive(isActive, _nonce, signature);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setUserRecoverySigner(
        address userRecoverySigner,
        bytes calldata signature
    ) external incrementNonce currentOwner {
        _setUserRecoverySigner(userRecoverySigner, _nonce, signature);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function recoverUserSafe(
        bytes calldata newOwner,
        Signature[2] calldata signatures
    ) external onlyWhenRecoveryActive incrementNonce currentOwner {
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
        uint256 amount
    ) external onlyEtherFiWallet {
        address debtManager = _cashDataProvider.etherFiCashDebtManager();
        _repay(debtManager, token, amount);
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

    function _getSpendingLimitRenewalTimestamp(uint64 startTimestamp) internal pure returns (uint64 renewalTimestamp) {
        return startTimestamp + 30 * 24 * 60 * 60;
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

    function _updateSpendingLimit(uint256 limitInUsd) internal {
        _currentSpendingLimit();

        if (limitInUsd > _spendingLimit.spendingLimit) {
            delete _incomingSpendingLimit;
            delete _incomingSpendingLimitStartTime;
            
            emit UpdateSpendingLimit(
                _spendingLimit.spendingLimit,
                limitInUsd,
                block.timestamp
            );

            _spendingLimit.spendingLimit = limitInUsd;
        } else {
            _incomingSpendingLimit = limitInUsd;
            _incomingSpendingLimitStartTime = block.timestamp + _cashDataProvider.delay();

            emit UpdateSpendingLimit(
                _spendingLimit.spendingLimit,
                limitInUsd,
                _incomingSpendingLimitStartTime
            );
        }
    }

    function _setCollateralLimit(uint256 limitInUsd) internal {
        _currentCollateralLimit();

        if (limitInUsd > _collateralLimit) {
            delete _incomingCollateralLimitStartTime;
            delete _incomingCollateralLimit;

            emit SetCollateralLimit(
                _collateralLimit,
                limitInUsd,
                block.timestamp
            );
            _collateralLimit = limitInUsd;
        } else {
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
        if (_pendingWithdrawalRequest.tokens.length > 0) {
            emit WithdrawalCancelled(
                _pendingWithdrawalRequest.tokens,
                _pendingWithdrawalRequest.amounts,
                _pendingWithdrawalRequest.recipient
            );

            delete _pendingWithdrawalRequest;
        }
    }

    function _setOwner(bytes calldata __owner) internal {
        emit SetOwner(_ownerBytes.getOwnerObject(), __owner.getOwnerObject());
        _ownerBytes = __owner;
    }

    function _setIncomingOwner(bytes calldata __owner) internal override {
        _incomingOwnerStartTime = block.timestamp + _cashDataProvider.delay();
        OwnerLib.OwnerObject memory ownerObj = __owner.getOwnerObject();
        ownerObj._ownerNotZero();

        emit SetIncomingOwner(ownerObj, _incomingOwnerStartTime);
        _incomingOwnerBytes = __owner;
    }

    function _getDecimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    function _checkSpendingLimit(address token, uint256 amount) internal {
        _currentSpendingLimit();

        // If spending limit needs to be renewed, then renew it
        if (block.timestamp > _spendingLimit.renewalTimestamp) {
            _spendingLimit.usedUpAmount = 0;
            
            do _spendingLimit.renewalTimestamp = _getSpendingLimitRenewalTimestamp(_spendingLimit.renewalTimestamp);
            while (block.timestamp > _spendingLimit.renewalTimestamp);
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

        uint256 currentCollateral = IL2DebtManager(debtManager).getCollateralValueInUsd(address(this));
        uint256 price = IPriceProvider(_cashDataProvider.priceProvider()).price(token);
        // amount * price with 6 decimals / 10 ** tokenDecimals will convert the collateral amount to USD amount with 6 decimals
        amountToAdd = (amountToAdd * price) / 10 ** _getDecimals(token);
        if (currentCollateral + amountToAdd > _collateralLimit) revert ExceededCollateralLimit();
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
        uint256 amount
    ) internal {
        // Repay token can either be borrow token or collateral token
        IERC20(token).forceApprove(debtManager, amount);

        IL2DebtManager(debtManager).repay(
            address(this),
            token,
            amount
        );
        emit RepayDebtManager(token, amount);
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
            _spendingLimit.spendingLimit = _incomingSpendingLimit;
            _spendingLimit.renewalTimestamp = _getSpendingLimitRenewalTimestamp(uint64(_incomingSpendingLimitStartTime));
            delete _incomingSpendingLimit;
            delete _incomingSpendingLimitStartTime;
        }
    }

    function _currentOwner() internal {
        if (
            _incomingOwnerStartTime != 0 &&
            block.timestamp > _incomingOwnerStartTime
        ) {
            _ownerBytes = _incomingOwnerBytes;
            delete _incomingOwnerBytes;
            delete _incomingOwnerStartTime;
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
        if (!_cashDataProvider.isEtherFiWallet(msg.sender))
            revert UnauthorizedCall();
    }

    modifier onlyEtherFiWallet() {
        _onlyEtherFiWallet();
        _;
    }

    modifier incrementNonce() {
        _nonce++;
        _;
    }

    modifier currentOwner() {
        _currentOwner();
        _;
    }
}
