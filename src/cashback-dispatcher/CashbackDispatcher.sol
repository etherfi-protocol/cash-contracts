// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IUserSafe} from "../interfaces/IUserSafe.sol";
import {console} from "forge-std/console.sol";

/// @title CashbackDispatcher
/// @author shivam@ether.fi
/// @notice This contract dispatches cashback to ether.fi cash users
contract CashbackDispatcher is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    ICashDataProvider public cashDataProvider;
    IPriceProvider public priceProvider;
    address public cashbackToken;

    uint256 public constant HUNDRED_PERCENT_IN_BPS = 10000;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event CashDataProviderSet(address oldCashDataProvider, address newCashDataProvider);
    event PriceProviderSet(address oldPriceProvider, address newPriceProvider);
    event CashbackTokenSet(address oldToken, address newToken);

    error CashbackTokenPriceNotConfigured();
    error InvalidValue();
    error OnlyUserSafe();
    error CannotWithdrawZeroAmount();
    error WithdrawFundsFailed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _cashDataProvider, address _priceProvider, address _cashbackToken) external initializer {
        if (
            _cashDataProvider == address(0) || _priceProvider == address(0) || _cashbackToken == address(0)
        ) revert InvalidValue();

        __AccessControlDefaultAdminRules_init_unchained(5 * 60, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        
        cashDataProvider = ICashDataProvider(_cashDataProvider);
        priceProvider = IPriceProvider(_priceProvider);

        if (priceProvider.price(_cashbackToken) == 0) revert CashbackTokenPriceNotConfigured();
        cashbackToken = _cashbackToken;

        emit CashDataProviderSet(address(0), _cashDataProvider);
        emit PriceProviderSet(address(0), _priceProvider);
        emit CashbackTokenSet(address(0), _cashbackToken);
    }

    function convertUsdToCashbackToken(uint256 cashbackInUsd) public view returns (uint256) {
        if (cashbackInUsd == 0) return 0;

        uint256 cashbackTokenPrice = priceProvider.price(cashbackToken);
        return cashbackInUsd.mulDiv(10 ** IERC20Metadata(cashbackToken).decimals(), cashbackTokenPrice);
    }

    function getCashbackAmount(address userSafe, uint256 spentAmountInUsd) public view returns (uint256, uint256) {
        uint256 cashbackPercentage = cashDataProvider.getUserSafeCashbackPercentage(userSafe);
        if (cashbackPercentage == 0) return (0, 0);

        uint256 cashbackInUsd = spentAmountInUsd.mulDiv(cashbackPercentage, HUNDRED_PERCENT_IN_BPS);
        return (convertUsdToCashbackToken(cashbackInUsd), cashbackInUsd);
    }

    function cashback(uint256 spentAmountInUsd) external returns (address token, uint256 cashbackAmount, uint256 cashbackInUsd, bool paid) {
        token = cashbackToken;
        if (!cashDataProvider.isUserSafe(msg.sender)) revert OnlyUserSafe();
        (cashbackAmount, cashbackInUsd) = getCashbackAmount(msg.sender, spentAmountInUsd);
        if (cashbackAmount == 0) return (token, cashbackAmount, cashbackInUsd, true);

        if (IERC20(token).balanceOf(address(this)) < cashbackAmount) paid = false;
        else {
            paid = true;
            IERC20(token).safeTransfer(msg.sender, cashbackAmount);
        }
    }

    function clearPendingCashback() external returns (address, uint256, bool) {
        if (!cashDataProvider.isUserSafe(msg.sender)) revert OnlyUserSafe();
        uint256 pendingCashbackInUsd = IUserSafe(msg.sender).pendingCashback();

        uint256 cashbackAmount = convertUsdToCashbackToken(pendingCashbackInUsd);
        if (cashbackAmount == 0) return (cashbackToken, 0, false);
        
        if (IERC20(cashbackToken).balanceOf(address(this)) < cashbackAmount) return (cashbackToken, cashbackAmount, false);
        else {
            IERC20(cashbackToken).safeTransfer(msg.sender, cashbackAmount);
            return (cashbackToken, cashbackAmount, true);
        }
    }

    function setCashDataProvider(address _cashDataProvider) external onlyRole(ADMIN_ROLE) {
        if (_cashDataProvider == address(0)) revert InvalidValue();
        emit CashDataProviderSet(address(cashDataProvider), _cashDataProvider);
        cashDataProvider = ICashDataProvider(_cashDataProvider);
    }

    function setPriceProvider(address _priceProvider) external onlyRole(ADMIN_ROLE) {
        if (_priceProvider == address(0)) revert InvalidValue();

        emit PriceProviderSet(address(priceProvider), _priceProvider);
        priceProvider = IPriceProvider(_priceProvider);
        
        if (priceProvider.price(cashbackToken) == 0) revert CashbackTokenPriceNotConfigured();
    }

    function setCashbackToken(address _token) external onlyRole(ADMIN_ROLE) {
        if (_token == address(0)) revert InvalidValue();
        if (priceProvider.price(cashbackToken) == 0) revert CashbackTokenPriceNotConfigured();
        emit CashbackTokenSet(cashbackToken, _token);
        cashbackToken = _token;
    }

    function withdrawFunds(address token, address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidValue();

        if (token == address(0)) {
            if (amount == 0) amount = address(this).balance;
            if (amount == 0) revert CannotWithdrawZeroAmount();
            (bool success, ) = payable(recipient).call{value: amount}("");
            if (!success) revert  WithdrawFundsFailed();
        } else {
            if (amount == 0) amount = IERC20(token).balanceOf(address(this));
            if (amount == 0) revert CannotWithdrawZeroAmount();
            IERC20(token).safeTransfer(recipient, amount);
        }
    }
    
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}