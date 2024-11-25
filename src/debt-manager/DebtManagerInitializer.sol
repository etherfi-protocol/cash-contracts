// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DebtManagerInitializer
 */

import {DebtManagerStorage, ICashDataProvider} from "./DebtManagerStorage.sol";

contract DebtManagerInitializer is DebtManagerStorage {
        function initialize(
        address __owner,
        address __cashDataProvider    
    ) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init_unchained();
        __AccessControlDefaultAdminRules_init(5 * 60, __owner);
        _grantRole(ADMIN_ROLE, __owner);

        _cashDataProvider = ICashDataProvider(__cashDataProvider);
    }
}