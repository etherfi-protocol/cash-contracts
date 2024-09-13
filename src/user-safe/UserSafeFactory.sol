// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";

/**
 * @title UserSafeFactory
 * @author ether.fi [shivam@ether.fi]
 * @notice Factory to deploy User Safe contracts
 */
contract UserSafeFactory is UpgradeableBeacon {
    address public cashDataProvider;

    event UserSafeDeployed(address indexed safe);
    event CashDataProviderSet(address oldProvider, address newProvider);

    constructor(
        address _implementation,
        address _owner,
        address _cashDataProvider
    ) UpgradeableBeacon(_implementation, _owner) {
        cashDataProvider = _cashDataProvider;
    }

    function setCashDataProvider(address _cashDataProvider) external onlyOwner {
        emit CashDataProviderSet(cashDataProvider, _cashDataProvider);
        cashDataProvider = _cashDataProvider;
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
                    abi.encode(address(this), data)
                ), 
                keccak256(abi.encode(saltData, data))
            )
        );
        
        ICashDataProvider(cashDataProvider).whitelistUserSafe(safe);

        emit UserSafeDeployed(safe);
        return safe;
    }
}
