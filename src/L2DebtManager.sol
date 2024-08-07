// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IL2DebtManager.sol";

// Consider directly inheriting AAVA pool or routing relevant calls to AAVA pool
contract L2DebtManager is IL2DebtManager {
    mapping(address => uint256) private _collaterals;
    mapping(address => uint256) private _borrowings;

    uint256 public totalCollateralAmount;
    uint256 public totalBorrowingAmount;

    IERC20 public eETH;
    IERC20 public USDC;

    uint256 public liquidationThreshold;

    address public etherFiCashSafe;

    uint256 private eEthPriceInUSDC; // todo: replace it with Oracle

    event SuppliedUSDC(uint256 amount);
    event DepositedCollateral(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 borrowUsdcAmount);
    event RepaidWithUSDC(address indexed user, uint256 repaidUsdcDebtAmount);
    event RepaidWithEETH(
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

    constructor(address _eETH, address _USDC, address _etherFiCashSafe) {
        eETH = IERC20(_eETH);
        USDC = IERC20(_USDC);
        etherFiCashSafe = _etherFiCashSafe;
    }

    function supplyUSDC(uint256 amount) external {
        SafeERC20.safeTransferFrom(USDC, msg.sender, address(this), amount);

        emit SuppliedUSDC(amount);
    }

    function depositEETH(address user, uint256 amount) external {
        _collaterals[user] += amount;
        totalCollateralAmount += amount;

        SafeERC20.safeTransferFrom(eETH, msg.sender, address(this), amount); // use safeTransferFrom

        emit DepositedCollateral(user, amount);
    }

    /// Users borrow USDC for payment using the deposited collateral eETH
    /// - the user's borriwng amount is incremented by the exact `borrowUsdcAmount`
    /// - the total borrowing amount is incremented by the exact `borrowUsdcAmount`
    /// - the USDC is transferred to the `etherFiCashSafe`
    function borrowUSDC(uint256 borrowUsdcAmount) external {
        _borrowings[msg.sender] += borrowUsdcAmount;
        totalBorrowingAmount += borrowUsdcAmount;

        require(
            debtRatioOf(msg.sender) <= liquidationThreshold,
            "NOT_ENOUGH_COLLATERAL"
        );
        require(
            USDC.balanceOf(address(this)) >= borrowUsdcAmount,
            "INSUFFICIENT_LIQUIDITY"
        );

        SafeERC20.safeTransfer(USDC, etherFiCashSafe, borrowUsdcAmount);

        emit Borrowed(msg.sender, borrowUsdcAmount);
    }

    /// Users repay the borrowed USDC in USDC
    function repayWithUSDC(uint256 repayUsdcAmount) external {
        _borrowings[msg.sender] -= repayUsdcAmount;
        totalBorrowingAmount -= repayUsdcAmount;

        SafeERC20.safeTransferFrom(
            USDC,
            msg.sender,
            address(this),
            repayUsdcAmount
        );

        emit RepaidWithUSDC(msg.sender, repayUsdcAmount);
    }

    /// Users repay the borrowed USDC in eETH
    /// Equivalent to partially liquidating the debt using the collateral
    function repayWithEETH(uint256 repayUsdcAmount) external {
        _repayWithEEthCollateral(msg.sender, repayUsdcAmount);
    }

    // https://docs.aave.com/faq/liquidations
    /// Liquidate the user's debt by repaying the entire debt using the collateral
    /// @dev do we need to add penalty?
    function liquidate(address user) external {
        require(liquidatable(user), "NO_LIQUIDATION_REQUIRED");

        uint256 beforeDebtAmount = _borrowings[user];
        uint256 beforeCollateralAmount = _collaterals[user];
        _repayWithEEthCollateral(user, beforeDebtAmount); // force to repay the entire debt using the collateral

        emit Liquidated(
            user,
            beforeCollateralAmount,
            _collaterals[user],
            beforeDebtAmount
        );
    }

    // View functions

    function liquidatable(address user) public view returns (bool) {
        return debtRatioOf(user) > liquidationThreshold;
    }

    function collateralOf(address user) public view returns (uint256) {
        return _collaterals[user];
    }

    function borrowingOf(address user) public view returns (uint256) {
        return _borrowings[user];
    }

    /// Debt ratio is calculated as the ratio of the debt to the collateral value in USDC
    // it returns the ratio in basis points (1e4)
    function debtRatioOf(address user) public view returns (uint256) {
        uint256 eEthPriceInUSDC = getEEthPriceInUsdc(); // assuming this returns the price scaled to 6 decimals
        uint256 debtValue = _borrowings[user];
        uint256 collateralValue = (_collaterals[user] * eEthPriceInUSDC) / 1e18; // adjust for eETH's 18 decimals

        require(collateralValue > 0, "ZERO_COLLATERAL_VALUE");

        return (debtValue * 1e4) / collateralValue; // result in basis points
    }

    function remainingBorrowingCapacityInUSDC(
        address user
    ) public view returns (uint256) {
        uint256 eEthPriceInUSDC = getEEthPriceInUsdc();
        uint256 collateralValue = (_collaterals[user] * eEthPriceInUSDC) / 1e18;
        uint256 maxBorrowingAmount = (collateralValue * liquidationThreshold) /
            1e4;
        return
            maxBorrowingAmount > _borrowings[user]
                ? maxBorrowingAmount - _borrowings[user]
                : 0;
    }

    function liquidEEthAmount() public view returns (uint256) {
        return eETH.balanceOf(address(this)) - totalCollateralAmount;
    }

    function liquidUsdcAmount() public view returns (uint256) {
        return USDC.balanceOf(address(this)) - totalBorrowingAmount;
    }

    // returns eETH price in USDC
    function getEEthPriceInUsdc() private view returns (uint256) {
        // TODO: replace it with the actual oracle interaction
        return eEthPriceInUSDC;
    }

    function convertEETHtoUSDC(
        uint256 eethAmount
    ) private view returns (uint256) {
        uint256 eEthPriceInUSDC = getEEthPriceInUsdc();
        return (eethAmount * eEthPriceInUSDC) / 1e18;
    }

    function getCollateralAmountForDebt(
        uint256 debtUsdcAmount
    ) public view returns (uint256) {
        uint256 eEthPriceInUSDC = getEEthPriceInUsdc();
        return (debtUsdcAmount * 1e18) / eEthPriceInUSDC;
    }

    // Internal functions

    // Use the deposited collateral to pay the debt
    function _repayWithEEthCollateral(
        address user,
        uint256 repayDebtAmount
    ) internal returns (uint256 collateralAmount) {
        collateralAmount = getCollateralAmountForDebt(repayDebtAmount);

        _borrowings[user] -= repayDebtAmount;
        _collaterals[user] -= collateralAmount;

        totalBorrowingAmount -= repayDebtAmount;
        totalCollateralAmount -= collateralAmount;

        emit RepaidWithEETH(user, repayDebtAmount, collateralAmount);
    }

    // Setters

    function setLiquidationThreshold(uint256 newThreshold) external {
        liquidationThreshold = newThreshold;
    }

    function setEEthPriceInUSDC(uint256 newPrice) external {
        eEthPriceInUSDC = newPrice;
    }
}
