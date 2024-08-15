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

    struct Collateral {
        address token;
        uint256 amount;
    }

    event SuppliedUSDC(uint256 amount);
    event DepositedCollateral(
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
    event RepaidWithWeEth(
        address indexed user,
        uint256 repaidUsdcDebtAmount,
        uint256 repaidCollateralEEthAmount
    );
    event Liquidated(
        address indexed user,
        uint256 beforeCollateralAmount,
        uint256 afterCollateralAmount,
        uint256 beforeDebtAmount
    );
    event LiquidationThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
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

    /**
     * @notice Function to deposit collateral into this contract.
     * @param  token Address of the token to deposit.
     * @param  amount Amount of the token to deposit.
     */
    function depositCollateral(address token, uint256 amount) external;

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
     * @param  amount Amount of the token.
     */
    function repay(address user, address token, uint256 amount) external;

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
    function liquidatable(address user) external view returns (bool);

    /**
     * @notice Function to fetch the collateral amount for the user.
     * @param  user Address of the user.
     * @return array of Collateral struct, total collateral amount in usdc.
     */
    function collateralOf(
        address user
    ) external view returns (Collateral[] memory, uint256);

    /**
     * @notice Function to fetch the borrowing amount of the user.
     * @param  user Address of the user.
     * @return borrow amount.
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
     * @notice Function to fetch the liquid weETH amount in the contract.
     * @notice Calculated as the weETH balance of the contract minus the total collateral amount.
     * @return Liquid weETH amount.
     */
    function liquidWeEthAmount() external view returns (uint256);
    /**
     * @notice Function to fetch the liquid USDC amount in the contract.
     * @notice Calculated as the USDC balance of the contract minus the total borrowing amount.
     * @return Liquid weETH amount.
     */
    function liquidUsdcAmount() external view returns (uint256);

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
     * @notice Function to fetch the supported collateral tokens.
     * @return Array of addresses of supported collateral tokens.
     */
    function collateralTokens() external view returns (address[] memory);

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
        returns (Collateral[] memory, uint256);
}
