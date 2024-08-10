// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceProvider {
    /**
     * @notice Function to get the price of weETH in USD
     * @return Price with 6 decimals
     */
    function getWeEthUsdPrice() external view returns (uint256);
}
