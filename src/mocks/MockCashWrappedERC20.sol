// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CashWrappedERC20} from "../cash-wrapper-token/CashWrappedERC20.sol";

contract MockCashWrappedERC20 is CashWrappedERC20 {
    function init(
        address __factory,
        address __baseToken, 
        string memory __name, 
        string memory __symbol, 
        uint8 __decimals
    ) external initializer {
        __ERC20_init(__name, __symbol);
        __ERC20Permit_init(__name);
        __ReentrancyGuardTransient_init();
        _decimals = __decimals;
        baseToken = __baseToken;
        factory = __factory;
    }

}