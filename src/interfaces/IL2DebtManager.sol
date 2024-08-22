// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IL2DebtManager {
    enum MarketOperationType {
        Supply,
        Borrow,
        Repay,
        Withdraw,
        SupplyAndBorrow
    }

    struct TokenData {
        address token;
        uint256 amount;
    }

    event SuppliedUSDC(uint256 amount);
    event DepositedCollateral(
        address indexed depositor,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 borrowUsdcAmount
    );
    event RepaidWithUSDC(
        address indexed user,
        address indexed payer,
        uint256 repaidUsdcDebtAmount
    );
    event RepaidWithCollateralToken(
        address indexed user,
        address indexed payer,
        address indexed collateralToken,
        uint256 beforeCollateralAmount,
        uint256 afterCollateralAmount,
        uint256 repaidUsdcDebtAmount
    );
    event RepaidWithCollateral(
        address indexed user,
        uint256 repaidUsdcDebtAmount,
        TokenData[] collateralUsed
    );
    event Liquidated(
        address indexed user,
        TokenData[] beforeCollateralAmount,
        TokenData[] afterCollateralAmount,
        uint256 beforeDebtAmount
    );
    event LiquidationThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    );
    event CollateralTokenAdded(address token);
    event CollateralTokenRemoved(address token);
    event BorrowTokenAdded(address token);
    event BorrowTokenRemoved(address token);
    event BorrowApySet(uint256 oldApy, uint256 newApy);
    event UserInterestAdded(
        address indexed user,
        uint256 borrowingAmtBeforeInterest,
        uint256 borrowingAmtAfterInterest
    );
    event TotalBorrowingUpdated(
        uint256 totalBorrowingAmtBeforeInterest,
        uint256 totalBorrowingAmtAfterInterest
    );
    event WithdrawCollateral(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event AccountClosed(
        address indexed user,
        uint256 borrowingsRepaid,
        TokenData[] collateralWithdrawal
    );

    error UnsupportedCollateralToken();
    error UnsupportedRepayToken();
    error UnsupportedBorrowToken();
    error InsufficientCollateral();
    error InsufficientCollateralToRepay();
    error InsufficientLiquidity();
    error CannotLiquidateYet();
    error ZeroCollateralValue();
    error CannotPayMoreThanDebtIncurred();
    error InvalidMarketOperationType();
    error OnlyUserCanRepayWithCollateral();
    error InvalidValue();
    error AlreadyCollateralToken();
    error AlreadyBorrowToken();
    error NotACollateralToken();
    error NoCollateralTokenLeft();
    error NotABorrowToken();
    error NoBorrowTokenLeft();
    error ArrayLengthMismatch();
    error BorrowApyGreaterThanMaxAllowed();
    error TotalCollateralAmountNotZero();
    error InsufficientLiquidityPleaseTryAgainLater();
    error AaveAdapterNotSet();

    /**
     * @notice Function to fetch the debt interest index snapshot.
     * @return debt interest index snapshot
     */
    function debtInterestIndexSnapshot() external view returns (uint256);

    /**
     * @notice Function to fetch the borrow APY per second with 18 decimals.
     * @notice Borrow APY per second. Eg: 0.0001% -> 0.0001e18
     */
    function borrowApyPerSecond() external view returns (uint256);

    /**
     * @notice Function to fetch the array of collateral tokens.
     * @return Array of collateral tokens.
     */
    function getCollateralTokens() external view returns (address[] memory);

    /**
     * @notice Function to fetch the array of borrow tokens.
     * @return Array of borrow tokens.
     */
    function getBorrowTokens() external view returns (address[] memory);

    /**
     * @notice Function to check whether a token is a collateral token.
     * @return Boolean value suggesting if token is a collateral token.
     */
    function isCollateralToken(address token) external view returns (bool);

    /**
     * @notice Function to check whether a token is a borrow token.
     * @return Boolean value suggesting if token is a borrow token.
     */
    function isBorrowToken(address token) external view returns (bool);

    /**
     * @notice Function to set the borrow APY per second.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param apy New borrow apy per second with 18 decimals. For eg: 0.001% -> 0.001 * 1e18
     */
    function setBorrowApyPerSecond(uint256 apy) external;

    /**
     * @notice Function to add support for a new collateral token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the token to be supported as collateral.
     */
    function supportCollateralToken(address token) external;

    /**
     * @notice Function to remove support for a collateral token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the token to be unsupported as collateral.
     */
    function unsupportCollateralToken(address token) external;

    /**
     * @notice Function to add support for a new borrow token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the token to be supported as borrow.
     */
    function supportBorrowToken(address token) external;

    /**
     * @notice Function to remove support for a borrow token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the token to be unsupported as borrow.
     */
    function unsupportBorrowToken(address token) external;

    /**
     * @notice Function to deposit collateral into this contract.
     * @param  token Address of the token to deposit.
     * @param  user Address of the user safe to deposit collateral for.
     * @param  amount Amount of the token to deposit.
     */
    function depositCollateral(
        address token,
        address user,
        uint256 amount
    ) external;

    /**
     * @notice Function for users to borrow funds for payment using the deposited collateral.
     * @notice Borrowed tokens are transferred to the `etherFiCashSafe`
     * @param  token Address of the token to borrow.
     * @param  amount Amount of the token to borrow.
     */
    function borrow(address token, uint256 amount) external;

    /**
     * @notice Function for users to repay the borrowed funds back to the debt manager.
     * @param  user Address of the user safe for whom the payment is made.
     * @param  token Address of the token in which repayment is done.
     * @param  repayDebtUsdcAmt Amount of debt to be repaid in USDC terms.
     */
    function repay(
        address user,
        address token,
        uint256 repayDebtUsdcAmt
    ) external;

    /**
     * @notice Function for users to repay the borrowed funds back to the debt manager using all the collateral user has.
     * @param  user Address of the user safe for whom the payment is made.
     * @param  repayDebtUsdcAmt Amount of debt to be repaid in USDC terms.
     */
    function repayWithCollateral(
        address user,
        uint256 repayDebtUsdcAmt
    ) external;

    /**
     * @notice Function to withdraw collateral from the Debt Manager.
     * @param  token Address of the collateral token to withdraw.
     * @param  amount Amount of the collateral token to withdraw.
     */
    function withdrawCollateral(address token, uint256 amount) external;

    /**
     * @notice Function to close account with the Debt Manager.
     * @notice Repays all the debt with user's collateral and withdraws the remaining collateral to the User Safe.
     */
    function closeAccount() external;

    // https://docs.aave.com/faq/liquidations
    /**
     * @notice Liquidate the user's debt by repaying the entire debt using the collateral.
     * @dev do we need to add penalty?
     * @param  user Address of the user to liquidate.
     */
    function liquidate(address user) external;

    /**
     * @notice Function to determine if a user is liquidatable.
     * @param  user Address of the user.
     * @return isLiquidatable boolean value.
     */
    function liquidatable(
        address user
    ) external view returns (bool isLiquidatable);

    /**
     * @notice Function to fetch the collateral amount for the user.
     * @param  user Address of the user.
     * @return Array of TokenData struct, total collateral amount in usdc.
     */
    function collateralOf(
        address user
    ) external view returns (TokenData[] memory, uint256);

    /**
     * @notice Function to fetch the borrowing amount of the user.
     * @param  user Address of the user.
     * @return Borrow amount with interest.
     */
    function borrowingOf(address user) external view returns (uint256);

    /**
     * @notice Function to calculate the debt ratio for a user.
     * @notice Debt ratio is calculated as the ratio of the debt to the collateral value in USDC.
     * @param  user Address of the user.
     * @return Debt ratio in basis points.
     */
    function debtRatioOf(address user) external view returns (uint256);

    /**
     * @notice Function to determine the current borrowable amount in USDC for a user.
     * @param  user Address of the user.
     * @return Current borrowable amount for the user.
     */
    function remainingBorrowingCapacityInUSDC(
        address user
    ) external view returns (uint256);

    /**
     * @notice Function to fetch the liquid collateral amounts in the contract.
     * @notice Calculated as the collateral balance of the contract minus the total collateral amount in a token.
     * @return Liquid collateral amounts.
     */
    function liquidCollateralAmounts()
        external
        view
        returns (TokenData[] memory);

    /**
     * @notice Function to fetch the liquid stable amount in the contract.
     * @notice Calculated as the stable balances of the contract minus the total borrowing amount.
     * @return Liquid stable amount.
     */
    function liquidStableAmount() external view returns (uint256);

    /**
     * @notice Function to convert collateral token amount to equivalent USDC amount.
     * @param  collateralToken Address of collateral to convert.
     * @param  collateralAmount Amount of collateral token to convert.
     * @return Equivalent USDC amount.
     */
    function convertCollateralTokenToUsdc(
        address collateralToken,
        uint256 collateralAmount
    ) external view returns (uint256);

    /**
     * @notice Function to convert usdc amount to collateral token amount.
     * @param  collateralToken Address of the collateral token.
     * @param  debtUsdcAmount Amount of USDC for borrowing.
     * @return Amount of collateral required.
     */
    function convertUsdcToCollateralToken(
        address collateralToken,
        uint256 debtUsdcAmount
    ) external view returns (uint256);

    /**
     * @notice Function to fetch the value of collateral deposited by the user in USDC.
     * @param  user Address of the user.
     * @return Total collateral value in USDC for the user.
     */
    function getCollateralValueInUsdc(
        address user
    ) external view returns (uint256);

    /**
     * @notice Function to set the liquidation threshold.
     * @dev Can only be called by the owner of the contract.
     * @param newThreshold New liquidation threshold.
     */
    function setLiquidationThreshold(uint256 newThreshold) external;

    /**
     * @notice Function to manage funds via supply, borrow, repay and withdraw from market.
     * @notice Can only be called by an account with FUND_MANAGER_ROLE.
     * @param marketOperationType Market operation type.
     * @param data Data for the operation.
     */
    function fundManagementOperation(
        uint8 marketOperationType,
        bytes calldata data
    ) external;

    /**
     * @notice Function to fetch the user collateral for a particular token.
     * @param  user Address of the user.
     * @param  token Address of the token.
     * @return Amount of collateral in tokens.
     * @return Amount of collateral in USDC.
     */
    function getUserCollateralForToken(
        address user,
        address token
    ) external view returns (uint256, uint256);

    /**
     * @notice Function to fetch the liquidation threshold.
     * @return Liquidation threshold in basis points.
     */
    function liquidationThreshold() external view returns (uint256);

    /**
     * @notice Function to fetch the total borrowing amount from this contract.
     * @return Total borrowing amount in USDC.
     */
    function totalBorrowingAmount() external view returns (uint256);

    /**
     * @notice Function to fetch the total collateral amount in this contract.
     * @return Array of Collateral struct.
     * @return Total collateral in USDC.
     */
    function totalCollateralAmounts()
        external
        view
        returns (TokenData[] memory, uint256);

    /**
     * @notice Function to fetch the current state of collaterals and borrowings.
     * @return totalCollaterals Array of collaterals in tuple(address token, uint256 amount) format.
     * @return totalCollateralInUsdc Total collateral value in USDC.
     * @return totalBorrowings Total borrowing value in USDC.
     */
    function getCurrentState()
        external
        view
        returns (
            TokenData[] memory totalCollaterals,
            uint256 totalCollateralInUsdc,
            uint256 totalBorrowings,
            TokenData[] memory totalLiquidCollateralAmounts,
            uint256 totalLiquidStableAmounts
        );
}
