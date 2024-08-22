// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "./interfaces/ICashDataProvider.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IL2DebtManager} from "./interfaces/IL2DebtManager.sol";
import {IPriceProvider} from "./interfaces/IPriceProvider.sol";
import {IEtherFiCashAaveV3Adapter} from "./interfaces/IEtherFiCashAaveV3Adapter.sol";
import {TokenDecimalCache} from "./utils/TokenDecimalCache.sol";
import {console} from "forge-std/console.sol";

/**
 * @title L2 Debt Manager
 * @author @seongyun-ko @shivam-ef
 * @notice Contract to manage lending and borrowing for Cash protocol
 */
contract L2DebtManager is
    IL2DebtManager,
    TokenDecimalCache,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant AN_YEAR_IN_SECONDS = 365 * 24 * 60 * 60;
    uint256 public constant MAX_BORROW_APY = 20e18;

    IERC20 public immutable weETH;
    IERC20 public immutable usdc;
    address public immutable etherFiCashSafe;
    IPriceProvider public immutable priceProvider;
    address public immutable aaveV3Adapter;

    address[] private _supportedCollateralTokens;
    address[] private _supportedBorrowTokens;
    mapping(address token => uint256 index)
        private _collateralTokenIndexPlusOne;
    mapping(address token => uint256 index) private _borrowTokenIndexPlusOne;

    // Collateral held by the user
    mapping(address user => mapping(address token => uint256 amount))
        private _userCollateral;
    // Total collateral held by the users with the contract
    mapping(address token => uint256 amount) private _totalCollateralAmounts;

    // Borrowings is in USD with 6 decimals
    mapping(address user => uint256 borrowing) private _userBorrowings;
    // Borrowings is in USD with 6 decimals
    uint256 private _totalBorrowingAmount;
    // Has 18 decimals
    uint256 private _liquidationThreshold;

    // In 18 decimals
    uint256 private _borrowApyPerSecond;
    // Snapshot of total interest earned per USD from the time of deployment of this contract
    uint256 private _debtInterestIndexSnapshot;
    // Last snapshot time for interest addition
    uint256 private _debtInterestIndexSnapshotTimestamp;
    // Snapshot of user's interests already paid
    mapping(address user => uint256 interestSnapshot)
        private _usersDebtInterestIndexSnapshots;

    constructor(
        address _weETH,
        address _usdc,
        address _etherFiCashSafe,
        address _priceProvider,
        address _aaveV3Adapter
    ) {
        weETH = IERC20(_weETH);
        usdc = IERC20(_usdc);
        etherFiCashSafe = _etherFiCashSafe;
        priceProvider = IPriceProvider(_priceProvider);
        aaveV3Adapter = _aaveV3Adapter;
    }

    function initialize(
        address __owner,
        uint256 __liquidationThreshold,
        uint256 __borrowApyPerSecond,
        address[] calldata __supportedCollateralTokens,
        address[] calldata __supportedBorrowTokens
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, __owner);
        _grantRole(ADMIN_ROLE, __owner);

        _setLiquidationThreshold(__liquidationThreshold);
        _setBorrowApyPerSecond(__borrowApyPerSecond);

        uint256 len = __supportedCollateralTokens.length;
        for (uint256 i = 0; i < len; ) {
            _supportCollateralToken(__supportedCollateralTokens[i]);
            unchecked {
                ++i;
            }
        }

        len = __supportedBorrowTokens.length;
        for (uint256 i = 0; i < len; ) {
            _supportBorrowToken(__supportedBorrowTokens[i]);
            unchecked {
                ++i;
            }
        }

        _debtInterestIndexSnapshotTimestamp = block.timestamp;
        _debtInterestIndexSnapshot = 0;
        _totalBorrowingAmount = 0;

        cacheDecimals(__supportedCollateralTokens);
        cacheDecimals(__supportedBorrowTokens);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function borrowApyPerSecond() public view returns (uint256) {
        return _borrowApyPerSecond;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getCollateralTokens() public view returns (address[] memory) {
        uint256 len = _supportedCollateralTokens.length;
        address[] memory tokens = new address[](len);

        for (uint256 i = 0; i < len; ) {
            tokens[i] = _supportedCollateralTokens[i];
            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getBorrowTokens() public view returns (address[] memory) {
        uint256 len = _supportedBorrowTokens.length;
        address[] memory tokens = new address[](len);

        for (uint256 i = 0; i < len; ) {
            tokens[i] = _supportedBorrowTokens[i];
            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function isCollateralToken(address token) public view returns (bool) {
        return _collateralTokenIndexPlusOne[token] != 0;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function isBorrowToken(address token) public view returns (bool) {
        return _borrowTokenIndexPlusOne[token] != 0;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getUserCollateralForToken(
        address user,
        address token
    ) external view returns (uint256, uint256) {
        if (!isCollateralToken(token)) revert UnsupportedCollateralToken();
        uint256 collateralTokenAmt = _userCollateral[user][token];
        uint256 collateralAmtInUsd = convertCollateralTokenToUsdc(
            token,
            collateralTokenAmt
        );

        return (collateralTokenAmt, collateralAmtInUsd);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidationThreshold() external view returns (uint256) {
        return _liquidationThreshold;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function totalBorrowingAmount() public view returns (uint256) {
        return
            _getAmountWithInterest(
                _totalBorrowingAmount,
                _debtInterestIndexSnapshot
            );
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function borrowingOf(address user) public view returns (uint256) {
        return
            _getAmountWithInterest(
                _userBorrowings[user],
                _usersDebtInterestIndexSnapshots[user]
            );
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function totalCollateralAmounts()
        public
        view
        returns (TokenData[] memory, uint256)
    {
        uint256 len = _supportedCollateralTokens.length;
        TokenData[] memory collaterals = new TokenData[](len);
        uint256 totalCollateralInUsd = 0;

        for (uint256 i = 0; i < len; ) {
            collaterals[i] = TokenData({
                token: _supportedCollateralTokens[i],
                amount: _totalCollateralAmounts[_supportedCollateralTokens[i]]
            });

            totalCollateralInUsd += convertCollateralTokenToUsdc(
                collaterals[i].token,
                collaterals[i].amount
            );

            unchecked {
                ++i;
            }
        }

        return (collaterals, totalCollateralInUsd);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidatable(address user) public view returns (bool) {
        return debtRatioOf(user) > _liquidationThreshold;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function collateralOf(
        address user
    ) public view returns (TokenData[] memory, uint256) {
        uint256 len = _supportedCollateralTokens.length;
        TokenData[] memory collaterals = new TokenData[](len);
        uint256 totalCollateralInUsd = 0;

        for (uint256 i = 0; i < len; ) {
            collaterals[i] = TokenData({
                token: _supportedCollateralTokens[i],
                amount: _userCollateral[user][_supportedCollateralTokens[i]]
            });

            totalCollateralInUsd += convertCollateralTokenToUsdc(
                collaterals[i].token,
                collaterals[i].amount
            );

            unchecked {
                ++i;
            }
        }

        return (collaterals, totalCollateralInUsd);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function debtRatioOf(address user) public view returns (uint256) {
        uint256 debtValue = borrowingOf(user);
        uint256 collateralValue = getCollateralValueInUsdc(user);
        if (collateralValue == 0) revert ZeroCollateralValue();

        return (debtValue * 1e20) / collateralValue; // result in basis points
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function remainingBorrowingCapacityInUSDC(
        address user
    ) public view returns (uint256) {
        uint256 maxBorrowingAmount = (getCollateralValueInUsdc(user) *
            _liquidationThreshold) / 1e20;

        uint256 currentBorrowingWithInterest = borrowingOf(user);

        return
            maxBorrowingAmount > currentBorrowingWithInterest
                ? maxBorrowingAmount - currentBorrowingWithInterest
                : 0;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getCurrentState()
        public
        view
        returns (
            TokenData[] memory totalCollaterals,
            uint256 totalCollateralInUsdc,
            uint256 totalBorrowings,
            TokenData[] memory totalLiquidCollateralAmounts,
            uint256 totalLiquidStableAmounts
        )
    {
        (totalCollaterals, totalCollateralInUsdc) = totalCollateralAmounts();
        totalBorrowings = _totalBorrowingAmount;
        totalLiquidCollateralAmounts = liquidCollateralAmounts();
        totalLiquidStableAmounts = liquidStableAmount();
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidCollateralAmounts()
        public
        view
        returns (TokenData[] memory)
    {
        uint256 len = _supportedCollateralTokens.length;
        TokenData[] memory collaterals = new TokenData[](len);

        for (uint256 i = 0; i < len; ) {
            uint256 balance = IERC20(_supportedCollateralTokens[i]).balanceOf(
                address(this)
            );
            if (
                balance > _totalCollateralAmounts[_supportedCollateralTokens[i]]
            )
                collaterals[i] = TokenData({
                    token: _supportedCollateralTokens[i],
                    amount: balance -
                        _totalCollateralAmounts[_supportedCollateralTokens[i]]
                });
            else
                collaterals[i] = TokenData({
                    token: _supportedCollateralTokens[i],
                    amount: 0
                });

            unchecked {
                ++i;
            }
        }

        return collaterals;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidStableAmount() public view returns (uint256) {
        uint256 len = _supportedBorrowTokens.length;
        uint256 totalStableBalances = 0;
        for (uint256 i = 0; i < len; ) {
            totalStableBalances += IERC20(_supportedBorrowTokens[i]).balanceOf(
                address(this)
            );

            unchecked {
                ++i;
            }
        }

        return
            totalStableBalances > _totalBorrowingAmount
                ? totalStableBalances - _totalBorrowingAmount
                : 0;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function convertUsdcToCollateralToken(
        address collateralToken,
        uint256 debtUsdcAmount
    ) public view returns (uint256) {
        if (!isCollateralToken(collateralToken))
            revert UnsupportedCollateralToken();
        return
            (debtUsdcAmount * 10 ** getDecimals(collateralToken)) /
            priceProvider.price(collateralToken);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function convertCollateralTokenToUsdc(
        address collateralToken,
        uint256 collateralAmount
    ) public view returns (uint256) {
        if (!isCollateralToken(collateralToken))
            revert UnsupportedCollateralToken();

        return
            (collateralAmount * priceProvider.price(collateralToken)) /
            10 ** getDecimals(collateralToken);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function getCollateralValueInUsdc(
        address user
    ) public view returns (uint256) {
        uint256 len = _supportedCollateralTokens.length;
        uint256 userCollateralInUsd = 0;

        for (uint256 i = 0; i < len; ) {
            userCollateralInUsd += convertCollateralTokenToUsdc(
                _supportedCollateralTokens[i],
                _userCollateral[user][_supportedCollateralTokens[i]]
            );

            unchecked {
                ++i;
            }
        }

        return userCollateralInUsd;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function debtInterestIndexSnapshot() public view returns (uint256) {
        return
            _debtInterestIndexSnapshot +
            (block.timestamp - _debtInterestIndexSnapshotTimestamp) *
            _borrowApyPerSecond;
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function supportCollateralToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        _supportCollateralToken(token);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function unsupportCollateralToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidValue();
        if (_totalCollateralAmounts[token] != 0)
            revert TotalCollateralAmountNotZero();

        uint256 indexPlusOneForTokenToBeRemoved = _collateralTokenIndexPlusOne[
            token
        ];
        if (indexPlusOneForTokenToBeRemoved == 0) revert NotACollateralToken();

        uint256 len = _supportedCollateralTokens.length;
        if (len == 1) revert NoCollateralTokenLeft();

        _collateralTokenIndexPlusOne[_supportedCollateralTokens[len - 1]] ==
            indexPlusOneForTokenToBeRemoved;

        _supportedCollateralTokens[
            indexPlusOneForTokenToBeRemoved - 1
        ] = _supportedCollateralTokens[len - 1];

        _supportedCollateralTokens.pop();
        delete _collateralTokenIndexPlusOne[token];

        emit CollateralTokenRemoved(token);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function supportBorrowToken(address token) external onlyRole(ADMIN_ROLE) {
        _supportBorrowToken(token);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function unsupportBorrowToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidValue();

        uint256 indexPlusOneForTokenToBeRemoved = _borrowTokenIndexPlusOne[
            token
        ];
        if (indexPlusOneForTokenToBeRemoved == 0) revert NotABorrowToken();

        uint256 len = _supportedBorrowTokens.length;
        if (len == 1) revert NoBorrowTokenLeft();

        _borrowTokenIndexPlusOne[_supportedBorrowTokens[len - 1]] ==
            indexPlusOneForTokenToBeRemoved;

        _supportedBorrowTokens[
            indexPlusOneForTokenToBeRemoved - 1
        ] = _supportedBorrowTokens[len - 1];

        _supportedBorrowTokens.pop();
        delete _borrowTokenIndexPlusOne[token];

        emit BorrowTokenRemoved(token);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function setBorrowApyPerSecond(uint256 apy) external onlyRole(ADMIN_ROLE) {
        _setBorrowApyPerSecond(apy);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function setLiquidationThreshold(
        uint256 newThreshold
    ) external onlyRole(ADMIN_ROLE) {
        _setLiquidationThreshold(newThreshold);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function depositCollateral(
        address token,
        address user,
        uint256 amount
    ) external updateBorrowings(user) {
        if (!isCollateralToken(token)) revert UnsupportedCollateralToken();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _totalCollateralAmounts[token] += amount;
        _userCollateral[user][token] += amount;

        emit DepositedCollateral(msg.sender, user, token, amount);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function borrow(
        address token,
        uint256 amount
    ) external updateBorrowings(msg.sender) {
        if (!isBorrowToken(token)) revert UnsupportedBorrowToken();

        // Convert amount to 6 decimals before adding to borrowings
        uint256 borrowAmt = _convertToSixDecimals(token, amount);

        _userBorrowings[msg.sender] += borrowAmt;
        _totalBorrowingAmount += borrowAmt;

        if (debtRatioOf(msg.sender) > _liquidationThreshold)
            revert InsufficientCollateral();

        if (IERC20(token).balanceOf(address(this)) < amount)
            revert InsufficientLiquidity();

        IERC20(token).safeTransfer(etherFiCashSafe, amount);

        emit Borrowed(msg.sender, token, amount);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function repay(
        address user,
        address token,
        uint256 repayDebtUsdcAmt
    ) external updateBorrowings(user) {
        if (_userBorrowings[user] < repayDebtUsdcAmt)
            revert CannotPayMoreThanDebtIncurred();

        if (isBorrowToken(token))
            _repayWithBorrowToken(token, user, repayDebtUsdcAmt);
        else if (isCollateralToken(token)) {
            if (msg.sender != user) revert OnlyUserCanRepayWithCollateral();
            _repayWithCollateralToken(user, token, repayDebtUsdcAmt);
        } else revert UnsupportedRepayToken();
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function repayWithCollateral(
        address user,
        uint256 repayDebtUsdcAmt
    ) external updateBorrowings(user) {
        if (msg.sender != user) revert OnlyUserCanRepayWithCollateral();

        _repayWithCollateral(user, repayDebtUsdcAmt);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function withdrawCollateral(
        address token,
        uint256 amount
    ) external updateBorrowings(msg.sender) {
        if (!isCollateralToken(token)) revert UnsupportedCollateralToken();

        _totalCollateralAmounts[token] -= amount;
        _userCollateral[msg.sender][token] -= amount;

        if (debtRatioOf(msg.sender) > _liquidationThreshold)
            revert InsufficientCollateral();

        IERC20(token).safeTransfer(msg.sender, amount);

        emit WithdrawCollateral(msg.sender, token, amount);
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function closeAccount() external updateBorrowings(msg.sender) {
        uint256 totalUserBorrowing = _userBorrowings[msg.sender];
        _repayWithCollateral(msg.sender, totalUserBorrowing);

        (TokenData[] memory tokenData, ) = collateralOf(msg.sender);
        uint256 len = tokenData.length;

        for (uint256 i = 0; i < len; ) {
            if (
                IERC20(tokenData[i].token).balanceOf(address(this)) <
                tokenData[i].amount
            ) revert InsufficientLiquidityPleaseTryAgainLater();

            IERC20(tokenData[i].token).safeTransfer(
                msg.sender,
                tokenData[i].amount
            );

            unchecked {
                ++i;
            }
        }

        emit AccountClosed(msg.sender, totalUserBorrowing, tokenData);
    }

    // https://docs.aave.com/faq/liquidations
    /**
     * @inheritdoc IL2DebtManager
     */
    function liquidate(
        address user
    ) external onlyRole(ADMIN_ROLE) updateBorrowings(user) {
        if (!liquidatable(user)) revert CannotLiquidateYet();

        uint256 beforeDebtAmount = _userBorrowings[user];
        (TokenData[] memory beforeCollateralAmounts, ) = collateralOf(user);
        _repayWithCollateral(user, beforeDebtAmount); // force to repay the entire debt using the collateral
        (TokenData[] memory afterCollateralAmounts, ) = collateralOf(user);

        emit Liquidated(
            user,
            beforeCollateralAmounts,
            afterCollateralAmounts,
            beforeDebtAmount
        );
    }

    /**
     * @inheritdoc IL2DebtManager
     */
    function fundManagementOperation(
        uint8 marketOperationType,
        bytes calldata data
    ) external onlyRole(ADMIN_ROLE) {
        if (marketOperationType == uint8(MarketOperationType.Supply)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _supplyOnAave(token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Borrow)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _borrowFromAave(token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Repay)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _repayOnAave(token, amount);
        } else if (marketOperationType == uint8(MarketOperationType.Withdraw)) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            _withdrawFromAave(token, amount);
        } else if (
            marketOperationType == uint8(MarketOperationType.SupplyAndBorrow)
        ) {
            (
                address tokenToSupply,
                uint256 amountToSupply,
                address tokenToBorrow,
                uint256 amountToBorrow
            ) = abi.decode(data, (address, uint256, address, uint256));
            _supplyAndBorrowOnAave(
                tokenToSupply,
                amountToSupply,
                tokenToBorrow,
                amountToBorrow
            );
        } else revert InvalidMarketOperationType();
    }

    /// Users repay the borrowed USDC in USDC
    function _repayWithBorrowToken(
        address token,
        address user,
        uint256 repayDebtUsdcAmt
    ) internal {
        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            _convertToSixDecimals(token, repayDebtUsdcAmt)
        );
        _userBorrowings[user] -= repayDebtUsdcAmt;
        _totalBorrowingAmount -= repayDebtUsdcAmt;

        emit RepaidWithUSDC(user, msg.sender, repayDebtUsdcAmt);
    }

    // Use the deposited collateral to pay the debt
    function _repayWithCollateralToken(
        address user,
        address collateralToken,
        uint256 repayDebtUsdcAmt
    ) internal {
        uint256 collateralAmountForDebt = convertUsdcToCollateralToken(
            collateralToken,
            repayDebtUsdcAmt
        );

        uint256 beforeCollateralAmount = _userCollateral[user][collateralToken];

        if (beforeCollateralAmount < collateralAmountForDebt)
            revert InsufficientCollateralToRepay();

        _userBorrowings[user] -= repayDebtUsdcAmt;
        _userCollateral[user][collateralToken] -= collateralAmountForDebt;

        _totalBorrowingAmount -= repayDebtUsdcAmt;
        _totalCollateralAmounts[collateralToken] -= collateralAmountForDebt;

        if (debtRatioOf(user) > _liquidationThreshold)
            revert InsufficientCollateral();

        emit RepaidWithCollateralToken(
            user,
            msg.sender,
            collateralToken,
            beforeCollateralAmount,
            _userCollateral[user][collateralToken],
            repayDebtUsdcAmt
        );
    }

    // Use the deposited collateral to pay the debt
    function _repayWithCollateral(
        address user,
        uint256 repayDebtUsdcAmt
    ) internal {
        uint256 len = _supportedCollateralTokens.length;
        TokenData[] memory collateral = new TokenData[](len);

        for (uint256 i = 0; i < len; ) {
            address collateralToken = _supportedCollateralTokens[i];
            uint256 collateralAmountForDebt = convertUsdcToCollateralToken(
                collateralToken,
                repayDebtUsdcAmt
            );

            if (
                _userCollateral[user][collateralToken] < collateralAmountForDebt
            ) {
                collateral[i] = TokenData({
                    token: collateralToken,
                    amount: _userCollateral[user][collateralToken]
                });

                uint256 usdcValueOfCollateral = convertCollateralTokenToUsdc(
                    collateralToken,
                    _userCollateral[user][collateralToken]
                );

                _totalCollateralAmounts[collateralToken] -= _userCollateral[
                    user
                ][collateralToken];
                _userCollateral[user][collateralToken] = 0;

                _userBorrowings[user] -= usdcValueOfCollateral;
                _totalBorrowingAmount -= usdcValueOfCollateral;
                repayDebtUsdcAmt -= usdcValueOfCollateral;
            } else {
                collateral[i] = TokenData({
                    token: collateralToken,
                    amount: collateralAmountForDebt
                });

                _userBorrowings[user] -= repayDebtUsdcAmt;
                _userCollateral[user][
                    collateralToken
                ] -= collateralAmountForDebt;

                _totalBorrowingAmount -= repayDebtUsdcAmt;
                _totalCollateralAmounts[
                    collateralToken
                ] -= collateralAmountForDebt;

                repayDebtUsdcAmt = 0;
            }

            if (repayDebtUsdcAmt == 0) {
                uint256 arrLen = i + 1;
                assembly {
                    mstore(collateral, arrLen)
                }

                break;
            }

            unchecked {
                ++i;
            }
        }

        if (debtRatioOf(user) > _liquidationThreshold)
            revert InsufficientCollateral();

        emit RepaidWithCollateral(user, repayDebtUsdcAmt, collateral);
    }

    function _supplyAndBorrowOnAave(
        address tokenToSupply,
        uint256 amountToSupply,
        address tokenToBorrow,
        uint256 amountToBorrow
    ) internal {
        if (aaveV3Adapter == address(0)) revert AaveAdapterNotSet();

        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.process.selector,
                tokenToSupply,
                amountToSupply,
                tokenToBorrow,
                amountToBorrow
            )
        );
    }

    function _supplyOnAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.supply.selector,
                token,
                amount
            )
        );
    }

    function _borrowFromAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.borrow.selector,
                token,
                amount
            )
        );
    }

    function _repayOnAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.repay.selector,
                token,
                amount
            )
        );
    }

    function _withdrawFromAave(address token, uint256 amount) internal {
        _delegateCall(
            aaveV3Adapter,
            abi.encodeWithSelector(
                IEtherFiCashAaveV3Adapter.withdraw.selector,
                token,
                amount
            )
        );
    }

    function _supportCollateralToken(address token) internal {
        if (token == address(0)) revert InvalidValue();

        if (_collateralTokenIndexPlusOne[token] != 0)
            revert AlreadyCollateralToken();

        _supportedCollateralTokens.push(token);
        _collateralTokenIndexPlusOne[token] = _supportedCollateralTokens.length;

        emit CollateralTokenAdded(token);
    }

    function _supportBorrowToken(address token) internal {
        if (token == address(0)) revert InvalidValue();

        if (_borrowTokenIndexPlusOne[token] != 0) revert AlreadyBorrowToken();

        _supportedBorrowTokens.push(token);
        _borrowTokenIndexPlusOne[token] = _supportedBorrowTokens.length;

        emit BorrowTokenAdded(token);
    }

    function _setLiquidationThreshold(uint256 newThreshold) internal {
        emit LiquidationThresholdUpdated(_liquidationThreshold, newThreshold);
        _liquidationThreshold = newThreshold;
    }

    function _setBorrowApyPerSecond(
        uint256 apy
    ) internal updateBorrowings(address(0)) {
        if (apy > MAX_BORROW_APY) revert BorrowApyGreaterThanMaxAllowed();

        emit BorrowApySet(_borrowApyPerSecond, apy);
        _borrowApyPerSecond = apy;
    }

    function _getAmountWithInterest(
        uint256 amountBefore,
        uint256 accInterestAlreadyAdded
    ) internal view returns (uint256) {
        return
            ((1e18 *
                (amountBefore *
                    (debtInterestIndexSnapshot() - accInterestAlreadyAdded))) /
                1e20 +
                1e18 *
                amountBefore) / 1e18;
    }

    function _convertToSixDecimals(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        uint8 tokenDecimals = getDecimals(token);
        return
            tokenDecimals == 6 ? amount : (amount * 1e6) / 10 ** tokenDecimals;
    }

    modifier updateBorrowings(address user) {
        uint256 totalBorrowingAmtBeforeInterest = _totalBorrowingAmount;

        uint256 accInterestAlreadyStored = _debtInterestIndexSnapshot;
        _debtInterestIndexSnapshot = debtInterestIndexSnapshot();
        _totalBorrowingAmount = totalBorrowingAmount();
        _debtInterestIndexSnapshotTimestamp = block.timestamp;

        if (totalBorrowingAmtBeforeInterest != _totalBorrowingAmount)
            emit TotalBorrowingUpdated(
                totalBorrowingAmtBeforeInterest,
                _totalBorrowingAmount
            );

        if (user != address(0)) {
            uint256 userBorrowingsBefore = _userBorrowings[user];
            _userBorrowings[user] = borrowingOf(user);
            _usersDebtInterestIndexSnapshots[user] = _debtInterestIndexSnapshot;

            emit UserInterestAdded(
                user,
                userBorrowingsBefore,
                _userBorrowings[user]
            );
        }

        _;
    }

    function _delegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        require(target != address(this), "delegatecall to self");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Perform delegatecall to the target contract
            let success := delegatecall(
                gas(),
                target,
                add(data, 0x20),
                mload(data),
                0,
                0
            )

            // Get the size of the returned data
            let size := returndatasize()

            // Allocate memory for the return data
            result := mload(0x40)

            // Set the length of the return data
            mstore(result, size)

            // Copy the return data to the allocated memory
            returndatacopy(add(result, 0x20), 0, size)

            // Update the free memory pointer
            mstore(0x40, add(result, add(0x20, size)))

            if iszero(success) {
                revert(result, returndatasize())
            }
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
