// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// User
// Account
//
interface IUserRegistry {
    struct User {
        address account;
    }
    // any other fields can be added

    function AccountOf(address user) external view returns (User memory);
}
