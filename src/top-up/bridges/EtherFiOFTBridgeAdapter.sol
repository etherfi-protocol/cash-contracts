// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SendParam, MessagingFee, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingReceipt, SendParam, IOFT } from "../../interfaces/IOFT.sol";
import { BridgeAdapterBase } from "./BridgeAdapterBase.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EtherFiOFTBridgeAdapter is BridgeAdapterBase {
    using SafeERC20 for IERC20;

    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 public constant DEST_EID_SCROLL = 30214;
    
    event BridgeOFT(address token, uint256 amount, MessagingReceipt messageReceipt, OFTReceipt oftReceipt);

    error AmountOutOfOFTLimit();    

    function bridge(
        address token,
        uint256 amount,
        address destRecipient,
        uint256 maxSlippage,
        bytes calldata additionalData
    ) external payable override {
        IOFT oftAdapter = IOFT(abi.decode(additionalData, (address)));
        uint256 minAmount = deductSlippage(amount, maxSlippage);

        SendParam memory sendParam = SendParam({
            dstEid: DEST_EID_SCROLL,
            to: bytes32(uint256(uint160(destRecipient))),
            amountLD: amount,
            minAmountLD: minAmount,
            extraOptions: hex"0003",
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });

        MessagingFee memory messagingFee = oftAdapter.quoteSend(sendParam, false);
        if (address(this).balance < messagingFee.nativeFee) revert InsufficientNativeFee();
        
        if (oftAdapter.approvalRequired()) IERC20(token).forceApprove(address(oftAdapter), amount);
        
        (MessagingReceipt memory messageReceipt, OFTReceipt memory oftReceipt) = oftAdapter.send{ value: messagingFee.nativeFee }(sendParam, messagingFee, payable(address(this)));
        if (oftReceipt.amountReceivedLD < minAmount) revert InsufficientMinAmount();

        emit BridgeOFT(token, amount, messageReceipt, oftReceipt);
    }

    function getBridgeFee(
        address,
        uint256 amount,
        address destRecipient,
        uint256 maxSlippage,
        bytes calldata additionalData
    ) external view override returns (address, uint256) {
        IOFT oftAdapter = IOFT(abi.decode(additionalData, (address)));
        uint256 minAmount = deductSlippage(amount, maxSlippage);

        SendParam memory sendParam = SendParam({
            dstEid: DEST_EID_SCROLL,
            to: bytes32(uint256(uint160(destRecipient))),
            amountLD: amount,
            minAmountLD: minAmount,
            extraOptions: hex"0003",
            composeMsg: new bytes(0),
            oftCmd: new bytes(0)
        });

        MessagingFee memory messagingFee = oftAdapter.quoteSend(sendParam, false);

        return (ETH, messagingFee.nativeFee);
    }
}