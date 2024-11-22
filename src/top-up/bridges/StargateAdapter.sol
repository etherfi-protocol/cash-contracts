// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IStargate, Ticket } from "../../interfaces/IStargate.sol";
import { MessagingFee, OFTReceipt, SendParam } from "../../interfaces/IOFT.sol";
import { BridgeAdapterBase } from "./BridgeAdapterBase.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StargateAdapter is BridgeAdapterBase {
    using SafeERC20 for IERC20;

    event BridgeViaStargate(address token, uint256 amount, Ticket ticket);

    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 public constant DEST_EID_SCROLL = 30214;

    error InvalidStargatePool();

    function bridge(
        address token,
        uint256 amount,
        address destRecipient,
        uint256 maxSlippage,
        bytes calldata additionalData
    ) external payable override {
        address stargatePool = abi.decode(additionalData, (address));
        uint256 minAmount = deductSlippage(amount, maxSlippage);

        (uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee, address poolToken) = 
            prepareRideBus(stargatePool, amount, destRecipient, minAmount);
        
        if (address(this).balance < valueToSend) revert InsufficientNativeFee();
        
        if (poolToken != address(0)) {
            if (poolToken != token) revert InvalidStargatePool();
            IERC20(token).forceApprove(stargatePool, amount);
        }
        (, , Ticket memory ticket) = IStargate(stargatePool).sendToken{ value: valueToSend }(sendParam, messagingFee, payable(address(this)));
        emit BridgeViaStargate(token, amount, ticket);
    }
    
    // from https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/integrate-with-stargate/how-to-swap#ride-the-bus
    function prepareRideBus(
        address stargate,
        uint256 amount,
        address destRecipient,
        uint256 minAmount
    ) public view returns (uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee, address poolToken) {
        sendParam = SendParam({
            dstEid: DEST_EID_SCROLL,
            to: bytes32(uint256(uint160(destRecipient))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(1)
        });

        (, , OFTReceipt memory receipt) = IStargate(stargate).quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;
        if (minAmount > receipt.amountReceivedLD) revert InsufficientMinAmount();

        messagingFee = IStargate(stargate).quoteSend(sendParam, false);
        valueToSend = messagingFee.nativeFee;
        poolToken = IStargate(stargate).token();
        if (poolToken == address(0)) {
            valueToSend += sendParam.amountLD;
        }
    }

    function getBridgeFee(
        address,
        uint256 amount,
        address destRecipient,
        uint256 maxSlippage,
        bytes calldata additionalData
    ) external view override returns (address, uint256) {
        address stargatePool = abi.decode(additionalData, (address));
        uint256 minAmount = deductSlippage(amount, maxSlippage);

        (, , MessagingFee memory messagingFee, ) = 
            prepareRideBus(stargatePool, amount, destRecipient, minAmount);

        return (ETH, messagingFee.nativeFee);
    }
}