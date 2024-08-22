// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceProvider {
    error UnknownToken();
    /**
     * @notice Function to get the price of a token in USD
     * @return Price with 6 decimals
     */
    function price(address token) external view returns (uint256);
}
