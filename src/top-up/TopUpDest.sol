// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransientUpgradeable} from "../utils/ReentrancyGuardTransientUpgradeable.sol";
import {EIP712Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {NoncesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/NoncesUpgradeable.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {EIP1271SignatureUtils} from "../libraries/EIP1271SignatureUtils.sol";

contract TopUpDest is Initializable, UUPSUpgradeable, EIP712Upgradeable, NoncesUpgradeable, AccessControlDefaultAdminRulesUpgradeable, ReentrancyGuardTransientUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using EIP1271SignatureUtils for bytes32;

    bytes32 public constant USER_SAFE_REGISTRY_TYPEHASH =
        keccak256("MapWalletToUserSafe(address wallet,address userSafe,uint256 nonce,uint256 deadline)");

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant TOP_UP_ROLE = keccak256("TOP_UP_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address token => uint256 deposits) public deposits;
    mapping(uint256 chainId => mapping(bytes32 txId => bool status)) public transactionCompleted;
    mapping(address wallet => address userSafe) public walletToUserSafeRegistry;
    ICashDataProvider public cashDataProvider;

    event Deposit(address token, uint256 amount);
    event Withdrawal(address token, uint256 amount);
    event TopUp(uint256 chainId, bytes32 txId, address userSafe, address token, uint256 amount);
    event TopUpBatch(uint256[] chainId, bytes32[] txId, address[] userSafe, address[] token, uint256[] amount);
    event WalletToUserSafeRegistered(address wallet, address userSafe);

    error BalanceTooLow();
    error AmountGreaterThanDeposit();
    error AmountCannotBeZero();
    error TransactionAlreadyCompleted();
    error NotARegisteredUserSafe();
    error ExpiredSignature();
    error WalletCannotBeAddressZero();
    error ArrayLengthMismatch();

    constructor() {
        _disableInitializers();
    }

    function initialize(address _defaultAdmin, address _cashDataProvider) external initializer {
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuardTransient_init();
        __AccessControlDefaultAdminRules_init_unchained(5 * 60, _defaultAdmin);
        __EIP712_init_unchained("TopUpContract", "1");
        __Pausable_init_unchained();
        __Nonces_init_unchained();

        cashDataProvider = ICashDataProvider(_cashDataProvider);

        _grantRole(DEPOSITOR_ROLE, _defaultAdmin);
        _grantRole(PAUSER_ROLE, _defaultAdmin);
        _grantRole(TOP_UP_ROLE, _defaultAdmin);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function mapWalletToUserSafe(
        address wallet,
        address userSafe,
        uint256 deadline,
        bytes memory signature
    ) external {
        if (wallet == address(0)) revert WalletCannotBeAddressZero();
        if (!cashDataProvider.isUserSafe(userSafe)) revert NotARegisteredUserSafe();
        if (block.timestamp > deadline) revert ExpiredSignature();
        bytes32 structHash = keccak256(abi.encode(USER_SAFE_REGISTRY_TYPEHASH, wallet, userSafe, _useNonce(wallet), deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        hash.checkSignature_EIP1271(wallet, signature);
        walletToUserSafeRegistry[wallet] = userSafe;

        emit WalletToUserSafeRegistered(wallet, userSafe);
    }

    // TODO: Remove in Prod, this function is just for Testing purposes
    function mapWalletToUserSafeAdmin(
        address wallet,
        address userSafe
     ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (wallet == address(0)) revert WalletCannotBeAddressZero();
        if (!cashDataProvider.isUserSafe(userSafe)) revert NotARegisteredUserSafe();
        walletToUserSafeRegistry[wallet] = userSafe;

        emit WalletToUserSafeRegistered(wallet, userSafe);
    }

    function deposit(address token, uint256 amount) external onlyRole(DEPOSITOR_ROLE) {
        if (amount == 0) revert AmountCannotBeZero();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        deposits[token] += amount;
        emit Deposit(token, amount);
    }

    function withdraw(address token, uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount == 0) revert AmountCannotBeZero();
        if (amount > deposits[token]) revert AmountGreaterThanDeposit();

        deposits[token] -= amount;
        _transfer(msg.sender, token, amount);

        emit Withdrawal(token, amount);
    }

    function topUpUserSafe(
        uint256[] memory chainIds, 
        bytes32[] memory txIds,
        address[] memory userSafes,
        address[] memory tokens, 
        uint256[] memory amounts
    ) external whenNotPaused nonReentrant onlyRole(TOP_UP_ROLE) {
        uint256 len = chainIds.length;
        if (len != txIds.length || len != userSafes.length || len != tokens.length || len != amounts.length) revert ArrayLengthMismatch();    
        for (uint256 i = 0; i < len; ) {
            _topUp(chainIds[i], txIds[i], userSafes[i], tokens[i], amounts[i]);
            unchecked {
                ++i;
            }
        }

        emit TopUpBatch(chainIds, txIds, userSafes, tokens, amounts);
    }

    function topUpUserSafe(
        uint256 chainId, 
        bytes32 txId, 
        address userSafe, 
        address token, 
        uint256 amount
    ) external whenNotPaused nonReentrant onlyRole(TOP_UP_ROLE) {
        _topUp(chainId, txId, userSafe, token, amount);
        emit TopUp(chainId, txId, userSafe, token, amount);
    }

    function _topUp(uint256 chainId, bytes32 txId, address userSafe, address token, uint256 amount) internal {
        if (transactionCompleted[chainId][txId]) revert TransactionAlreadyCompleted();
        if (!cashDataProvider.isUserSafe(userSafe)) revert NotARegisteredUserSafe();

        transactionCompleted[chainId][txId] = true;
        _transfer(userSafe, token, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _transfer(address to, address token, uint256 amount) internal {
        if (IERC20(token).balanceOf(address(this)) < amount) revert BalanceTooLow();
        IERC20(token).safeTransfer(to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}