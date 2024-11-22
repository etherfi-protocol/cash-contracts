// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UserSafeSetters} from "./UserSafeSetters.sol";
import {UserSafeCore} from "./UserSafeCore.sol";

/**
 * @title UserSafeFactory
 * @author ether.fi [shivam@ether.fi]
 * @notice Factory to deploy User Safe contracts
 */
contract UserSafeFactory is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    address public cashDataProvider;
    address public beacon;
    address public userSafeSettersImpl;

    event UserSafeDeployed(address indexed safe);
    event CashDataProviderSet(address oldProvider, address newProvider);
    event UserSafeSettersImplSet(address oldUserSafeSettersImpl, address newUserSafeSettersImpl);
    event BeaconSet(address oldBeacon, address newBeacon);

    error InvalidValue();
    error SafeAddressDifferentFromDetermined();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint48 _accessControlDelay,
        address _owner,
        address _cashDataProvider,
        address _userSafeCoreImpl,
        address _userSafeSettersImpl
    ) external initializer {
        __AccessControlDefaultAdminRules_init(_accessControlDelay, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        beacon = address(new UpgradeableBeacon(_userSafeCoreImpl, address(this)));
        cashDataProvider = _cashDataProvider;
        userSafeSettersImpl = _userSafeSettersImpl;
    }

    function setCashDataProvider(address _cashDataProvider) external onlyRole(ADMIN_ROLE) {
        if (_cashDataProvider == address(0)) revert InvalidValue();
        emit CashDataProviderSet(cashDataProvider, _cashDataProvider);
        cashDataProvider = _cashDataProvider;
    }

    function setUserSafeSettersImpl(address _userSafeSettersImpl) external onlyRole(ADMIN_ROLE) {
        if (_userSafeSettersImpl == address(0)) revert InvalidValue();
        emit UserSafeSettersImplSet(userSafeSettersImpl, _userSafeSettersImpl);
        userSafeSettersImpl = _userSafeSettersImpl;
    }

    function setBeacon(address _beacon) external onlyRole(ADMIN_ROLE) {
        if (_beacon == address(0)) revert InvalidValue();
        emit BeaconSet(beacon, _beacon);
        beacon = _beacon;
    }

    function getUserSafeAddress(bytes memory saltData, bytes memory data) external view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(abi.encode(saltData, data)));
    }

    /**
     * @notice Function to deploy a new User Safe.
     * @param data Initialize function data to be passed while deploying a user safe.
     * @return Address of the user safe.
     */
    function createUserSafe(bytes memory saltData, bytes memory data) external onlyRole(ADMIN_ROLE) returns (address) {
        address safe = this.getUserSafeAddress(saltData, data);
        ICashDataProvider(cashDataProvider).whitelistUserSafe(safe);

        address deployedSafe = address(
            CREATE3.deployDeterministic(
                abi.encodePacked(
                    type(BeaconProxy).creationCode, 
                    abi.encode(beacon, data)
                ), 
                keccak256(abi.encode(saltData, data))
            )
        );
        
        if (deployedSafe != safe) revert SafeAddressDifferentFromDetermined();

        emit UserSafeDeployed(safe);
        return safe;
    }

    function upgradeUserSafeCoreImpl(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE)  {}
}