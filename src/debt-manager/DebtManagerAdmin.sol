// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DebtManagerStorage} from "./DebtManagerStorage.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

contract DebtManagerAdmin is DebtManagerStorage {
    function supportCollateralToken(
        address token,
        CollateralTokenConfig calldata config
    ) external onlyRole(ADMIN_ROLE) {
        _supportCollateralToken(token);
        _setCollateralTokenConfig(token, config);
    }

    function unsupportCollateralToken(
        address token
    ) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidValue();
        if (_totalCollateralAmounts[token] != 0) revert TotalCollateralAmountNotZero();

        uint256 indexPlusOneForTokenToBeRemoved = _collateralTokenIndexPlusOne[
            token
        ];
        if (indexPlusOneForTokenToBeRemoved == 0) revert NotACollateralToken();

        uint256 len = _supportedCollateralTokens.length;
        if (len == 1) revert NoCollateralTokenLeft();

        _collateralTokenIndexPlusOne[
            _supportedCollateralTokens[len - 1]
        ] = indexPlusOneForTokenToBeRemoved;

        _supportedCollateralTokens[
            indexPlusOneForTokenToBeRemoved - 1
        ] = _supportedCollateralTokens[len - 1];

        _supportedCollateralTokens.pop();
        delete _collateralTokenIndexPlusOne[token];

        CollateralTokenConfig memory config;
        _setCollateralTokenConfig(token, config);

        emit CollateralTokenRemoved(token);
    }

    function supportBorrowToken(
        address token,
        uint64 borrowApy,
        uint128 minShares
    ) external onlyRole(ADMIN_ROLE) {
        _supportBorrowToken(token);
        _setBorrowTokenConfig(token, borrowApy, minShares);
    }

    function unsupportBorrowToken(address token) external onlyRole(ADMIN_ROLE) {
        uint256 indexPlusOneForTokenToBeRemoved = _borrowTokenIndexPlusOne[
            token
        ];
        if (indexPlusOneForTokenToBeRemoved == 0) revert NotABorrowToken();

        if (_getTotalBorrowTokenAmount(token) != 0)
            revert BorrowTokenStillInTheSystem();

        uint256 len = _supportedBorrowTokens.length;
        if (len == 1) revert NoBorrowTokenLeft();

        _borrowTokenIndexPlusOne[
            _supportedBorrowTokens[len - 1]
        ] = indexPlusOneForTokenToBeRemoved;

        _supportedBorrowTokens[
            indexPlusOneForTokenToBeRemoved - 1
        ] = _supportedBorrowTokens[len - 1];

        _supportedBorrowTokens.pop();
        delete _borrowTokenIndexPlusOne[token];
        delete _borrowTokenConfig[token];

        emit BorrowTokenRemoved(token);
    }

    function setCollateralTokenConfig(
        address __collateralToken,
        CollateralTokenConfig memory __config
    ) external onlyRole(ADMIN_ROLE) {
        _setCollateralTokenConfig(__collateralToken, __config);
    }

    function setBorrowApy(
        address token,
        uint64 apy
    ) external onlyRole(ADMIN_ROLE) {
        _setBorrowApy(token, apy);
    }

    function setMinBorrowTokenShares(
        address token,
        uint128 shares
    ) external onlyRole(ADMIN_ROLE) {
        _setMinBorrowTokenShares(token, shares);
    }

    function _supportCollateralToken(address token) internal {
        if (token == address(0)) revert InvalidValue();

        if (_collateralTokenIndexPlusOne[token] != 0)
            revert AlreadyCollateralToken();

        uint256 price = IPriceProvider(_cashDataProvider.priceProvider()).price(
            token
        );
        if (price == 0) revert OraclePriceZero();

        _supportedCollateralTokens.push(token);
        _collateralTokenIndexPlusOne[token] = _supportedCollateralTokens.length;

        emit CollateralTokenAdded(token);
    }

    function _supportBorrowToken(address token) internal {
        if (token == address(0)) revert InvalidValue();

        if (_borrowTokenIndexPlusOne[token] != 0) revert AlreadyBorrowToken();

        _supportedBorrowTokens.push(token);
        _borrowTokenIndexPlusOne[token] = _supportedBorrowTokens.length;

        emit BorrowTokenAdded(token);
    }


function _setCollateralTokenConfig(
        address collateralToken,
        CollateralTokenConfig memory config
    ) internal {
        if (config.ltv > config.liquidationThreshold)
            revert LtvCannotBeGreaterThanLiquidationThreshold();
        
        if (config.liquidationThreshold + config.liquidationBonus > HUNDRED_PERCENT) revert InvalidValue();

        emit CollateralTokenConfigSet(
            collateralToken,
            _collateralTokenConfig[collateralToken],
            config
        );

        _collateralTokenConfig[collateralToken] = config;
    }

    function _setBorrowTokenConfig(
        address borrowToken,
        uint64 borrowApy,
        uint128 minShares
    ) internal {
        if (borrowApy == 0 || minShares == 0) revert InvalidValue();

        BorrowTokenConfig memory cfg = BorrowTokenConfig({
            interestIndexSnapshot: 0,
            totalBorrowingAmount: 0,
            totalSharesOfBorrowTokens: 0,
            lastUpdateTimestamp: uint64(block.timestamp),
            borrowApy: borrowApy,
            minShares: minShares
        });

        _borrowTokenConfig[borrowToken] = cfg;
        emit BorrowTokenConfigSet(borrowToken, cfg);
    }

    function _setBorrowApy(address token, uint64 apy) internal {
        if (apy == 0) revert InvalidValue();
        if (!isBorrowToken(token)) revert UnsupportedBorrowToken();

        _updateBorrowings(address(0));
        emit BorrowApySet(token, _borrowTokenConfig[token].borrowApy, apy);
        _borrowTokenConfig[token].borrowApy = apy;
    }

    function _setMinBorrowTokenShares(
        address token,
        uint128 shares
    ) internal {
        if (shares == 0) revert InvalidValue();
        if (!isBorrowToken(token)) revert UnsupportedBorrowToken();

        _updateBorrowings(address(0));
        emit MinSharesOfBorrowTokenSet(
            token,
            _borrowTokenConfig[token].minShares,
            shares
        );
        _borrowTokenConfig[token].minShares = shares;
    }
}