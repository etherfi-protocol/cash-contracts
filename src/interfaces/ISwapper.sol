// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISwapper {
    /**
     * @notice Strategist swaps assets sitting in the contract of the `assetHolder`.
     * @param _fromAsset The token address of the asset being sold by the vault.
     * @param _toAsset The token address of the asset being purchased by the vault.
     * @param _fromAssetAmount The amount of assets being sold by the vault.
     * @param _minToAssetAmount The minimum amount of assets to be purchased.
     * @param _guaranteedAmount The guaranteed amount of output (only for openocean).
     * @param _data RLP encoded executor address and bytes data. This is re-encoded tx.data from 1Inch swap API
     */
    function swap(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        uint256 _guaranteedAmount,
        bytes calldata _data
    ) external returns (uint256 toAssetAmount);
}
