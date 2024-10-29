// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeCore} from "../user-safe/UserSafeCore.sol";

contract UserSafeV2Mock is UserSafeCore {
    function version() external pure returns (uint256) {
        return 2;
    }
}
