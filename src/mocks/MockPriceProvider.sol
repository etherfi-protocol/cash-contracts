// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MockPriceProvider
 */
contract MockPriceProvider is Ownable {
    uint256 price;

    constructor(uint256 _price) Ownable(msg.sender) {
        price = _price;
    }

    function setWeEthUsdPrice(uint256 _price) external {
        price = _price;
    }

    function getWeEthUsdPrice() external view returns (uint256) {
        return price;
    }
}
