// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title TokenDecimalCache
 * @author ether.fi (shivam@ether.fi)
 * @notice Contract to cache decimals for tokens.
 */
contract TokenDecimalCache {
    mapping(address token => uint8 decimals) private _cachedDecimals;

    event CacheDecimals(address[] tokens);

    /**
     * @notice Function to cache token decimals.
     * @param  tokens Array of token addresses to cache decimals for.
     */
    function cacheDecimals(address[] memory tokens) public {
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ) {
            _cachedDecimals[tokens[i]] = IERC20Metadata(tokens[i]).decimals();

            unchecked {
                ++i;
            }
        }

        emit CacheDecimals(tokens);
    }

    /**
     * @notice Function to fetch token decimals.
     * @param  token Address of the token to fetch decimals for.
     * @return Token decimals.
     */
    function getDecimals(address token) public view returns (uint8) {
        return
            _cachedDecimals[token] != 0
                ? _cachedDecimals[token]
                : IERC20Metadata(token).decimals();
    }
}
