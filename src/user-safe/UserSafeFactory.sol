// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**
 * @title UserSafeFactory
 * @author ether.fi [shivam@ether.fi]
 * @notice Factory to deploy User Safe contracts
 */
contract UserSafeFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    address public cashDataProvider;
    address public beacon;

    event UserSafeDeployed(address indexed safe);
    event CashDataProviderSet(address oldProvider, address newProvider);
    event BeaconSet(address oldBeacon, address newBeacon);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _implementation,
        address _owner,
        address _cashDataProvider
    ) external initializer {
        __Ownable_init(_owner);
        beacon = address(new UpgradeableBeacon(_implementation, address(this)));
        cashDataProvider = _cashDataProvider;
    }

    function setCashDataProvider(address _cashDataProvider) external onlyOwner {
        emit CashDataProviderSet(cashDataProvider, _cashDataProvider);
        cashDataProvider = _cashDataProvider;
    }

    function setBeacon(address _beacon) external onlyOwner {
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
    function createUserSafe(bytes memory saltData, bytes memory data) external returns (address) {
        address safe = address(
            CREATE3.deployDeterministic(
                abi.encodePacked(
                    type(BeaconProxy).creationCode, 
                    abi.encode(beacon, data)
                ), 
                keccak256(abi.encode(saltData, data))
            )
        );
        
        ICashDataProvider(cashDataProvider).whitelistUserSafe(safe);

        emit UserSafeDeployed(safe);
        return safe;
    }

    function upgradeUserSafeImpl(address newImplementation) external onlyOwner {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
