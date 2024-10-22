// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BridgeAdapterBase} from "./bridges/BridgeAdapterBase.sol";
import {IWETH} from "../interfaces/IWETH.sol";

contract TopUpSource is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    
    struct TokenConfig {
        address bridgeAdapter;
        address recipientOnDestChain;
        uint96 maxSlippageInBps;
        bytes additionalData;
    }

    uint96 public constant MAX_ALLOWED_SLIPPAGE = 200; // 2%
    bytes32 public constant BRIDGER_ROLE = keccak256("BRIDGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    IWETH public immutable weth;
    mapping (address token => TokenConfig config) private _tokenConfig;
    address public recoveryWallet;

    event TokenConfigSet(address[] tokens, TokenConfig[] configs);
    event Bridge(address token, uint256 amount);
    event ETHDeposit(address sender, uint256 amount);
    event Recovery(address recoveryWallet, address token, uint256 amount);
    event RecoveryWalletSet(address oldRecoveryWallet, address newRecoveryWallet);

    error ArrayLengthMismatch();
    error TokenCannotBeZeroAddress();
    error InvalidConfig();
    error TokenConfigNotSet();
    error ZeroBalance();
    error RecoveryWalletNotSet();
    error RecoveryWalletCannotBeZeroAddress();
    error DefaultAdminCannotBeZeroAddress();

    constructor(address _weth) {
        weth = IWETH(_weth);
        _disableInitializers();
    }

    function initialize(uint48 _defaultAdminDelay, address _defaultAdmin, address _recoveryWallet) external initializer {
        if (_defaultAdmin == address(0)) revert DefaultAdminCannotBeZeroAddress();
        if (_recoveryWallet == address(0)) revert RecoveryWalletCannotBeZeroAddress();

        __UUPSUpgradeable_init_unchained();
        __AccessControlDefaultAdminRules_init_unchained(_defaultAdminDelay, _defaultAdmin);
        __Pausable_init_unchained();

        _grantRole(PAUSER_ROLE, _defaultAdmin);
        _grantRole(BRIDGER_ROLE, _defaultAdmin);

        recoveryWallet = _recoveryWallet;
        emit RecoveryWalletSet(address(0), _recoveryWallet);
    }

    function tokenConfig(address token) external view returns (TokenConfig memory) {
        return _tokenConfig[token];
    }

    function setTokenConfig(address[] calldata tokens, TokenConfig[] calldata configs) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = tokens.length;
        if (len != configs.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < len; ) {
            if (tokens[i] == address(0)) revert TokenCannotBeZeroAddress();
            if (
                configs[i].bridgeAdapter == address(0) || 
                configs[i].recipientOnDestChain == address(0) || 
                configs[i].maxSlippageInBps > MAX_ALLOWED_SLIPPAGE
            ) revert InvalidConfig();

            _tokenConfig[tokens[i]] = configs[i];
            unchecked {
                ++i;
            }
        }

        emit TokenConfigSet(tokens, configs);
    }

    function bridge(address token) external payable whenNotPaused onlyRole(BRIDGER_ROLE) {
        if (token == address(0)) revert TokenCannotBeZeroAddress();
        if (_tokenConfig[token].bridgeAdapter == address(0)) revert TokenConfigNotSet();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert ZeroBalance();

        delegateCall(
            _tokenConfig[token].bridgeAdapter, 
            abi.encodeWithSelector(
                BridgeAdapterBase.bridge.selector, 
                token, 
                balance, 
                _tokenConfig[token].recipientOnDestChain, 
                _tokenConfig[token].maxSlippageInBps, 
                _tokenConfig[token].additionalData
            )  
        );

        emit Bridge(token, balance);
    }

    function getBridgeFee(address token) external view returns (address _token, uint256 _amount) {
        if (token == address(0)) revert TokenCannotBeZeroAddress();
        if (_tokenConfig[token].bridgeAdapter == address(0)) revert TokenConfigNotSet();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert ZeroBalance();

        return BridgeAdapterBase(_tokenConfig[token].bridgeAdapter).getBridgeFee(
            token, 
            balance, 
            _tokenConfig[token].recipientOnDestChain, 
            _tokenConfig[token].maxSlippageInBps, 
            _tokenConfig[token].additionalData
        );
    }

    function recoverFunds(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recoveryWallet == address(0)) revert RecoveryWalletNotSet();
        if (token == address(0)) revert TokenCannotBeZeroAddress();
        IERC20(token).safeTransfer(recoveryWallet, amount);   

        emit Recovery(recoveryWallet, token, amount);
    }

    function setRecoveryWallet(address _recoveryWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_recoveryWallet == address(0)) revert RecoveryWalletCannotBeZeroAddress();
        emit RecoveryWalletSet(recoveryWallet, _recoveryWallet);
        recoveryWallet = _recoveryWallet;
    }

    function pause() external whenNotPaused onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {
        weth.deposit{value: msg.value}();
        emit ETHDeposit(msg.sender, msg.value);
    }
    
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function delegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        require(target != address(this), "delegatecall to self");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Perform delegatecall to the target contract
            let success := delegatecall(
                gas(),
                target,
                add(data, 0x20),
                mload(data),
                0,
                0
            )

            // Get the size of the returned data
            let size := returndatasize()

            // Allocate memory for the return data
            result := mload(0x40)

            // Set the length of the return data
            mstore(result, size)

            // Copy the return data to the allocated memory
            returndatacopy(add(result, 0x20), 0, size)

            // Update the free memory pointer
            mstore(0x40, add(result, add(0x20, size)))

            if iszero(success) {
                revert(result, returndatasize())
            }
        }
    }

}