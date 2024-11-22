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
contract CashDataProvider is ICashDataProvider, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    bytes32 public constant ETHER_FI_WALLET_ROLE = keccak256("ETHER_FI_WALLET_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant MAX_CASHBACK_PERCENTAGE = 1000; // 10%

    // Delay for timelock
    uint64 private _delay;
    // Address of the Settlement Dispatcher
    address private _settlementDispatcher;
    // Address of the Cash Debt Manager
    address private _etherFiCashDebtManager;
    // Address of the price provider
    address private _priceProvider;
    // Address of the swapper
    address private _swapper;
    // Address of user safe factory
    address private _userSafeFactory;
    // Address of user safe event emitter
    address private _userSafeEventEmitter;
    // Address of the Cashback Dispatcher 
    address internal _cashbackDispatcher;
    // Address of the EtherFi Recovery Signer
    address internal _etherFiRecoverySigner;
    // Address of the Third Party Recovery Signer
    address internal _thirdPartyRecoverySigner;

    // Mapping of user safes 
    mapping (address account => bool isUserSafe) private _isUserSafe;
    // User Safe tier mapping
    mapping (address account => UserSafeTiers tier) private _userSafeTier;
    // User safe tier to cashback percentage in bps mapping
    mapping (UserSafeTiers tier => uint256 cashbackPercentageInBps) private _tierToCashbackPercentageInBps; 

    function initialize(bytes memory data) external initializer {
        {
            (
                address __owner,
                uint64 __delay,
                address __etherFiWallet,
                address __settlementDispatcher,
                address __etherFiCashDebtManager,
                address __priceProvider
            ) = abi.decode(data, (address, uint64, address, address, address, address));
            __AccessControlDefaultAdminRules_init_unchained(uint48(__delay), __owner);
            _grantRole(ADMIN_ROLE, __owner);
            _grantRole(ETHER_FI_WALLET_ROLE, __etherFiWallet);

            _delay = __delay;
            _settlementDispatcher = __settlementDispatcher; 
            _etherFiCashDebtManager = __etherFiCashDebtManager;
            _priceProvider = __priceProvider;
        }

        {
            ( 
            , , , , , ,
            address __swapper,
            address __userSafeFactory,
            address __userSafeEventEmitter,
            address __cashbackDispatcher,
            address __etherFiRecoverySigner,
            address __thirdPartyRecoverySigner
            ) = abi.decode(data, (address, uint64, address, address, address, address, address, address, address, address, address, address));

            if (__etherFiRecoverySigner == address(0) || __thirdPartyRecoverySigner == address(0)) revert InvalidValue();
            _swapper = __swapper;
            _userSafeFactory = __userSafeFactory;
            _userSafeEventEmitter = __userSafeEventEmitter;
            _cashbackDispatcher = __cashbackDispatcher;
            _etherFiRecoverySigner = __etherFiRecoverySigner;
            _thirdPartyRecoverySigner = __thirdPartyRecoverySigner;
        }
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
    function settlementDispatcher() external view returns (address) {
        return _settlementDispatcher;
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
    function userSafeFactory() external view returns (address) {
        return _userSafeFactory;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function userSafeEventEmitter() external view returns (address) {
        return _userSafeEventEmitter;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function cashbackDispatcher() external view returns (address) {
        return _cashbackDispatcher;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiRecoverySigner() external view returns (address) {
        return _etherFiRecoverySigner;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function thirdPartyRecoverySigner() external view returns (address) {
        return _thirdPartyRecoverySigner;
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
    function getUserSafeTier(address safe) external view returns (UserSafeTiers) {
        if (!_isUserSafe[safe]) revert NotAUserSafe();
        return _userSafeTier[safe];
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function getUserSafeCashbackPercentage(address safe) external view returns (uint256) {
        if (!_isUserSafe[safe]) revert NotAUserSafe();
        return _tierToCashbackPercentageInBps[_userSafeTier[safe]];
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function getTierCashbackPercentage(UserSafeTiers tier) external view returns (uint256) {
        if (tier == UserSafeTiers.None) revert TierCannotBeNone();
        return _tierToCashbackPercentageInBps[tier];
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
    function setSettlementDispatcher(address dispatcher) external onlyRole(ADMIN_ROLE) {
        if (dispatcher == address(0)) revert InvalidValue();

        emit SettlementDispatcherUpdated(_settlementDispatcher, dispatcher);
        _settlementDispatcher = dispatcher;
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
    function setUserSafeFactory(address factory) external onlyRole(ADMIN_ROLE) {
        if (factory == address(0)) revert InvalidValue();
        emit UserSafeFactoryUpdated(_userSafeFactory, factory);
        _userSafeFactory = factory;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setUserSafeEventEmitter(address eventEmitter) external onlyRole(ADMIN_ROLE) {
        if (eventEmitter == address(0)) revert InvalidValue();
        emit UserSafeEventEmitterUpdated(_userSafeEventEmitter, eventEmitter);
        _userSafeEventEmitter = eventEmitter;
    }
    
    /**
     * @inheritdoc ICashDataProvider
     */
    function setCashbackDispatcher(address dispatcher) external onlyRole(ADMIN_ROLE) {
        if (dispatcher == address(0)) revert InvalidValue();
        emit CashbackDispatcherUpdated(_cashbackDispatcher, dispatcher);
        _cashbackDispatcher = dispatcher;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setEtherFiRecoverySigner(address recoverySigner) external onlyRole(ADMIN_ROLE) {
        if (recoverySigner == address(0)) revert InvalidValue();
        if (_thirdPartyRecoverySigner == recoverySigner) revert RecoverySignersCannotBeSame();
        emit EtherFiRecoverySignerUpdated(_etherFiRecoverySigner, recoverySigner);
        _etherFiRecoverySigner = recoverySigner;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setThirdPartyRecoverySigner(address recoverySigner) external onlyRole(ADMIN_ROLE) {
        if (recoverySigner == address(0)) revert InvalidValue();
        if (_etherFiRecoverySigner == recoverySigner) revert RecoverySignersCannotBeSame();
        emit ThirdPartyRecoverySignerUpdated(_thirdPartyRecoverySigner, recoverySigner);
        _thirdPartyRecoverySigner = recoverySigner;
    }
      
    /**
     * @inheritdoc ICashDataProvider
     */
    function whitelistUserSafe(address safe) external {
        if (msg.sender != _userSafeFactory) revert OnlyUserSafeFactory();
        _isUserSafe[safe] = true;
        _userSafeTier[safe] = UserSafeTiers.Pepe;
        emit UserSafeWhitelisted(safe);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setUserSafeTier(address[] memory safes, UserSafeTiers[] memory tiers) external onlyRole(ADMIN_ROLE) {
        uint256 len = safes.length;
        if (len != tiers.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < len; ) {
            if (!_isUserSafe[safes[i]]) revert NotAUserSafe();
            if (tiers[i] == UserSafeTiers.None) revert TierCannotBeNone();
            if (_userSafeTier[safes[i]] == tiers[i]) revert AlreadyInSameTier();
            emit UserSafeTierSet(safes[i], _userSafeTier[safes[i]], tiers[i]);
            _userSafeTier[safes[i]] = tiers[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setTierCashbackPercentage(UserSafeTiers[] memory tiers, uint256[] memory cashbackPercentages) external onlyRole(ADMIN_ROLE) {
        uint256 len = tiers.length;
        if (len != cashbackPercentages.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < len; ) {
            if (tiers[i] == UserSafeTiers.None) revert TierCannotBeNone();
            if (cashbackPercentages[i] > MAX_CASHBACK_PERCENTAGE) revert CashbackPercentageGreaterThanMaxAllowed();
            _tierToCashbackPercentageInBps[tiers[i]] = cashbackPercentages[i];
            unchecked {
                ++i;
            }
        }

        emit TierCashbackPercentageSet(tiers, cashbackPercentages);
    }
}