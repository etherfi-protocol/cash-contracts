// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DebtManagerStorage} from "./DebtManagerStorage.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";

contract DebtManagerCore is DebtManagerStorage {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function cashDataProvider() external view returns (address) {
        return address(_cashDataProvider);
    }

    function borrowTokenConfig(
        address borrowToken
    ) public view returns (BorrowTokenConfig memory) {
        BorrowTokenConfig memory config = _borrowTokenConfig[borrowToken];
        config.totalBorrowingAmount = _getAmountWithInterest(
            borrowToken,
            config.totalBorrowingAmount,
            config.interestIndexSnapshot
        );

        return config;
    }

    function collateralTokenConfig(
        address collateralToken
    ) external view returns (CollateralTokenConfig memory) {
        return _collateralTokenConfig[collateralToken];
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return _supportedCollateralTokens;
    }

    function getBorrowTokens() public view returns (address[] memory) {
        return _supportedBorrowTokens;
    }

    function getUserCollateralForToken(address user, address token) external view returns (uint256, uint256) {
        if (!isCollateralToken(token)) revert UnsupportedCollateralToken();
        uint256 collateralTokenAmt = IUserSafe(user).getUserCollateralForToken(token);
        uint256 collateralAmtInUsd = convertCollateralTokenToUsd(token, collateralTokenAmt);

        return (collateralTokenAmt, collateralAmtInUsd);
    }

    function totalBorrowingAmounts()
        public
        view
        returns (TokenData[] memory, uint256)
    {
        uint256 len = _supportedBorrowTokens.length;
        TokenData[] memory tokenData = new TokenData[](len);
        uint256 totalBorrowingAmt = 0;
        uint256 m = 0;

        for (uint256 i = 0; i < len; ) {
            BorrowTokenConfig memory config = borrowTokenConfig(
                _supportedBorrowTokens[i]
            );

            if (config.totalBorrowingAmount > 0) {
                tokenData[m] = TokenData({
                    token: _supportedBorrowTokens[i],
                    amount: config.totalBorrowingAmount
                });
                totalBorrowingAmt += config.totalBorrowingAmount;

                unchecked {
                    ++m;
                }
            } 

            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(tokenData, m)
        }

        return (tokenData, totalBorrowingAmt);
    }

    function liquidatable(address user) public view returns (bool) {
        (, uint256 userBorrowing) = borrowingOf(user);
        // Total borrowing in USD > total max borrowing of the user
        return userBorrowing > getMaxBorrowAmount(user, false);
    }

    function getMaxBorrowAmount(
        address user,
        bool forLtv
    ) public view returns (uint256) {
        uint256 totalMaxBorrow = 0;
        TokenData[] memory collateralTokens = IUserSafe(user).getUserTotalCollateral();
        uint256 len = collateralTokens.length;

        for (uint256 i = 0; i < len; ) {
            uint256 collateral = convertCollateralTokenToUsd(collateralTokens[i].token, collateralTokens[i].amount);
            if (forLtv)
                // user collateral for token in USD * 100 / liquidation threshold
                totalMaxBorrow += collateral.mulDiv(
                    _collateralTokenConfig[collateralTokens[i].token].ltv,
                    HUNDRED_PERCENT,
                    Math.Rounding.Floor
                );
            else
                totalMaxBorrow += collateral.mulDiv(
                    _collateralTokenConfig[collateralTokens[i].token].liquidationThreshold,
                    HUNDRED_PERCENT,
                    Math.Rounding.Floor
                );

            unchecked {
                ++i;
            }
        }

        return totalMaxBorrow;
    }

    function collateralOf(address user) public view returns (TokenData[] memory, uint256) {
        TokenData[] memory collateralTokens = IUserSafe(user).getUserTotalCollateral();
        uint256 len = collateralTokens.length;
        uint256 totalCollateralInUsd = 0;

        for (uint256 i = 0; i < len; ) {
            totalCollateralInUsd += convertCollateralTokenToUsd(collateralTokens[i].token, collateralTokens[i].amount);
            unchecked {
                ++i;
            }
        }

        return (collateralTokens, totalCollateralInUsd);
    }

    function getBorrowingPowerAndTotalBorrowing(address user) external view returns (uint256, uint256) {
        uint256 totalMaxBorrow = getMaxBorrowAmount(user, true);
        (, uint256 totalBorrowings) = borrowingOf(user);
        return (totalMaxBorrow, totalBorrowings);
    }

    // if user borrowings is greater than they can borrow as per LTV, revert
    function ensureHealth(address user) public view {
        (, uint256 totalBorrowings) = borrowingOf(user);
        if (totalBorrowings > getMaxBorrowAmount(user, true)) revert AccountUnhealthy();
    }

    function remainingBorrowingCapacityInUSD(
        address user
    ) public view returns (uint256) {
        uint256 maxBorrowingAmount = getMaxBorrowAmount(user, true);
        (, uint256 currentBorrowingWithInterest) = borrowingOf(user);

        return
            maxBorrowingAmount > currentBorrowingWithInterest
                ? maxBorrowingAmount - currentBorrowingWithInterest
                : 0;
    }

    function borrowApyPerSecond(
        address borrowToken
    ) external view returns (uint64) {
        return _borrowTokenConfig[borrowToken].borrowApy;
    }

    function borrowTokenMinShares(
        address borrowToken
    ) external view returns (uint128) {
        return _borrowTokenConfig[borrowToken].minShares;
    }

    function getCurrentState()
        public
        view
        returns (
            TokenData[] memory borrowings,
            uint256 totalBorrowingsInUsd,
            TokenData[] memory totalLiquidStableAmounts
        )
    {
        (borrowings, totalBorrowingsInUsd) = totalBorrowingAmounts();
        totalLiquidStableAmounts = _liquidStableAmounts();
    }

    function getUserCurrentState(address user)
        external
        view
        returns (
            TokenData[] memory totalCollaterals,
            uint256 totalCollateralInUsd,
            TokenData[] memory borrowings,
            uint256 totalBorrowings
        )
    {
        (totalCollaterals, totalCollateralInUsd) = collateralOf(user);
        (borrowings, totalBorrowings) = borrowingOf(user);
    }

    function supplierBalance(
        address supplier,
        address borrowToken
    ) public view returns (uint256) {
        if (_borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens == 0) return 0;

        return
            _sharesOfBorrowTokens[supplier][borrowToken].mulDiv(
                _getTotalBorrowTokenAmount(borrowToken),
                _borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens,
                Math.Rounding.Floor
            );
    }

    function supplierBalance(
        address supplier
    ) public view returns (TokenData[] memory, uint256) {
        uint256 len = _supportedBorrowTokens.length;
        TokenData[] memory suppliesData = new TokenData[](len);
        uint256 amountInUsd = 0;
        uint256 m = 0;

        for (uint256 i = 0; i < len; ) {
            address borrowToken = _supportedBorrowTokens[i];
            uint256 amount = supplierBalance(supplier, borrowToken);

            if (amount > 0) {
                amountInUsd += convertCollateralTokenToUsd(borrowToken, amount);
                suppliesData[m] = TokenData({
                    token: borrowToken,
                    amount: amount
                });
            
                unchecked {
                    ++m;
                }
            }
            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(suppliesData, m)
        }

        return (suppliesData, amountInUsd);
    }

    function totalSupplies(address borrowToken) public view returns (uint256) {
        return _getTotalBorrowTokenAmount(borrowToken);
    }

    function totalSupplies() external view returns (TokenData[] memory, uint256) {
        uint256 len = _supportedBorrowTokens.length;
        TokenData[] memory suppliesData = new TokenData[](len);
        uint256 amountInUsd = 0;
        uint256 m = 0;

        for (uint256 i = 0; i < len; ) {
            address borrowToken = _supportedBorrowTokens[i];
            uint256 totalSupplied = totalSupplies(borrowToken);
            if (totalSupplied > 0) {
                amountInUsd += convertCollateralTokenToUsd(borrowToken, totalSupplied);
                suppliesData[m] = TokenData({
                    token: borrowToken,
                    amount: totalSupplied
                });
                unchecked {
                    ++m;
                }
            }
            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(suppliesData, m)
        }

        return (suppliesData, amountInUsd);
    }

    function convertCollateralTokenToUsd(
        address collateralToken,
        uint256 collateralAmount
    ) public view returns (uint256) {
        if (!isCollateralToken(collateralToken)) revert UnsupportedCollateralToken();

        return
            (collateralAmount *
                IPriceProvider(_cashDataProvider.priceProvider()).price(
                    collateralToken
                )) / 10 ** _getDecimals(collateralToken);
    }

    function getCollateralValueInUsd(address user) public view returns (uint256) {
        uint256 userCollateralInUsd = 0;
        TokenData[] memory userCollateral = IUserSafe(user).getUserTotalCollateral();
        uint256 len = userCollateral.length;

        for (uint256 i = 0; i < len; ) {
            userCollateralInUsd += convertCollateralTokenToUsd(userCollateral[i].token, userCollateral[i].amount);
            unchecked {
                ++i;
            }
        }

        return userCollateralInUsd;
    }

    function supply(
        address user,
        address borrowToken,
        uint256 amount
    ) external nonReentrant {
        if (!isBorrowToken(borrowToken)) revert UnsupportedBorrowToken();
        if (_cashDataProvider.isUserSafe(user)) revert UserSafeCannotSupplyDebtTokens();
        
        uint256 shares = _borrowTokenConfig[borrowToken]
            .totalSharesOfBorrowTokens == 0
            ? amount
            : amount.mulDiv(
                _borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens,
                _getTotalBorrowTokenAmount(borrowToken),
                Math.Rounding.Floor
            );

        if (shares < _borrowTokenConfig[borrowToken].minShares)
            revert SharesCannotBeLessThanMinShares();

        _sharesOfBorrowTokens[user][borrowToken] += shares;
        _borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens += shares;

        // Moving this before state update to prevent reentrancy
        IERC20(borrowToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Supplied(msg.sender, user, borrowToken, amount);
    }
    
    function withdrawBorrowToken(address borrowToken, uint256 amount) external {
        uint256 totalBorrowTokenAmt = _getTotalBorrowTokenAmount(borrowToken);
        if (totalBorrowTokenAmt == 0) revert ZeroTotalBorrowTokens();

        uint256 shares = amount.mulDiv(
            _borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens,
            totalBorrowTokenAmt,
            Math.Rounding.Ceil
        );

        if (shares == 0) revert SharesCannotBeZero();
        if (_sharesOfBorrowTokens[msg.sender][borrowToken] < shares) revert InsufficientBorrowShares();

        uint256 sharesLeft = _borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens - shares;
        if (sharesLeft != 0 && sharesLeft < _borrowTokenConfig[borrowToken].minShares) revert SharesCannotBeLessThanMinShares();

        _sharesOfBorrowTokens[msg.sender][borrowToken] -= shares;
        _borrowTokenConfig[borrowToken].totalSharesOfBorrowTokens = sharesLeft;

        IERC20(borrowToken).safeTransfer(msg.sender, amount);
        emit WithdrawBorrowToken(msg.sender, borrowToken, amount);
    }

    function borrow(address token, uint256 amount) external onlyUserSafe {
        if (!isBorrowToken(token)) revert UnsupportedBorrowToken();
        _updateBorrowings(msg.sender, token);

        // Convert amount to 6 decimals before adding to borrowings
        uint256 borrowAmt = convertCollateralTokenToUsd(token, amount);
        if (borrowAmt == 0) revert BorrowAmountZero();

        _userBorrowings[msg.sender][token] += borrowAmt;
        _borrowTokenConfig[token].totalBorrowingAmount += borrowAmt;

        ensureHealth(msg.sender);

        if (IERC20(token).balanceOf(address(this)) < amount) revert InsufficientLiquidity();
        IERC20(token).safeTransfer(_cashDataProvider.settlementDispatcher(), amount);

        emit Borrowed(msg.sender, token, amount);
    }

    function repay(
        address user,
        address token,
        uint256 amount
    ) external nonReentrant {
        if (!_cashDataProvider.isUserSafe(user)) revert NotAUserSafe();
        _updateBorrowings(user, token);

        uint256 repayDebtUsdAmt = convertCollateralTokenToUsd(token, amount);
        if (_userBorrowings[user][token] < repayDebtUsdAmt) {
            repayDebtUsdAmt = _userBorrowings[user][token];
            amount = convertUsdToCollateralToken(token, repayDebtUsdAmt);
        }
        if (repayDebtUsdAmt == 0) revert RepaymentAmountIsZero();

        // if (!isBorrowToken(token)) revert UnsupportedRepayToken();
        _repayWithBorrowToken(token, user, amount, repayDebtUsdAmt);
    }

    function liquidate(address user, address borrowToken, address[] memory collateralTokensPreference) external nonReentrant {
        _updateBorrowings(user);
        if (!isBorrowToken(borrowToken)) revert UnsupportedBorrowToken();
        if (!liquidatable(user)) revert CannotLiquidateYet();

        _liquidateUser(user, borrowToken, collateralTokensPreference);

    }

    function _liquidateUser(
        address user,
        address borrowToken,
        address[] memory collateralTokensPreference
    ) internal {
        uint256 debtAmountToLiquidateInUsd = _userBorrowings[user][borrowToken].ceilDiv(2);
        _liquidate(user, borrowToken, collateralTokensPreference, debtAmountToLiquidateInUsd);

        if (liquidatable(user)) _liquidate(user, borrowToken, collateralTokensPreference, _userBorrowings[user][borrowToken]);
    }

    function _liquidate(
        address user,
        address borrowToken,
        address[] memory collateralTokensPreference,
        uint256 debtAmountToLiquidateInUsd
    ) internal {    
        IUserSafe(user).preLiquidate();
        if (debtAmountToLiquidateInUsd == 0) revert LiquidatableAmountIsZero();

        uint256 beforeDebtAmount = _userBorrowings[user][borrowToken];

        (LiquidationTokenData[] memory collateralTokensToSend, uint256 remainingDebt) = _getCollateralTokensForDebtAmount(
            user,
            debtAmountToLiquidateInUsd,
            collateralTokensPreference
        );

        IUserSafe(user).postLiquidate(msg.sender, collateralTokensToSend);

        uint256 liquidatedAmt = debtAmountToLiquidateInUsd - remainingDebt;
        _userBorrowings[user][borrowToken] -= liquidatedAmt;
        _borrowTokenConfig[borrowToken].totalBorrowingAmount -= liquidatedAmt;

        IERC20(borrowToken).safeTransferFrom(msg.sender, address(this), convertUsdToCollateralToken(borrowToken, liquidatedAmt));

        emit Liquidated(
            msg.sender,
            user,
            borrowToken,
            collateralTokensToSend,
            beforeDebtAmount,
            liquidatedAmt
        );
    }

    /// Users repay the borrowed USD in USD
    function _repayWithBorrowToken(address token, address user, uint256 amount, uint256 repayDebtUsdAmt) internal {
        _userBorrowings[user][token] -= repayDebtUsdAmt;
        _borrowTokenConfig[token].totalBorrowingAmount -= repayDebtUsdAmt;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Repaid(user, msg.sender, token, repayDebtUsdAmt);
    }

    function _getCollateralTokensForDebtAmount(
        address user,
        uint256 repayDebtUsdAmt,
        address[] memory collateralTokenPreference
    ) internal view returns (LiquidationTokenData[] memory, uint256 remainingDebt) {
        uint256 len = collateralTokenPreference.length;
        LiquidationTokenData[] memory collateral = new LiquidationTokenData[](len);

        for (uint256 i = 0; i < len; ) {
            address collateralToken = collateralTokenPreference[i];
            uint256 collateralAmountForDebt = convertUsdToCollateralToken(
                collateralToken,
                repayDebtUsdAmt
            );
            uint256 totalCollateral = IERC20(collateralToken).balanceOf(user);
            uint256 maxBonus = (totalCollateral * _collateralTokenConfig[collateralToken].liquidationBonus) / HUNDRED_PERCENT;

            if (totalCollateral - maxBonus < collateralAmountForDebt) {
                uint256 liquidationBonus = maxBonus;
                collateral[i] = LiquidationTokenData({
                    token: collateralToken,
                    amount: totalCollateral, 
                    liquidationBonus: liquidationBonus
                });

                uint256 usdValueOfCollateral = convertCollateralTokenToUsd(
                    collateralToken,
                    totalCollateral - liquidationBonus
                );

                repayDebtUsdAmt -= usdValueOfCollateral;
            } else {
                uint256 liquidationBonus = 
                    (collateralAmountForDebt * _collateralTokenConfig[collateralToken].liquidationBonus) / HUNDRED_PERCENT;

                collateral[i] = LiquidationTokenData({
                    token: collateralToken,
                    amount: collateralAmountForDebt + liquidationBonus,
                    liquidationBonus: liquidationBonus
                });

                repayDebtUsdAmt = 0;
            }

            if (repayDebtUsdAmt == 0) {
                uint256 arrLen = i + 1;
                assembly("memory-safe") {
                    mstore(collateral, arrLen)
                }

                break;
            }

            unchecked {
                ++i;
            }
        }

        return (collateral, repayDebtUsdAmt);
    }

    /**
     * @notice Function to fetch the liquid stable amounts in the contract.
     * @notice Calculated as the stable balances of the contract.
     * @return Liquid stable amounts in TokenData array format.
     */
    function _liquidStableAmounts() internal view returns (TokenData[] memory) {
        uint256 len = _supportedBorrowTokens.length;
        TokenData[] memory tokenData = new TokenData[](len);
        uint256 m = 0;

        uint256 totalStableBalances = 0;
        for (uint256 i = 0; i < len; ) {
            uint256 bal = IERC20(_supportedBorrowTokens[i]).balanceOf(
                address(this)
            );

            if (bal > 0) {
                tokenData[m] = TokenData({
                    token: _supportedBorrowTokens[i],
                    amount: bal
                });
                totalStableBalances += bal;
                unchecked {
                    ++m;
                }
            }

            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(tokenData, m)
        }

        return tokenData;
    }

    function _isUserSafe() internal view {
        if (!_cashDataProvider.isUserSafe(msg.sender)) revert OnlyUserSafe();
    }

    modifier onlyUserSafe() {
        _isUserSafe();
        _;
    }

    /**
     * @dev Falldown to the admin implementation
     * @notice This is a catch all for all functions not declared in core
     */
    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        bytes32 slot = adminImplPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly("memory-safe") {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(
                gas(),
                sload(slot),
                0,
                calldatasize(),
                0,
                0
            )

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}