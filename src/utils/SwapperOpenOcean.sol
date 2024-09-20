// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OpenOceanSwapDescription, IOpenOceanCaller, IOpenOceanRouter} from "../interfaces/IOpenOcean.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

contract SwapperOpenOcean is ISwapper {
    using SafeERC20 for IERC20;

    /// @notice OpenOcean router contract to give allowance to perform swaps
    address public immutable swapRouter;

    error OutputLessThanMinAmount();

    constructor(address _swapRouter, address[] memory _assets) {
        swapRouter = _swapRouter;
        _approveAssets(_assets);
    }

    /**
     * @inheritdoc ISwapper
     */
    function swap(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        uint256 _guaranteedAmount,
        bytes calldata _data
    ) external returns (uint256 toAssetAmount) {
        (
            ,
            address executor,
            IOpenOceanCaller.CallDescription[] memory calls
        ) = abi.decode(
                _data,
                (bytes4, address, IOpenOceanCaller.CallDescription[])
            );

        OpenOceanSwapDescription memory swapDesc = OpenOceanSwapDescription({
            srcToken: IERC20(_fromAsset),
            dstToken: IERC20(_toAsset),
            srcReceiver: payable(executor),
            dstReceiver: payable(msg.sender),
            amount: _fromAssetAmount,
            minReturnAmount: _minToAssetAmount,
            guaranteedAmount: _guaranteedAmount,
            flags: 2,
            referrer: msg.sender,
            permit: hex""
        });

        toAssetAmount = IOpenOceanRouter(swapRouter).swap(
            IOpenOceanCaller(executor),
            swapDesc,
            calls
        );

        if (toAssetAmount < _minToAssetAmount) revert OutputLessThanMinAmount();
    }

    /**
     * @notice Approve assets for swapping.
     * @param _assets Array of token addresses to approve.
     * @dev unlimited approval is used as no tokens sit in this contract outside a transaction.
     */
    function approveAssets(address[] memory _assets) external {
        _approveAssets(_assets);
    }

    function _approveAssets(address[] memory _assets) internal {
        for (uint256 i = 0; i < _assets.length; ) {
            // Give the 1Inch router approval to transfer unlimited assets
            IERC20(_assets[i]).forceApprove(swapRouter, type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }
}
