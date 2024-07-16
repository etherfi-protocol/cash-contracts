// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


interface IL2DebtManager {
    // --------------
    // Admin functions
    // --------------
    function setLiquidationThreshold(uint256 newThreshold) external;


    function liquidate(address user) external;

    // function transferUSDC(uint256 amount, address to) external;

    // --------------
    // User functions
    // --------------

    // Deposit of Collateral eETH from Users
    function depositEETH(address user, uint256 amount) external;

    // Debt and collateral 
    function collateralOf(address user) external view returns (uint256);
    function borrowingOf(address user) external view returns (uint256);
    function debtRatioOf(address user) external view returns (uint256);

    // Repayment
    function repayWithUSDC(uint256 repayUsdcAmount) external;
    function repayWithEETH(uint256 repayUsdcAmount) external;

    // --------------
    // View functions
    // --------------

    // Query for liquidated collateral
    function liquidEEthAmount() external view returns (uint256);
    function liquidUsdcAmount() external view returns (uint256);
    function totalCollateralAmount() external view returns (uint256);
    function totalBorrowingAmount() external view returns (uint256);

    // Additional helper functions may be added here as necessary
}
