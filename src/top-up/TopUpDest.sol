// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransientUpgradeable} from "../utils/ReentrancyGuardTransientUpgradeable.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";

contract TopUpDest is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable, ReentrancyGuardTransientUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant TOP_UP_ROLE = keccak256("TOP_UP_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address token => uint256 deposits) public deposits;
    mapping(bytes32 txId => bool status) public transactionCompleted;
    ICashDataProvider public cashDataProvider;

    event Deposit(address token, uint256 amount);
    event Withdrawal(address token, uint256 amount);
    event TopUp(bytes32 txId, address userSafe, address token, uint256 amount);

    error BalanceTooLow();
    error AmountGreaterThanDeposit();
    error AmountCannotBeZero();
    error TransactionAlreadyCompleted();
    error NotARegisteredUserSafe();

    constructor() {
        _disableInitializers();
    }

    function initialize(uint48 _defaultAdminDelay, address _defaultAdmin, address _cashDataProvider) external initializer {
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuardTransient_init();
        __AccessControlDefaultAdminRules_init_unchained(_defaultAdminDelay, _defaultAdmin);
        __Pausable_init_unchained();
        cashDataProvider = ICashDataProvider(_cashDataProvider);

        _grantRole(DEPOSITOR_ROLE, _defaultAdmin);
        _grantRole(PAUSER_ROLE, _defaultAdmin);
        _grantRole(TOP_UP_ROLE, _defaultAdmin);
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

    function topUpUserSafe(bytes32 txId, address userSafe, address token, uint256 amount) external whenNotPaused nonReentrant onlyRole(TOP_UP_ROLE) {
        if (transactionCompleted[txId]) revert TransactionAlreadyCompleted();
        if (!cashDataProvider.isUserSafe(userSafe)) revert NotARegisteredUserSafe();

        transactionCompleted[txId] = true;
        _transfer(userSafe, token, amount);

        emit TopUp(txId, userSafe, token, amount);
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