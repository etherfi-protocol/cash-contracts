// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafe} from "../UserSafe.sol";

contract UserSafeV2Mock is UserSafe {
    constructor(
        address _usdc,
        address _weETH,
        address _priceProvider,
        address _cashDataProvider,
        address __swapper
    ) UserSafe(_usdc, _weETH, _priceProvider, _cashDataProvider, __swapper) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}
