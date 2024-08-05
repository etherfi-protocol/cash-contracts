// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// 1Inch swap data
struct SwapDescription {
    IERC20 srcToken; // contract address of a token to sell
    IERC20 dstToken; // contract address of a token to buy
    address payable srcReceiver;
    address payable dstReceiver; // Receiver of destination currency. default: fromAddress
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
}

/// @title Interface for making arbitrary calls during swap
interface IAggregationExecutor {
    /// @notice propagates information about original msg.sender and executes arbitrary data
    function execute(address msgSender) external payable returns (uint256); // 0x4b64e492
}

interface IOneInchRouterV6 {
    type Address is uint256;

    /**
     * @notice Performs a swap, delegating all calls encoded in `data` to `executor`. See tests for usage examples.
     * @dev Router keeps 1 wei of every token on the contract balance for gas optimisations reasons.
     *      This affects first swap of every token by leaving 1 wei on the contract.
     * @param executor Aggregation executor that executes calls described in `data`.
     * @param desc Swap description.
     * @param data Encoded calls that `caller` should execute in between of swaps.
     * @return returnAmount Resulting token amount.
     * @return spentAmount Source token amount.
     */
    function swap(
        IAggregationExecutor executor,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);

    /**
     * @notice Swaps `amount` of the specified `token` for another token using an Unoswap-compatible exchange's pool,
     *         sending the resulting tokens to the `to` address, with a minimum return specified by `minReturn`.
     * @param to The address to receive the swapped tokens.
     * @param token The address of the token to be swapped.
     * @param amount The amount of tokens to be swapped.
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap.
     */
    function unoswapTo(
        uint256 to,
        uint256 token,
        uint256 amount,
        uint256 minReturn,
        uint256 dex
    ) external returns (uint256 returnAmount);

    /**
     * @notice Swaps `amount` of the specified `token` for another token using two Unoswap-compatible exchange pools (`dex` and `dex2`) sequentially,
     *         sending the resulting tokens to the `to` address, with a minimum return specified by `minReturn`.
     * @param to The address to receive the swapped tokens.
     * @param token The address of the token to be swapped.
     * @param amount The amount of tokens to be swapped.
     * @param minReturn The minimum amount of tokens to be received after the swap.
     * @param dex The address of the first Unoswap-compatible exchange's pool.
     * @param dex2 The address of the second Unoswap-compatible exchange's pool.
     * @return returnAmount The actual amount of tokens received after the swap through both pools.
     */
    function unoswapTo2(
        uint256 to,
        uint256 token,
        uint256 amount,
        uint256 minReturn,
        uint256 dex,
        uint256 dex2
    ) external returns (uint256 returnAmount);
}
