// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract BridgeAdapterBase {
    using Math for uint256;
    
    address ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error InsufficientNativeFee();
    error InsufficientMinAmount();

    function deductSlippage(uint256 amount, uint256 slippage) internal pure returns (uint256) {
        return amount.mulDiv(10000 - slippage, 10000);
    }

    function bridge(
        address token, 
        uint256 amount, 
        address destRecipient, 
        uint256 maxSlippage, 
        bytes calldata additionalData
    ) external payable virtual;

    function getBridgeFee(
        address token, 
        uint256 amount, 
        address destRecipient, 
        uint256 maxSlippage, 
        bytes calldata additionalData
    ) external view virtual returns (address, uint256);
}