// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

library ArrayDeDupTransient {
    error DuplicateTokenFound();

    function checkDuplicates(address[] calldata tokens) internal {
        bytes4 errorSelector = DuplicateTokenFound.selector;
        // Use assembly to interact with transient storage
        assembly {
            // Iterate through the tokens array
            for { let i := 0 } lt(i, tokens.length) { i := add(i, 1) }
            {
                // Load the current token address
                let token := calldataload(add(tokens.offset, mul(i, 0x20)))
                
                // Check if the token has been seen before
                if tload(token) {
                    // If found, revert with custom error
                    mstore(0x00, errorSelector) 
                    revert(0x00, 0x04)
                }
                
                // Mark the token as seen
                tstore(token, 1)
            }

            for { let i := 0 } lt(i, tokens.length) { i := add(i, 1) }
            {
                let token := calldataload(add(tokens.offset, mul(i, 0x20)))
                tstore(token, 0)
            }
        }
    }

}