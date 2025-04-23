// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import { BridgeAdapterBase } from "./BridgeAdapterBase.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INttManager} from "../../interfaces/INttManager.sol";

contract NTTAdapter is BridgeAdapterBase {
    using SafeERC20 for IERC20;

    event BridgeViaNTT(address token, uint256 amount, uint64 msgId);

    // https://wormhole.com/docs/build/reference/chain-ids/
    uint16 public constant DEST_EID_SCROLL = 34;

    error InvalidNTTManager();

    function bridge(
        address token,
        uint256 amount,
        address destRecipient,
        uint256 /*maxSlippage*/,
        bytes calldata additionalData
    ) external payable override {
        address nttManager = abi.decode(additionalData, (address));

        (,uint256 price) = INttManager(nttManager).quoteDeliveryPrice(DEST_EID_SCROLL, new bytes(1));
        if (address(this).balance < price) revert InsufficientNativeFee();
        
        IERC20(token).forceApprove(nttManager, amount);

        uint64 msgId = INttManager(nttManager).transfer{value: price}(amount, DEST_EID_SCROLL, bytes32(uint256(uint160(destRecipient))));
        emit BridgeViaNTT(token, amount, msgId);
    }
    
    function getBridgeFee(
        address,
        uint256 amount,
        address destRecipient,
        uint256 /*maxSlippage*/,
        bytes calldata additionalData
    ) external view override returns (address, uint256) {
        address nttManager = abi.decode(additionalData, (address));
        (,uint256 price) = INttManager(nttManager).quoteDeliveryPrice(DEST_EID_SCROLL, new bytes(1));
        return (ETH, price);
    }
}
