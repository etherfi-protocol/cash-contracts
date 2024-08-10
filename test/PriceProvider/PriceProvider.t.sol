// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeSetup} from "../UserSafe/UserSafeSetup.sol";
import {console} from "forge-std/console.sol";

contract PriceProviderTest is UserSafeSetup {
    function test_Value() public view {
        console.log(priceProvider.getWeEthUsdPrice());
    }
}
