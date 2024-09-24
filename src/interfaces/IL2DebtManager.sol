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

    struct BorrowTokenConfigData {
        uint64 borrowApy;
        uint128 minShares;
    }

    struct BorrowTokenConfig {
        uint256 interestIndexSnapshot;
        uint256 totalBorrowingAmount;
        uint256 totalSharesOfBorrowTokens;
        uint64 lastUpdateTimestamp;
        uint64 borrowApy;
        uint128 minShares;
    }

    struct CollateralTokenConfig {
        uint80 ltv;
        uint80 liquidationThreshold;
        uint96 liquidationBonus;
        uint256 supplyCap;
    }

    struct TokenData {
        address token;
        uint256 amount;
    }

    struct LiquidationTokenData {
        address token;
        uint256 amount;
        uint256 liquidationBonus;
    }

    event SuppliedUSDC(uint256 amount);
    event DepositedCollateral(
        address indexed depositor,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Supplied(
        address indexed sender,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 borrowUsdcAmount
    );
    event Repaid(
        address indexed user,
        address indexed payer,
        address indexed token,
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
        address indexed liquidator,
        address indexed user,
        address indexed debtTokenToLiquidate,
        TokenData[] beforeCollateralAmount,
        LiquidationTokenData[] userCollateralLiquidated,
        uint256 beforeDebtAmount,
        uint256 debtAmountLiquidated
    );
    event LiquidationThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    );
    event CollateralTokenAdded(address token);
    event CollateralTokenRemoved(address token);
    event BorrowTokenAdded(address token);
    event BorrowTokenRemoved(address token);
    event BorrowApySet(address indexed token, uint256 oldApy, uint256 newApy);
    event MinSharesOfBorrowTokenSet(address indexed token, uint128 oldMinShares, uint128 newMinShares);
    event UserInterestAdded(
        address indexed user,
        uint256 borrowingAmtBeforeInterest,
        uint256 borrowingAmtAfterInterest
    );
    event TotalBorrowingUpdated(
        address indexed borrowToken,
        uint256 totalBorrowingAmtBeforeInterest,
        uint256 totalBorrowingAmtAfterInterest
    );
    event WithdrawCollateral(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event AccountClosed(address indexed user, TokenData[] collateralWithdrawal);
    event BorrowTokenConfigSet(address indexed token, BorrowTokenConfig config);
    event CollateralTokenConfigSet(
        address indexed collateralToken,
        CollateralTokenConfig oldConfig,
        CollateralTokenConfig newConfig
    );
    event WithdrawBorrowToken(
        address indexed withdrawer,
        address indexed borrowToken,
        uint256 amount
    );

    error UnsupportedCollateralToken();
    error UnsupportedRepayToken();
    error UnsupportedBorrowToken();
    error InsufficientCollateral();
    error InsufficientCollateralToRepay();
    error InsufficientLiquidity();
    error CannotLiquidateYet();
    error ZeroCollateralValue();
    error OnlyUserCanRepayWithCollateral();
    error InvalidValue();
    error AlreadyCollateralToken();
    error AlreadyBorrowToken();
    error NotACollateralToken();
    error NoCollateralTokenLeft();
    error NotABorrowToken();
    error NoBorrowTokenLeft();
    error ArrayLengthMismatch();
    error TotalCollateralAmountNotZero();
    error InsufficientLiquidityPleaseTryAgainLater();
    error LiquidAmountLesserThanRequired();
    error ZeroTotalBorrowTokens();
    error InsufficientBorrowShares();
    error UserStillLiquidatable();
    error TotalBorrowingsForUserNotZero();
    error BorrowTokenConfigAlreadySet();
    error AccountUnhealthy();
    error BorrowTokenStillInTheSystem();
    error RepaymentAmountIsZero();
    error LiquidatableAmountIsZero();
    error LtvCannotBeGreaterThanLiquidationThreshold();
    error OraclePriceZero();
    error BorrowAmountZero();
    error SharesCannotBeZero();
    error SharesCannotBeLessThanMinShares();
    error SupplyCapBreached();
    error OnlyUserSafe();
    error AaveAdapterNotSet();

    /**
     * @notice Function to fetch the address of the Cash Data Provider.
     * @return Cash Data Provider address
     */
    function cashDataProvider() external view returns (address);

    /**
     * @notice Function to fetch the debt interest index snapshot.
     * @param  borrowToken Address of the borrow token.
     * @return debt interest index snapshot
     */
    function debtInterestIndexSnapshot(
        address borrowToken
    ) external view returns (uint256);

    /**
     * @notice Function to fetch the borrow APY per second with 18 decimals.
     * @param borrowToken Address of the borrow token.
     * @return Borrow APY per second. Eg: 0.0001% -> 0.0001e18
     */
    function borrowApyPerSecond(
        address borrowToken
    ) external view returns (uint64);

    /**
     * @notice Function to fetch the min shares of borrow token that can be minted by a supplier.
     * @param borrowToken Address of the borrow token.
     * @return minShares
     */
    function borrowTokenMinShares(
        address borrowToken
    ) external view returns (uint128);

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
     * @notice Function to add support for a new collateral token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the token to be supported as collateral.
     * @param config Collateral token config.
     */
    function supportCollateralToken(
        address token,
        CollateralTokenConfig memory config
    ) external;

    /**
     * @notice Function to set the borrow APY per second for a borrow token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the borrow token.
     * @param apy Borrow APY per seconds with 18 decimals.
     */
    function setBorrowApy(address token, uint64 apy) external;

    /**
     * @notice Function to set min borrow token shares to mint. 
     * @notice Implemented to prevent inflation attacks.
     * @param token Address of the borrow token.
     * @param shares Min shares of that borrow token to mint. 
     */
    function setMinBorrowTokenShares(
        address token,
        uint128 shares
    ) external;

    /**
     * @notice Function to set the collateral token config.
     * @param __collateralToken Address of the collateral token.
     * @param __config Collateral token config.
     */
    function setCollateralTokenConfig(
        address __collateralToken,
        CollateralTokenConfig memory __config
    ) external;

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
     * @param borrowApy Borrow APY per second in 18 decimals.
     */
    function supportBorrowToken(address token, uint64 borrowApy, uint128 minBorrowTokenShares) external;

    /**
     * @notice Function to remove support for a borrow token.
     * @dev Can only be called by an address with the ADMIN_ROLE.
     * @param token Address of the token to be unsupported as borrow.
     */
    function unsupportBorrowToken(address token) external;

    /**
     * @notice Function to supply borrow tokens to the debt manager.
     * @param  user Address of the user to register for supply.
     * @param  borrowToken Address of the borrow token to supply.
     * @param  amount Amount of the borrow token to supply.
     */
    function supply(address user, address borrowToken, uint256 amount) external;

    /**
     * @notice Function to withdraw the borrow tokens.
     * @param  borrowToken Address of the borrow token.
     * @param  amount Amount of the borrow token to withdraw.
     */
    function withdrawBorrowToken(address borrowToken, uint256 amount) external;

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
     * @notice Function to withdraw collateral from the Debt Manager.
     * @param  token Address of the collateral token to withdraw.
     * @param  amount Amount of the collateral token to withdraw.
     */
    function withdrawCollateral(address token, uint256 amount) external;

    /**
     * @notice Function to close account with the Debt Manager.
     * @notice All the debt should already be repaid before this function can be called.
     * @notice Withdraws the remaining user's collateral to the User Safe.
     */
    function closeAccount() external;

    // https://docs.aave.com/faq/liquidations
    /**
     * @notice Liquidate the user's debt by repaying the partial/entire debt using the collateral.
     * @notice If user's 50% debt is repaid and user is healthy, then only 50% will be repaid. Otherwise entire debt is repaid.
     * @dev do we need to add penalty?
     * @param  user Address of the user to liquidate.
     * @param  borrowToken Borrow token address to liquidate.
     * @param  collateralTokensPreference Preference of order of collateral tokens to liquidate the user for.
     */
    function liquidate(
        address user,
        address borrowToken,
        address[] memory collateralTokensPreference
    ) external;

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
     * @notice Function to fetch the borrowing amount of the user for a borrow token.
     * @param  user Address of the user.
     * @param  borrowToken Address of the borrow token.
     * @return Borrow amount with interest.
     */
    function borrowingOf(
        address user,
        address borrowToken
    ) external view returns (uint256);

    /**
     * @notice Function to fetch the borrowing amount of the user for a all the borrow tokens.
     * @param  user Address of the user.
     * @return Array of TokenData struct, total borrow amount in usdc.
     */
    function borrowingOf(
        address user
    ) external view returns (TokenData[] memory, uint256);

    /**
     * @notice Function to fetch the max borrow amount for liquidation purpose.
     * @notice Calculates user's total collateral amount in USDC and finds max borrowable amount using liquidation threshold.
     * @param  user Address of the user.
     * @param  forLtv For ltv, pass true and for liquidation, pass false.
     * @return Max borrow amount for liquidation purpose.
     */
    function getMaxBorrowAmount(
        address user,
        bool forLtv
    ) external view returns (uint256);

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
     * @notice Function to fetch the liquid stable amounts in the contract.
     * @notice Calculated as the stable balances of the contract.
     * @return Liquid stable amounts in TokenData array format.
     */
    function liquidStableAmount() external view returns (TokenData[] memory);

    /**
     * @notice Function to get the withdrawable amount of borrow tokens for a supplier.
     * @param  supplier Address of the supplier.
     * @param  borrowToken Address of the borrow token.
     * @return Amount of borrow tokens the supplier can withdraw.
     */
    function withdrawableBorrowToken(
        address supplier,
        address borrowToken
    ) external view returns (uint256);


    /**
     * @notice Function to get the withdrawable amount of borrow tokens for a supplier.
     * @param  supplier Address of the supplier.
     * @return Array of borrow tokens addresses and respective amounts.
     * @return Total amount in USD.
     */
    function withdrawableBorrowToken(
        address supplier
    ) external view returns (TokenData[] memory, uint256);

    /**
     * @notice Function to fetch the total supplies for a borrow token.
     * @param borrowToken Address of the borrow token.
     * @return Total amount supplied.
     */
    function totalSupplies(address borrowToken) external view returns (uint256);

    /**
     * @notice Function to fetch the total supplies for each borrow token.
     * @return Total amount supplied for each borrow token.
     * @return Total amount supplied in USD combined.
     */
    function totalSupplies() external view returns (TokenData[] memory, uint256);

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
     * @notice Function to fetch the total borrowing amount for a token from this contract.
     * @param  borrowToken Address of the borrow token.
     * @return Total borrowing amount in debt token with 6 decimals.
     */
    function totalBorrowingAmount(
        address borrowToken
    ) external view returns (uint256);

    /**
     * @notice Function to fetch the total borrowing amounts from this contract.
     * @return Array of borrow tokens with respective amount in USDC.
     * @return Total borrowing amount in USDC.
     */
    function totalBorrowingAmounts()
        external
        view
        returns (TokenData[] memory, uint256);

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
     * @notice Function to fetch the borrow token config.
     * @param  borrowToken Address of the borrow token.
     * @return BorrowTokenConfig struct.
     */
    function borrowTokenConfig(
        address borrowToken
    ) external view returns (BorrowTokenConfig memory);

    /**
     * @notice Function to fetch the collateral token config.
     * @param  collateralToken Address of the collateral token.
     * @return CollateralTokenConfig.
     */
    function collateralTokenConfig(
        address collateralToken
    ) external view returns (CollateralTokenConfig memory);

    /**
     * @notice Function to fetch the current state of collaterals and borrowings.
     * @return totalCollaterals Array of collaterals in tuple(address token, uint256 amount) format.
     * @return totalCollateralInUsdc Total collateral value in USDC.
     * @return borrowings Array of borrowings in tuple(address token, uint256 amount) format.
     * @return totalBorrowings Total borrowing value in USDC.
     * @return totalLiquidCollateralAmounts Total liquid collateral amounts in tuple(address token, uint256 amount) format.
     * @return totalLiquidStableAmounts Total liquid stable amounts in tuple(address token, uint256 amount) format.
     */
    function getCurrentState()
        external
        view
        returns (
            TokenData[] memory totalCollaterals,
            uint256 totalCollateralInUsdc,
            TokenData[] memory borrowings,
            uint256 totalBorrowings,
            TokenData[] memory totalLiquidCollateralAmounts,
            TokenData[] memory totalLiquidStableAmounts
        );

    /**
     * @notice Function to fetch the current state of a user.
     * @return totalCollaterals Array of collaterals in tuple(address token, uint256 amount) format.
     * @return totalCollateralInUsdc Total collateral value in USDC.
     * @return borrowings Array of borrowings in tuple(address token, uint256 amount) format.
     * @return totalBorrowings Total borrowing value in USDC.
     */
    function getUserCurrentState(address user)
        external
        view
        returns (
            TokenData[] memory totalCollaterals,
            uint256 totalCollateralInUsdc,
            TokenData[] memory borrowings,
            uint256 totalBorrowings
        );
}
