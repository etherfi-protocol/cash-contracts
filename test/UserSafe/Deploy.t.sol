// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafe} from "../../src/user-safe/UserSafe.sol";
import {UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeDeployTest is UserSafeSetup {
    address bob = makeAddr("bob");
    bytes bobBytes = abi.encode(bob);

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

    function test_DeployAUserSafe() public {
        factory.createUserSafe(
            abi.encodeWithSelector(
                // initialize(bytes,uint256, uint256)
                0x32b218ac,
                bobBytes,
                defaultSpendingLimit,
                collateralLimit
            )
        );
    }
}
