// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface INttManager {

    /// @notice Fetch the delivery price for a given recipient chain transfer.
    /// @param recipientChain The Wormhole chain ID of the transfer destination.
    /// @param transceiverInstructions The transceiver specific instructions for quoting and sending
    /// @return - The delivery prices associated with each enabled endpoint and the total price.
    function quoteDeliveryPrice(
        uint16 recipientChain,
        bytes memory transceiverInstructions
    ) external view returns (uint256[] memory, uint256);

    /// @notice Transfer a given amount to a recipient on a given chain. This function is called
    ///         by the user to send the token cross-chain. This function will either lock or burn the
    ///         sender's tokens. Finally, this function will call into registered `Endpoint` contracts
    ///         to send a message with the incrementing sequence number and the token transfer payload.
    /// @param amount The amount to transfer.
    /// @param recipientChain The Wormhole chain ID for the destination.
    /// @param recipient The recipient address.
    /// @return msgId The resulting message ID of the transfer
    function transfer(
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient
    ) external payable returns (uint64 msgId);

}
