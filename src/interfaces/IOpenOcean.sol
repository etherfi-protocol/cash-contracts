// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct OpenOceanSwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address srcReceiver;
    address dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 guaranteedAmount;
    uint256 flags;
    address referrer;
    bytes permit;
}

/// @title Interface for making arbitrary calls during swap
interface IOpenOceanCaller {
    struct CallDescription {
        uint256 target;
        uint256 gasLimit;
        uint256 value;
        bytes data;
    }

    function makeCall(CallDescription memory desc) external;

    function makeCalls(CallDescription[] memory desc) external payable;
}

interface IOpenOceanRouter {
    /// @notice Performs a swap, delegating all calls encoded in `data` to `executor`.
    function swap(
        IOpenOceanCaller caller,
        OpenOceanSwapDescription calldata desc,
        IOpenOceanCaller.CallDescription[] calldata calls
    ) external returns (uint256 returnAmount);
}
