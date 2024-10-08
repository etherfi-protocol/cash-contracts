// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockSwapper {
    using SafeERC20 for IERC20;

    error InvalidMinToAssetAmount();

    function swap(
        address, // _fromAsset
        address _toAsset,
        uint256, // _fromAssetAmount
        uint256 _minToAssetAmount,
        uint256, // _guaranteedAmount
        bytes calldata // _data
    ) external returns (uint256 toAssetAmount) {
        // more than a million usdc swap we won't support on test
        if (_minToAssetAmount > 1e12) revert InvalidMinToAssetAmount();
        IERC20(_toAsset).safeTransfer(msg.sender, _minToAssetAmount);
        return _minToAssetAmount;
    }

    function approveAssets(address[] memory _assets) external {}
}
