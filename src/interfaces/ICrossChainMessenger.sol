// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// facilitate pair-wise communication
interface ICrossChainMessenger {
    function send(address asset, uint256 amount) external;

    function setCrossChainMessenger(address newMessenger) external;
}
