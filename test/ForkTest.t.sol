// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {Utils, ChainConfig} from "../script/user-safe/Utils.sol";
import {DebtManagerCore} from "../src/debt-manager/DebtManagerCore.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {UserSafe} from "../src/user-safe/UserSafe.sol";

contract ForkTest is Utils {
    using stdJson for string;

    address user = 0x2F9e38E716AD75B6f8005C65BD727183137393F1;
    address borrowToken = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    uint256 withdrawAmt = 10000000;
    DebtManagerCore debtManager;
    
    function setUp() public {
        vm.createSelectFork("https://1rpc.io/scroll");
        
        // string memory deployments = readDeploymentFile();
        // debtManager = DebtManagerCore(stdJson.readAddress(
        //         deployments,
        //         string.concat(".", "addresses", ".", "debtManagerProxy")
        //     )
        // );
    }
    
    // function test_Withdraw() public {
    //     vm.prank(user);
    //     debtManager.withdrawBorrowToken(borrowToken, withdrawAmt);
    // }

    function test_Scroll() public {
        address userSafe = 0x3b41152Ab1F00eD0b52C0E606e9e9838CAA2a2be;
        uint8 spendingLimitType = 1;
        uint256 spendingLimit = 10000000;

        UserSafe(userSafe).resetSpendingLimit(
            spendingLimitType, 
            spendingLimit, 
            hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000170000000000000000000000000000000000000000000000000000000000000001709632e9a9600dc7d77238183777c96a4f0b079f3116d26fce792fbbf35a42aee1b289b0001c3687db63affcae87cfe0983fc1575d960698b2bf94a1b90a983b000000000000000000000000000000000000000000000000000000000000002549960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000867b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a2247595161644851396c735a554f6266464d465552454f384b3339786c6c6e5a553754737075525456573573222c226f726967696e223a22687474703a2f2f6c6f63616c686f73743a35313733222c2263726f73734f726967696e223a66616c73657d0000000000000000000000000000000000000000000000000000"
        );
    }
}
