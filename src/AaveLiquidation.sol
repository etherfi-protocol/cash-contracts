// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CashTokenWrapperFactory, CashWrappedERC20} from "./cash-wrapper-token/CashTokenWrapperFactory.sol";
import {IPool} from "@aave/interfaces/IPool.sol";

contract AaveLiquidation {
    using SafeERC20 for IERC20;

    IPool public immutable aavePool;
    CashTokenWrapperFactory public immutable cashWrapperFactory;

    error UnknownCollateralToken();
    error InvalidCollateralToken();
    error ZeroATokensReceived();
    error ZeroCollateralTokensReceived();

    constructor(address _aavePool, address _cashWrapperFactory) {
        aavePool = IPool(_aavePool);
        cashWrapperFactory = CashTokenWrapperFactory(_cashWrapperFactory);
    }

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external {
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        IERC20(debtAsset).forceApprove(address(aavePool), debtToCover);

        aavePool.liquidationCall(collateralAsset, debtAsset, user, debtToCover, receiveAToken);

        if (receiveAToken) {
            address aToken = _getAToken(collateralAsset);
            uint256 aTokenReceived = IERC20(aToken).balanceOf(address(this));
            if (aTokenReceived == 0) revert ZeroATokensReceived();
            IERC20(aToken).safeTransfer(msg.sender, aTokenReceived);
            return;
        } 

        uint256 collateralAssetReceived = IERC20(collateralAsset).balanceOf(address(this));
        if (collateralAssetReceived == 0) revert ZeroCollateralTokensReceived();

        try CashWrappedERC20(collateralAsset).baseToken() returns (address baseToken) {
            if (cashWrapperFactory.cashWrappedToken(baseToken) != collateralAsset) revert UnknownCollateralToken();
            CashWrappedERC20(collateralAsset).withdraw(msg.sender, collateralAssetReceived);
        } catch {
            IERC20(collateralAsset).safeTransfer(msg.sender, collateralAssetReceived);
        }
    }

    function _getAToken(address collateralAsset) internal view returns (address aToken) {
        aToken = aavePool.getReserveData(collateralAsset).aTokenAddress;
        if (aToken == address(0)) revert InvalidCollateralToken();
    }
}