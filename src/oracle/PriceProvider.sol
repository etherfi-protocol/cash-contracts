// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

/**
 * @title PriceProvider
 * @author ether.fi [shivam@ether.fi]
 * @notice Price oracle to get weETH/USD rate with 6 decimals
 */
contract PriceProvider is IPriceProvider {
    IAggregatorV3 public immutable weEthWethOracle;
    IAggregatorV3 public immutable ethUsdcOracle;

    uint8 public immutable weEthWethDecimals;
    uint8 public immutable ethUsdcDecimals;

    uint8 public constant decimals = 6;

    error PriceCannotBeZeroOrNegative();

    constructor(address _weEthWethOracle, address _ethUsdcOracle) {
        weEthWethOracle = IAggregatorV3(_weEthWethOracle);
        ethUsdcOracle = IAggregatorV3(_ethUsdcOracle);

        weEthWethDecimals = weEthWethOracle.decimals();
        ethUsdcDecimals = ethUsdcOracle.decimals();
    }

    /**
     * @inheritdoc IPriceProvider
     */
    function getWeEthUsdPrice() external view returns (uint256) {
        int256 priceWeEthWeth = weEthWethOracle.latestAnswer();
        if (priceWeEthWeth <= 0) revert PriceCannotBeZeroOrNegative();
        int256 priceEthUsd = ethUsdcOracle.latestAnswer();
        if (priceEthUsd <= 0) revert PriceCannotBeZeroOrNegative();

        uint256 price = (uint256(priceWeEthWeth) *
            uint256(priceEthUsd) *
            10 ** decimals) / 10 ** (weEthWethDecimals + ethUsdcDecimals);

        return price;
    }
}
