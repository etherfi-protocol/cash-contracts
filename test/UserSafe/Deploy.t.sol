// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";

contract UserSafeDeployTest is UserSafeSetup {
    function test_Deploy() public view {
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(aliceSafe.recoverySigners()[0].ethAddr, alice);
        assertEq(aliceSafe.recoverySigners()[1].ethAddr, etherFiRecoverySigner);
        assertEq(
            aliceSafe.recoverySigners()[2].ethAddr,
            thirdPartyRecoverySigner
        );

        UserSafe.SpendingLimitData memory spendingLimit = aliceSafe
            .spendingLimit();
        assertEq(spendingLimit.spendingLimit, defaultSpendingLimit);
    }
}
