// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEtherFiCashAaveV3Adapter} from "../interfaces/IEtherFiCashAaveV3Adapter.sol";

contract MockAave {
    using SafeERC20 for IERC20;

    uint256 totalCollateral;
    uint256 totalDebt;
    uint256 availableBorrowsBase;
    uint256 currentLiquidationThreshold;
    uint256 ltv;
    uint256 healthFactor;

    function supply(
        address, // asset
        uint256 amount
    ) external {
        totalCollateral += amount;
    }

    function borrow(
        address, // asset
        uint256 amount
    ) external {
        totalDebt += amount;
    }

    function repay(
        address, // asset
        uint256 amount
    ) external {
        totalDebt -= amount;
    }

    function withdraw(
        address, // asset
        uint256 amount
    ) external {
        totalCollateral -= amount;
    }

    function getAccountData(
        address // user
    ) external view returns (IEtherFiCashAaveV3Adapter.AaveAccountData memory) {
        return
            IEtherFiCashAaveV3Adapter.AaveAccountData({
                totalCollateralBase: totalCollateral,
                totalDebtBase: totalDebt,
                availableBorrowsBase: availableBorrowsBase,
                currentLiquidationThreshold: currentLiquidationThreshold,
                ltv: ltv,
                healthFactor: healthFactor
            });
    }

    function getDebt(
        address, // user
        address // token
    ) external view returns (uint256 debt) {
        return totalDebt;
    }

    function getCollateralBalance(
        address, // user
        address // token
    ) external view returns (uint256 balance) {
        return totalCollateral;
    }
}

contract MockAaveAdapter is IEtherFiCashAaveV3Adapter {
    using SafeERC20 for IERC20;
    MockAave public immutable aave;

    constructor() {
        aave = new MockAave();
    }

    function process(
        address assetToSupply,
        uint256 amountToSupply,
        address assetToBorrow,
        uint256 amountToBorrow
    ) external {
        aave.supply(assetToSupply, amountToSupply);
        aave.borrow(assetToBorrow, amountToBorrow);

        emit AaveV3Process(
            assetToSupply,
            amountToSupply,
            assetToBorrow,
            amountToBorrow
        );
    }

    function supply(address asset, uint256 amount) external {
        aave.supply(asset, amount);
    }

    function borrow(address asset, uint256 amount) external {
        aave.borrow(asset, amount);
    }

    function repay(address asset, uint256 amount) external {
        aave.repay(asset, amount);
    }

    function withdraw(address asset, uint256 amount) external {
        aave.withdraw(asset, amount);
    }

    function setEModeCategory(uint8 categoryId) external {}

    function getAccountData(
        address user
    ) external view returns (AaveAccountData memory) {
        return aave.getAccountData(user);
    }

    function getDebt(
        address user,
        address token
    ) external view returns (uint256 debt) {
        return aave.getDebt(user, token);
    }

    function getCollateralBalance(
        address user,
        address token
    ) external view returns (uint256 balance) {
        return aave.getCollateralBalance(user, token);
    }
}
