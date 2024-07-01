// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

/// @notice Minimalist and gas efficient standard ERC1155 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract CustomERC1155 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event URI(string value, uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                             ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct TokenData {
        address owner;
        uint8 tokenTier;
    }
    TokenData[] public tokens;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                             METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    function uri(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                              ERC1155 LOGIC
    //////////////////////////////////////////////////////////////*/


    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address /*from*/,
        address /*to*/,
        uint256 /*id*/,
        uint256 /*amount*/,
        bytes calldata /*data*/
    ) public virtual {
        revert("TRANSFER_DISABLED");
    }

    function safeBatchTransferFrom(
        address /*from*/,
        address /*to*/,
        uint256[] calldata /*ids*/,
        uint256[] calldata /*data*/,
        bytes calldata /*data*/
    ) public virtual {
        revert("TRANSFER_DISABLED");
    }

    function balanceOf(address account, uint256 id) public view virtual returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");

        return tokens[id].owner == account ? 1 : 0;
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        public
        view
        virtual
        returns (uint256[] memory balances)
    {
        require(owners.length == ids.length, "LENGTH_MISMATCH");

        balances = new uint256[](owners.length);

        // Unchecked because the only math done is incrementing
        // the array index counter which cannot possibly overflow.
        unchecked {
            for (uint256 i = 0; i < owners.length; ++i) {
                balances[i] = balanceOf(owners[i], ids[i]);
            }
        }
    }

    // Scan for all tokens in the provided range (exclusive) for target user.
    // This is intended to be called off-chain
    function tokensForUser(address user, uint256 startIndex, uint256 endIndex) public view returns (uint256[] memory) {
        require(startIndex < endIndex, "invalid range");
        require(endIndex <= tokens.length, "invalid range");

        uint256[] memory ownedTokens = new uint256[](tokens.length);

        uint256 numOwned = 0;
        for (uint256 idx = startIndex; idx < endIndex; ++idx) {
            if (tokens[idx].owner == user) {
                ownedTokens[numOwned++] = idx;
            }
        }

        // truncate result
        assembly { mstore(ownedTokens, numOwned) }
        return ownedTokens;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xd9b67a26 || // ERC165 Interface ID for ERC1155
            interfaceId == 0x0e89341c; // ERC165 Interface ID for ERC1155MetadataURI
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function safeMint(
        address to,
        uint8 tier,
        uint256 tokenId
    ) internal virtual {

        tokens[tokenId] = TokenData(to, tier);

        emit TransferSingle(msg.sender, address(0), to, tokenId, 1);

        require(
            to.code.length == 0
                ? to != address(0)
                : ERC1155TokenReceiver(to).onERC1155Received(msg.sender, address(0), tokenId, 1, "") ==
                    ERC1155TokenReceiver.onERC1155Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

}

/// @notice A generic interface for a contract which properly accepts ERC1155 tokens.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract ERC1155TokenReceiver {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
