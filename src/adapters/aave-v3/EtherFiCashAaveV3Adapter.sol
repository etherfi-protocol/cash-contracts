// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPool} from "@aave/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aave/interfaces/IPoolDataProvider.sol";
import {DataTypes} from "@aave/protocol/libraries/types/DataTypes.sol";
import {WadRayMath} from "@aave/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "@aave/protocol/libraries/math/PercentageMath.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICashDataProvider} from "../../interfaces/ICashDataProvider.sol";

contract EtherFiCashAaveV3Adapter {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    struct AaveAccountData {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold; // ltv liquidation threshold in basis points
        uint256 ltv; // loan to value ration in basis points
        uint256 healthFactor;
    }

    // Address of the AaveV3 Pool contract
    IPool public immutable aaveV3Pool;
    // Address of the AaveV3 Pool Data provider
    IPoolDataProvider public immutable aaveV3PoolDataProvider;
    // Referral code for AaveV3
    uint16 public immutable aaveV3ReferralCode;
    // Interest rate mode -> Stable: 1, variable: 2
    uint256 public immutable interestRateMode;

    event AaveV3Process(
        address assetToSupply,
        uint256 amountToSupply,
        address assetToBorrow,
        uint256 amountToBorrow
    );

    error InvalidRateMode();

    constructor(
        address _aaveV3Pool,
        address _aaveV3PoolDataProvider,
        uint16 _aaveV3ReferralCode,
        uint256 _interestRateMode
    ) {
        if (interestRateMode != 1 && interestRateMode != 2)
            revert InvalidRateMode();

        aaveV3Pool = IPool(_aaveV3Pool);
        aaveV3PoolDataProvider = IPoolDataProvider(_aaveV3PoolDataProvider);
        aaveV3ReferralCode = _aaveV3ReferralCode;
        interestRateMode = _interestRateMode;
    }

    function process(
        address assetToSupply,
        uint256 amountToSupply,
        address assetToBorrow,
        uint256 amountToBorrow
    ) external {
        _supply(assetToSupply, amountToSupply);

        if (!getIsCollateral(assetToSupply))
            aaveV3Pool.setUserUseReserveAsCollateral(assetToSupply, true);

        _borrow(assetToBorrow, amountToBorrow);

        emit AaveV3Process(
            assetToSupply,
            amountToSupply,
            assetToBorrow,
            amountToBorrow
        );
    }

    function _supply(address asset, uint256 amount) internal {
        IERC20(asset).safeIncreaseAllowance(address(aaveV3Pool), amount);
        aaveV3Pool.supply(asset, amount, address(this), aaveV3ReferralCode);
    }

    function _borrow(address asset, uint256 amount) internal {
        aaveV3Pool.borrow(
            asset,
            amount,
            interestRateMode,
            aaveV3ReferralCode,
            address(this)
        );
    }

    function _repay(address asset, uint256 amount) internal {
        aaveV3Pool.repay(asset, amount, interestRateMode, address(this));
    }

    function _withdraw(address token, uint256 amount) internal {
        aaveV3Pool.withdraw(token, amount, address(this));
    }

    function getAccountData(
        address user
    ) public view returns (AaveAccountData memory) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = aaveV3Pool.getUserAccountData(user);

        return
            AaveAccountData({
                totalCollateralBase: totalCollateralBase,
                totalDebtBase: totalDebtBase,
                availableBorrowsBase: availableBorrowsBase,
                currentLiquidationThreshold: currentLiquidationThreshold,
                ltv: ltv,
                healthFactor: healthFactor
            });
    }

    /**
     * @dev Checks if collateral is enabled for an asset
     * @param token token address of the asset.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     */

    function getIsCollateral(
        address token
    ) internal view returns (bool isCollateral) {
        (, , , , , , , , isCollateral) = aaveV3PoolDataProvider
            .getUserReserveData(token, address(this));
    }

    /**
     * @dev Get total debt balance & fee for an asset
     * @param token token address of the debt
     */
    function getDebt(address token) internal view returns (uint256) {
        (
            ,
            uint256 stableDebt,
            uint256 variableDebt,
            ,
            ,
            ,
            ,
            ,

        ) = aaveV3PoolDataProvider.getUserReserveData(token, address(this));
        return interestRateMode == 1 ? stableDebt : variableDebt;
    }

    /**
     * @dev Get total collateral balance for an asset
     * @param token token address of the collateral
     */
    function getCollateralBalance(
        address token
    ) internal view returns (uint256 balance) {
        (balance, , , , , , , , ) = aaveV3PoolDataProvider.getUserReserveData(
            token,
            address(this)
        );
    }
}
