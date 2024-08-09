// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockPriceProvider
 */
contract MockPriceProvider {
    uint256 price;
    uint8 public constant decimals = 6;

    error PriceCannotBeZeroOrNegative();

    function setWeEthUsdPrice(uint256 _price) external {
        price = _price;
    }

    function getWeEthUsdPrice() external view returns (uint256) {
        return price;
    }
}
