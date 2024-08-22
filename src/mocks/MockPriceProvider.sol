// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockPriceProvider
 */
contract MockPriceProvider {
    uint256 _price;

    constructor(uint256 __price) {
        _price = __price;
    }

    function setPrice(uint256 __price) external {
        _price = __price;
    }

    function price(
        address // token
    ) public view returns (uint256) {
        return _price;
    }
}
