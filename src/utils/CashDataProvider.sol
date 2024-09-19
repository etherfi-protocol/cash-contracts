// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title CashDataProvider
 * @author ether.fi [shivam@ether.fi]
 * @notice Contract which stores necessary data required for Cash contracts
 */
contract CashDataProvider is
    ICashDataProvider,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable
{
    bytes32 public constant ETHER_FI_WALLET_ROLE = keccak256("ETHER_FI_WALLET_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Delay for timelock
    uint64 private _delay;
    // Address of the Cash MultiSig
    address private _etherFiCashMultiSig;
    // Address of the Cash Debt Manager
    address private _etherFiCashDebtManager;
    // Address of the price provider
    address private _priceProvider;
    // Address of the swapper
    address private _swapper;
    // Address of aave adapter
    address private _aaveAdapter;
    // Address of user safe factory
    address private _userSafeFactory;
    // Mapping of user safes 
    mapping (address account => bool isUserSafe) private _isUserSafe;

    function initialize(
        address __owner,
        uint64 __delay,
        address __etherFiWallet,
        address __etherFiCashMultiSig,
        address __etherFiCashDebtManager,
        address __priceProvider,
        address __swapper,
        address __aaveAdapter,
        address __userSafeFactory
    ) external initializer {
        __AccessControlDefaultAdminRules_init(uint48(__delay), __owner);
        _grantRole(ADMIN_ROLE, __owner);
        _grantRole(ETHER_FI_WALLET_ROLE, __etherFiWallet);

        _delay = __delay;
        _etherFiCashMultiSig = __etherFiCashMultiSig; 
        _etherFiCashDebtManager = __etherFiCashDebtManager;
        _priceProvider = __priceProvider;
        _swapper = __swapper;
        _aaveAdapter = __aaveAdapter;
        _userSafeFactory = __userSafeFactory;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @inheritdoc ICashDataProvider
     */
    function delay() external view returns (uint64) {
        return _delay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function isEtherFiWallet(address wallet) external view returns (bool) {
        return hasRole(ETHER_FI_WALLET_ROLE, wallet);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiCashMultiSig() external view returns (address) {
        return _etherFiCashMultiSig;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiCashDebtManager() external view returns (address) {
        return _etherFiCashDebtManager;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function priceProvider() external view returns (address) {
        return _priceProvider;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function swapper() external view returns (address) {
        return _swapper;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function aaveAdapter() external view returns (address) {
        return _aaveAdapter;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function userSafeFactory() external view returns (address) {
        return _userSafeFactory;
    }
    
    /**
     * @inheritdoc ICashDataProvider
     */
    function isUserSafe(address account) external view returns (bool) {
        return _isUserSafe[account];
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setDelay(uint64 __delay) external onlyRole(ADMIN_ROLE) {
        if (__delay == 0) revert InvalidValue();
        emit DelayUpdated(_delay, __delay);
        _delay = __delay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function grantEtherFiWalletRole(address wallet) external onlyRole(ADMIN_ROLE) {
        if (wallet == address(0)) revert InvalidValue();
        if (hasRole(ETHER_FI_WALLET_ROLE, wallet)) revert AlreadyAWhitelistedEtherFiWallet();
        _grantRole(ETHER_FI_WALLET_ROLE, wallet);

        emit EtherFiWalletAdded(wallet);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function revokeEtherFiWalletRole(address wallet) external onlyRole(ADMIN_ROLE) {
        if (!hasRole(ETHER_FI_WALLET_ROLE, wallet)) revert NotAWhitelistedEtherFiWallet();
        _revokeRole(ETHER_FI_WALLET_ROLE, wallet);
        emit EtherFiWalletRemoved(wallet);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setEtherFiCashMultiSig(address cashMultiSig) external onlyRole(ADMIN_ROLE) {
        if (cashMultiSig == address(0)) revert InvalidValue();

        emit CashMultiSigUpdated(_etherFiCashMultiSig, cashMultiSig);
        _etherFiCashMultiSig = cashMultiSig;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setEtherFiCashDebtManager(
        address cashDebtManager
    ) external onlyRole(ADMIN_ROLE) {
        if (cashDebtManager == address(0)) revert InvalidValue();

        emit CashDebtManagerUpdated(_etherFiCashDebtManager, cashDebtManager);
        _etherFiCashDebtManager = cashDebtManager;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setPriceProvider(address priceProviderAddr) external onlyRole(ADMIN_ROLE) {
        if (priceProviderAddr == address(0)) revert InvalidValue();
        emit PriceProviderUpdated(_priceProvider, priceProviderAddr);
        _priceProvider = priceProviderAddr;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setSwapper(address swapperAddr) external onlyRole(ADMIN_ROLE) {
        if (swapperAddr == address(0)) revert InvalidValue();
        emit SwapperUpdated(_swapper, swapperAddr);
        _swapper = swapperAddr;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setAaveAdapter(address adapter) external onlyRole(ADMIN_ROLE) {
        if (adapter == address(0)) revert InvalidValue();
        emit AaveAdapterUpdated(_aaveAdapter, adapter);
        _aaveAdapter = adapter;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setUserSafeFactory(address factory) external onlyRole(ADMIN_ROLE) {
        if (factory == address(0)) revert InvalidValue();
        emit UserSafeFactoryUpdated(_userSafeFactory, factory);
        _userSafeFactory = factory;
    }
      
    /**
     * @inheritdoc ICashDataProvider
     */
    function whitelistUserSafe(address safe) external {
        if (msg.sender != _userSafeFactory) revert OnlyUserSafeFactory();
        _isUserSafe[safe] = true;
        emit UserSafeWhitelisted(safe);
    }
}
