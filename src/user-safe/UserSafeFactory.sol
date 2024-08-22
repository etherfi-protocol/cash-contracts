// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UserSafeFactory
 * @author ether.fi [shivam@ether.fi]
 * @notice Factory to deploy User Safe contracts
 */
contract UserSafeFactory is UpgradeableBeacon {
    event UserSafeDeployed(address indexed safe);

    constructor(
        address _implementation,
        address _owner
    ) UpgradeableBeacon(_implementation, _owner) {}

    /**
     * @notice Function to deploy a new User Safe.
     * @param data Initialize function data to be passed while deploying a user safe.
     * @return Address of the user safe.
     */
    function createUserSafe(bytes memory data) external returns (address) {
        address safe = address(new BeaconProxy(address(this), data));
        emit UserSafeDeployed(safe);

        return safe;
    }
}
