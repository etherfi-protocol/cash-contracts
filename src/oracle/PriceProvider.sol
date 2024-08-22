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
    address public immutable weETH;
    IAggregatorV3 public immutable weEthWethOracle;
    IAggregatorV3 public immutable ethUsdcOracle;

    uint8 public immutable weEthWethDecimals;
    uint8 public immutable ethUsdcDecimals;

    uint8 public constant DECIMALS = 6;

    error PriceCannotBeZeroOrNegative();

    constructor(
        address _weETH,
        address _weEthWethOracle,
        address _ethUsdcOracle
    ) {
        weETH = _weETH;
        weEthWethOracle = IAggregatorV3(_weEthWethOracle);
        ethUsdcOracle = IAggregatorV3(_ethUsdcOracle);

        weEthWethDecimals = weEthWethOracle.decimals();
        ethUsdcDecimals = ethUsdcOracle.decimals();
    }

    /**
     * @inheritdoc IPriceProvider
     */
    function price(address token) external view returns (uint256) {
        if (token != weETH) revert UnknownToken();

        int256 priceWeEthWeth = weEthWethOracle.latestAnswer();
        if (priceWeEthWeth <= 0) revert PriceCannotBeZeroOrNegative();
        int256 priceEthUsd = ethUsdcOracle.latestAnswer();
        if (priceEthUsd <= 0) revert PriceCannotBeZeroOrNegative();

        uint256 returnPrice = (uint256(priceWeEthWeth) *
            uint256(priceEthUsd) *
            10 ** DECIMALS) / 10 ** (weEthWethDecimals + ethUsdcDecimals);

        return returnPrice;
    }
}
