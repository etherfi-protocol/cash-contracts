// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice 1Inch Pathfinder V6 implementation of the general ISwapper interface.
 * @author ether.fi [shivam@ether.fi]
 * @dev It is possible that dust token amounts are left in this contract after a swap.
 * This can happen with some tokens that don't send the full transfer amount.
 * These dust amounts can build up over time and be used by anyone who calls the `swap` function.
 */
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregationExecutor, IOneInchRouterV6, SwapDescription} from "../interfaces/IOneInch.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

contract Swapper1InchV6 is ISwapper {
    using SafeERC20 for IERC20;

    /// @notice 1Inch router contract to give allowance to perform swaps
    address public immutable swapRouter;

    // swap(address,(address,address,address,address,uint256,uint256,uint256),bytes)
    bytes4 internal constant SWAP_SELECTOR = 0x07ed2379;
    // unoswapTo(uint256,uint256,uint256,uint256,uint256)
    bytes4 internal constant UNOSWAP_TO_SELECTOR = 0xe2c95c82;
    // unoswapTo2(uint256,uint256,uint256,uint256,uint256,uint256)
    bytes4 internal constant UNOSWAP_TO_2_SELECTOR = 0xea76dddf;

    error UnsupportedSwapFunction();
    error OutputLessThanMinAmount();

    constructor(address _swapRouter, address[] memory _assets) {
        swapRouter = _swapRouter;
        _approveAssets(_assets);
    }

    /**
     * @notice Strategist swaps assets sitting in the contract of the `assetHolder`.
     * @param _fromAsset The token address of the asset being sold by the vault.
     * @param _toAsset The token address of the asset being purchased by the vault.
     * @param _fromAssetAmount The amount of assets being sold by the vault.
     * @param _minToAssetAmount The minimum amount of assets to be purchased.
     * @param _data RLP encoded executer address and bytes data. This is re-encoded tx.data from 1Inch swap API
     */
    function swap(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        uint256,
        bytes calldata _data
    ) external returns (uint256 toAssetAmount) {
        // Decode the function selector from the RLP encoded _data param
        bytes4 swapSelector = bytes4(_data[:4]);

        if (swapSelector == SWAP_SELECTOR) {
            // Decode the executer address and data from the RLP encoded _data param
            (, address executer, bytes memory executerData) = abi.decode(
                _data,
                (bytes4, address, bytes)
            );
            SwapDescription memory swapDesc = SwapDescription({
                srcToken: IERC20(_fromAsset),
                dstToken: IERC20(_toAsset),
                srcReceiver: payable(executer),
                dstReceiver: payable(msg.sender),
                amount: _fromAssetAmount,
                minReturnAmount: _minToAssetAmount,
                flags: 0 // 1st bit _PARTIAL_FILL, 2nd bit _REQUIRES_EXTRA_ETH, 3rd bit _SHOULD_CLAIM
            });
            (toAssetAmount, ) = IOneInchRouterV6(swapRouter).swap(
                IAggregationExecutor(executer),
                swapDesc,
                executerData
            );
        } else if (swapSelector == UNOSWAP_TO_SELECTOR) {
            // Need to get the Uniswap pools data from the _data param
            (, uint256 dex) = abi.decode(_data, (bytes4, uint256));
            toAssetAmount = IOneInchRouterV6(swapRouter).unoswapTo(
                uint256(uint160(msg.sender)),
                uint256(uint160(_fromAsset)),
                _fromAssetAmount,
                _minToAssetAmount,
                dex
            );
        } else if (swapSelector == UNOSWAP_TO_2_SELECTOR) {
            // Need to get the Uniswap pools data from the _data param
            (, uint256 dex, uint256 dex2) = abi.decode(
                _data,
                (bytes4, uint256, uint256)
            );
            toAssetAmount = IOneInchRouterV6(swapRouter).unoswapTo2(
                uint256(uint160(msg.sender)),
                uint256(uint160(_fromAsset)),
                _fromAssetAmount,
                _minToAssetAmount,
                dex,
                dex2
            );
        } else {
            revert UnsupportedSwapFunction();
        }

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
