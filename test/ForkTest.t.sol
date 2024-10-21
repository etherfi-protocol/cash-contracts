// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {Utils, ChainConfig} from "../script/user-safe/Utils.sol";
import {DebtManagerCore} from "../src/debt-manager/DebtManagerCore.sol";
import {CashSafe} from "../src/cash-safe/CashSafe.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ForkTest is Utils {
    using stdJson for string;

    address user = 0x7D829d50aAF400B8B29B3b311F4aD70aD819DC6E;
    address borrowToken = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    uint256 withdrawAmt = 3000000;
    DebtManagerCore debtManager;
    CashSafe cashSafe;
    
    function setUp() public {
        vm.createSelectFork("https://1rpc.io/scroll");
        
        string memory deployments = readDeploymentFile();
        debtManager = DebtManagerCore(stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "debtManagerProxy")
            )
        );

        cashSafe = CashSafe(payable(stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "cashSafeProxy")
            ))
        );
    }
    
    // function test_Withdraw() public {
    //     vm.prank(user);
    //     debtManager.withdrawBorrowToken(borrowToken, withdrawAmt);
    // }
    
    // function test_Bridge() public {
    //     ( , uint256 valueToSend, , ) = cashSafe.prepareRideBus(borrowToken, withdrawAmt);
        
    //     vm.prank(user);
    //     cashSafe.bridge{value: valueToSend}(borrowToken, withdrawAmt);
    // }
}
