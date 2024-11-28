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
        IUserSafe.Mode mode;
        uint256 incomingCreditModeStartTime;
        IL2DebtManager.TokenData[] collateralBalances;
        IL2DebtManager.TokenData[] borrows;
        IL2DebtManager.TokenData[] tokenPrices;
        IUserSafe.WithdrawalRequest withdrawalRequest;
        uint256 totalCollateral;
        uint256 totalBorrow;
        uint256 maxBorrow;
        uint256 creditMaxSpend;
        uint256 debitMaxSpend;
        uint256 spendingLimitAllowance;
        uint256 totalCashbackEarnedInUsd;
        uint256 pendingCashbackInUsd;
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

    function getUserSafeData(address user) external view returns (UserSafeData memory userData) {
        IUserSafe userSafe = IUserSafe(user);
        IL2DebtManager debtManager = IL2DebtManager(cashDataProvider.etherFiCashDebtManager());

        (
            userData.collateralBalances,
            userData.totalCollateral,
            userData.borrows,
            userData.totalBorrow
        ) = debtManager.getUserCurrentState(address(userSafe));
        
        userData.withdrawalRequest = userSafe.pendingWithdrawalRequest();
        userData.maxBorrow = debtManager.getMaxBorrowAmount(address(user), true);

        address[] memory supportedTokens = debtManager.getCollateralTokens();
        uint256 len = supportedTokens.length;
        userData.tokenPrices = new IL2DebtManager.TokenData[](len);
        IPriceProvider priceProvider = IPriceProvider(cashDataProvider.priceProvider());

        for (uint256 i = 0; i < len; ) { 
            userData.tokenPrices[i].token = supportedTokens[i];
            userData.tokenPrices[i].amount = priceProvider.price(supportedTokens[i]);
            unchecked {
                ++i;
            }
        }
        
        (userData.creditMaxSpend, userData.debitMaxSpend, userData.spendingLimitAllowance) = userSafe.maxCanSpend(debtManager.getBorrowTokens()[0]);
        userData.mode = userSafe.mode();
        userData.incomingCreditModeStartTime = userSafe.incomingCreditModeStartTime();
        userData.totalCashbackEarnedInUsd = userSafe.totalCashbackEarnedInUsd();
        userData.pendingCashbackInUsd = userSafe.pendingCashback();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}   
}