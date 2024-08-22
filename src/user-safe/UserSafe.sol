// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

/**
 * @title UserSafe
 * @author ether.fi [shivam@ether.fi]
 * @notice User safe account for interactions with the EtherFi Cash contracts
 */
contract UserSafe is IUserSafe, Initializable, UserSafeRecovery {
    using SafeERC20 for IERC20;
    using SignatureUtils for bytes32;
    using OwnerLib for bytes;

    bytes32 public constant REQUEST_WITHDRAWAL_METHOD =
        keccak256("requestWithdrawal");
    bytes32 public constant RESET_SPENDING_LIMIT_METHOD =
        keccak256("resetSpendingLimit");
    bytes32 public constant UPDATE_SPENDING_LIMIT_METHOD =
        keccak256("updateSpendingLimit");
    bytes32 public constant SET_COLLATERAL_LIMIT_METHOD =
        keccak256("setCollateralLimit");
    bytes32 public constant SET_OWNER_METHOD = keccak256("setOwner");

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

    // Owner: if ethAddr -> abi.encode(owner), if passkey -> abi.encode(x,y)
    bytes private _ownerBytes;
    // Withdrawal requests pending with the contract
    WithdrawalRequest private _pendingWithdrawalRequest;
    // Funds blocked for withdrawal
    mapping(address token => uint256 amount) private blockedFundsForWithdrawal;
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

    constructor(
        address __cashDataProvider,
        address __etherFiRecoverySigner,
        address __thirdPartyRecoverySigner
    ) UserSafeRecovery(__etherFiRecoverySigner, __thirdPartyRecoverySigner) {
        _cashDataProvider = ICashDataProvider(__cashDataProvider);
        _usdc = _cashDataProvider.usdc();
        _weETH = _cashDataProvider.weETH();
        _priceProvider = IPriceProvider(_cashDataProvider.priceProvider());
        _swapper = ISwapper(_cashDataProvider.swapper());
    }

    function initialize(
        bytes calldata __owner,
        uint256 __defaultSpendingLimit,
        uint256 __collateralLimit
    ) external initializer {
        _ownerBytes = __owner;

        _spendingLimit = SpendingLimitData({
            spendingLimitType: SpendingLimitTypes(SpendingLimitTypes.Monthly),
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(
                uint64(block.timestamp),
                SpendingLimitTypes(SpendingLimitTypes.Monthly)
            ),
            spendingLimit: __defaultSpendingLimit,
            usedUpAmount: 0
        });

        _collateralLimit = __collateralLimit;

        __UserSafeRecovery_init();
    }

    /**
     * @inheritdoc IUserSafe
     */
    function ownerBytes() public view returns (bytes memory) {
        return _ownerBytes;
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
    function incomingSpendingLimit()
        external
        view
        returns (SpendingLimitData memory, uint256)
    {
        return (_incomingSpendingLimit, _incomingSpendingLimitStartTime);
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
    function collateralLimit() external view returns (uint256) {
        return _collateralLimit;
    }

    /**
     * @inheritdoc IUserSafe
     */
    function incomingCollateralLimit()
        external
        view
        returns (uint256, uint256)
    {
        return (_incomingCollateralLimit, _incomingCollateralLimitStartTime);
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
    function setOwner(bytes calldata __owner) external onlyOwner {
        _setOwner(__owner);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setOwnerWithPermit(
        bytes calldata __owner,
        bytes calldata signature
    ) external incrementNonce {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_OWNER_METHOD,
                block.chainid,
                address(this),
                _nonce,
                __owner
            )
        );

        msgHash.verifySig(owner(), signature);
        _setOwner(__owner);
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
        bytes calldata signature
    ) external incrementNonce {
        bytes32 msgHash = keccak256(
            abi.encode(
                RESET_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(this),
                _nonce,
                spendingLimitType,
                limitInUsd
            )
        );

        msgHash.verifySig(owner(), signature);
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
        bytes calldata signature
    ) external incrementNonce {
        bytes32 msgHash = keccak256(
            abi.encode(
                UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(this),
                _nonce,
                limitInUsd
            )
        );

        msgHash.verifySig(owner(), signature);
        _updateSpendingLimit(limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setCollateralLimit(uint256 limitInUsd) external onlyOwner {
        _setCollateralLimit(limitInUsd);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setCollateralLimitWithPermit(
        uint256 limitInUsd,
        bytes calldata signature
    ) external incrementNonce {
        bytes32 msgHash = keccak256(
            abi.encode(
                SET_COLLATERAL_LIMIT_METHOD,
                block.chainid,
                address(this),
                _nonce,
                limitInUsd
            )
        );

        msgHash.verifySig(owner(), signature);
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
        address recipient
    ) external onlyOwner {
        _requestWithdrawal(tokens, amounts, recipient);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function requestWithdrawalWithPermit(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address recipient,
        bytes calldata signature
    ) external incrementNonce {
        bytes32 msgHash = keccak256(
            abi.encode(
                REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(this),
                _nonce,
                tokens,
                amounts,
                recipient
            )
        );

        msgHash.verifySig(owner(), signature);
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
    function setIsRecoveryActive(bool isActive) external onlyOwner {
        _setIsRecoveryActive(isActive);
    }

    /**
     * @inheritdoc IUserSafe
     */
    function setIsRecoveryActiveWithPermit(
        bool isActive,
        bytes calldata signature
    ) external incrementNonce {
        _setIsRecoveryActiveWithPermit(isActive, _nonce, signature);
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
        if (token != _usdc) revert UnsupportedToken();

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
        if (inputTokenToSwap != _weETH || outputToken != _usdc)
            revert UnsupportedToken();

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
        _currentSpendingLimit();

        _incomingSpendingLimitStartTime =
            block.timestamp +
            _cashDataProvider.delay();

        _incomingSpendingLimit = SpendingLimitData({
            spendingLimitType: SpendingLimitTypes(spendingLimitType),
            renewalTimestamp: _getSpendingLimitRenewalTimestamp(
                uint64(_incomingSpendingLimitStartTime),
                SpendingLimitTypes(spendingLimitType)
            ),
            spendingLimit: limitInUsd,
            usedUpAmount: 0
        });

        emit ResetSpendingLimit(
            spendingLimitType,
            limitInUsd,
            _incomingSpendingLimitStartTime
        );
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

        for (uint256 i = 0; i < len; ) {
            if (IERC20(tokens[i]).balanceOf(address(this)) < amounts[i])
                revert InsufficientBalance();

            blockedFundsForWithdrawal[tokens[i]] = amounts[i];

            unchecked {
                ++i;
            }
        }

        uint96 finalTime = uint96(block.timestamp) + _cashDataProvider.delay();

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

    function _setOwner(bytes calldata __owner) internal override {
        emit SetOwner(_ownerBytes.getOwnerObject(), __owner.getOwnerObject());
        _ownerBytes = __owner;
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

    function _checkCollateralLimit(
        address debtManager,
        address token,
        uint256 amountToAdd
    ) internal {
        _currentCollateralLimit();

        uint256 currentCollateral = IL2DebtManager(debtManager)
            .getCollateralValueInUsdc(address(this));

        // in current case, token can be either weETH or USDC only
        if (token == _weETH) {
            uint256 price = _priceProvider.getWeEthUsdPrice();
            // amount * price with 6 decimals / 1 ether will convert the weETH amount to USD amount with 6 decimals
            amountToAdd = (amountToAdd * price) / 1 ether;
        }

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
        if (token != _weETH) revert UnsupportedToken();

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
        if (token != _usdc) revert UnsupportedToken();
        _checkSpendingLimit(token, amount);

        IL2DebtManager(debtManager).borrow(token, amount);
        emit BorrowFromDebtManager(token, amount);
    }

    function _repay(
        address debtManager,
        address token,
        uint256 repayDebtUsdcAmt
    ) internal {
        if (token == _usdc) {
            IERC20(_usdc).forceApprove(debtManager, repayDebtUsdcAmt);
            IL2DebtManager(debtManager).repay(
                address(this),
                token,
                repayDebtUsdcAmt
            );
            emit RepayDebtManager(token, repayDebtUsdcAmt);
        } else if (token == _weETH) {
            IL2DebtManager(debtManager).repay(
                address(this),
                token,
                repayDebtUsdcAmt
            );
            emit RepayDebtManager(token, repayDebtUsdcAmt);
        } else revert UnsupportedToken();
    }

    function _withdrawCollateralFromDebtManager(
        address debtManager,
        address token,
        uint256 amount
    ) internal {
        IL2DebtManager(debtManager).withdrawCollateral(token, amount);
        emit WithdrawCollateralFromDebtManager(token, amount);
    }

    function _updateWithdrawalRequestIfNecessary(
        address token,
        uint256 amount
    ) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));

        if (amount > balance) revert InsufficientBalance();

        if (amount + blockedFundsForWithdrawal[token] > balance) {
            blockedFundsForWithdrawal[token] = balance - amount;
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
