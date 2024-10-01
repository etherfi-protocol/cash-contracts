// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)
pragma solidity ^0.8.24;
interface IEtherFiCashAaveV3Adapter {
    struct AaveAccountData {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold; // ltv liquidation threshold in basis points
        uint256 ltv; // loan to value ration in basis points
        uint256 healthFactor;
    }

    event AaveV3Process(
        address assetToSupply,
        uint256 amountToSupply,
        address assetToBorrow,
        uint256 amountToBorrow
    );

    error InvalidRateMode();

    /**
     * @notice Function to supply and borrow via Aave V3.
     * @param assetToSupply Address of the asset to supply.
     * @param amountToSupply Amount of the asset to supply.
     * @param assetToBorrow Address of the asset to borrow.
     * @param amountToBorrow Amount of the asset to borrow.
     */
    function process(
        address assetToSupply,
        uint256 amountToSupply,
        address assetToBorrow,
        uint256 amountToBorrow
    ) external;

    /**
     * @notice Function to supply funds to Aave V3.
     * @param asset Address of the asset to supply.
     * @param amount Amount of the asset to supply.
     */
    function supply(address asset, uint256 amount) external;

    /**
     * @notice Function to borrow funds from Aave V3.
     * @param asset Address of the asset to borrow.
     * @param amount Amount of the asset to borrow.
     */
    function borrow(address asset, uint256 amount) external;

    /**
     * @notice Function to repay funds to Aave V3.
     * @param asset Address of the asset to repay.
     * @param amount Amount of the asset to repay.
     */
    function repay(address asset, uint256 amount) external;

    /**
     * @notice Function to withdraw funds from Aave V3.
     * @param asset Address of the asset to withdraw.
     * @param amount Amount of the asset to withdraw.
     */
    function withdraw(address asset, uint256 amount) external;

    /**
     * @notice Function to set e-mode category on Aave V3.
     * @param categoryId CategoryId of the e-mode.
     */
    function setEModeCategory(uint8 categoryId) external;

    /**
     * @notice Function to get the account data for a user.
     * @param user Address of the user.
     * @return AaveAccountData struct.
     */
    function getAccountData(
        address user
    ) external view returns (AaveAccountData memory);

    /**
     * @dev Get total debt balance for an asset.
     * @param user Address of the user.
     * @param token Address of the debt token.
     * @return debt Amount of debt.
     */
    function getDebt(
        address user,
        address token
    ) external view returns (uint256 debt);

    /**
     * @dev Get total collateral balance for an asset.
     * @param user Address of the user.
     * @param token Address of the token used as collateral.
     * @return balance Amount fo collateral balance.
     */
    function getCollateralBalance(
        address user,
        address token
    ) external view returns (uint256 balance);
}
