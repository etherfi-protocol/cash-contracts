// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {IL2DebtManager} from "../interfaces/IL2DebtManager.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {DebtManagerStorage} from "../debt-manager/DebtManagerStorage.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract UserSafeLens is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    using Math for uint256;

    struct UserSafeData {
        IL2DebtManager.TokenData[] collateralBalances;
        IL2DebtManager.TokenData[] borrows;
        IL2DebtManager.TokenData[] tokenPrices;
        IUserSafe.WithdrawalRequest withdrawalRequest;
        uint256 totalCollateral;
        uint256 totalBorrow;
        uint256 maxBorrow;
    }

    ICashDataProvider public cashDataProvider;

    event CashDataProviderSet(address oldProvider, address newProvider);

    error InvalidValue();

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _cashDataProvider) external initializer {
        __UUPSUpgradeable_init();
        __AccessControlDefaultAdminRules_init(5 * 60, owner);

        cashDataProvider = ICashDataProvider(_cashDataProvider);
    }

    function setCashDataProvider(address _cashDataProvider) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_cashDataProvider == address(0)) revert InvalidValue();
        emit CashDataProviderSet(address(cashDataProvider), _cashDataProvider);
        cashDataProvider = ICashDataProvider(_cashDataProvider);

    }

    function getUserSafeData(address user) external view returns (UserSafeData memory) {
        IUserSafe userSafe = IUserSafe(user);
        IL2DebtManager debtManager = IL2DebtManager(cashDataProvider.etherFiCashDebtManager());

        (
            IL2DebtManager.TokenData[] memory collateralBalances,
            uint256 totalCollateralInUsd,
            IL2DebtManager.TokenData[] memory borrowings,
            uint256 totalBorrowings
        ) = debtManager.getUserCurrentState(address(userSafe));
        
        IUserSafe.WithdrawalRequest memory withdrawalRequest = userSafe.pendingWithdrawalRequest();
        uint256 maxBorrow = debtManager.getMaxBorrowAmount(address(user), true);

        address[] memory supportedTokens = debtManager.getCollateralTokens();
        uint256 len = supportedTokens.length;
        IL2DebtManager.TokenData[] memory tokenPrices = new IL2DebtManager.TokenData[](len);
        IPriceProvider priceProvider = IPriceProvider(cashDataProvider.priceProvider());

        for (uint256 i = 0; i < len; ) { 
            tokenPrices[i].token = supportedTokens[i];
            tokenPrices[i].amount = priceProvider.price(supportedTokens[i]);
            unchecked {
                ++i;
            }
        }

        return UserSafeData({
            collateralBalances: collateralBalances,
            borrows: borrowings,
            withdrawalRequest: withdrawalRequest,
            totalCollateral: totalCollateralInUsd,
            totalBorrow: totalBorrowings,
            maxBorrow: maxBorrow,
            tokenPrices: tokenPrices
        });
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}   
}