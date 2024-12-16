// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockPriceProvider
 */
contract MockPriceProvider {
    uint256 _price;
    mapping (address => bool) public isStableToken;

    constructor(uint256 __price, address stableToken) {
        _price = __price;
        isStableToken[stableToken] = true;
    }

    function setStableToken(address token) external {
        isStableToken[token] = true;
    }

    function setPrice(uint256 __price) external {
        _price = __price;
    }

    function price(
        address token
    ) public view returns (uint256) {
        if (isStableToken[token]) return 1e6;
        return _price;
    }
}
