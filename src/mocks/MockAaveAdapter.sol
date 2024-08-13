// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEtherFiCashAaveV3Adapter} from "../interfaces/IEtherFiCashAaveV3Adapter.sol";

contract MockAaveAdapter is IEtherFiCashAaveV3Adapter {
    using SafeERC20 for IERC20;

    uint256 totalCollateral;
    uint256 totalDebt;
    uint256 availableBorrowsBase;
    uint256 currentLiquidationThreshold;
    uint256 ltv;
    uint256 healthFactor;

    function process(
        address assetToSupply,
        uint256 amountToSupply,
        address assetToBorrow,
        uint256 amountToBorrow
    ) external override {
        totalCollateral += amountToSupply;
        totalDebt += amountToBorrow;

        emit AaveV3Process(
            assetToSupply,
            amountToSupply,
            assetToBorrow,
            amountToBorrow
        );
    }

    function supply(address asset, uint256 amount) external override {
        totalCollateral += amount;
    }

    function borrow(address asset, uint256 amount) external override {
        totalDebt += amount;
    }

    function repay(address asset, uint256 amount) external override {
        totalDebt -= amount;
    }

    function withdraw(address asset, uint256 amount) external override {
        totalCollateral -= amount;
    }

    function getAccountData(
        address user
    ) external view override returns (AaveAccountData memory) {
        return
            AaveAccountData({
                totalCollateralBase: totalCollateral,
                totalDebtBase: totalDebt,
                availableBorrowsBase: availableBorrowsBase,
                currentLiquidationThreshold: currentLiquidationThreshold,
                ltv: ltv,
                healthFactor: healthFactor
            });
    }

    function getDebt(
        address user,
        address token
    ) external view override returns (uint256 debt) {
        return totalDebt;
    }

    function getCollateralBalance(
        address user,
        address token
    ) external view override returns (uint256 balance) {
        return totalCollateral;
    }
}
