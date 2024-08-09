// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe, OwnerLib} from "../../src/user-safe/UserSafe.sol";
import {UserSafeV2Mock} from "../../src/mocks/UserSafeV2Mock.sol";
import {Swapper1InchV6} from "../../src/utils/Swapper1InchV6.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {UserSafeSetup} from "./UserSafeSetup.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UserSafeFactoryTest is UserSafeSetup {
    using OwnerLib for address;

    UserSafeV2Mock implV2;

    address bob = makeAddr("bob");
    bytes bobBytes = abi.encode(bob);

    UserSafe bobSafe;

    function setUp() public override {
        super.setUp();

        implV2 = new UserSafeV2Mock(
            address(cashDataProvider),
            etherFiRecoverySigner,
            thirdPartyRecoverySigner
        );

        bobSafe = UserSafe(
            factory.createUserSafe(
                abi.encodeWithSelector(
                    // initialize(bytes,uint256, uint256)
                    0x32b218ac,
                    bobBytes,
                    defaultSpendingLimit,
                    collateralLimit
                )
            )
        );

        vm.stopPrank();
    }

    function test_Deploy() public view {
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(bobSafe.owner().ethAddr, bob);
    }

    function test_Upgrade() public {
        vm.prank(owner);
        factory.upgradeTo(address(implV2));

        UserSafeV2Mock aliceSafeV2 = UserSafeV2Mock(address(aliceSafe));
        UserSafeV2Mock bobSafeV2 = UserSafeV2Mock(address(bobSafe));

        assertEq(aliceSafeV2.version(), 2);
        assertEq(bobSafeV2.version(), 2);
        assertEq(aliceSafeV2.usdc(), cashDataProvider.usdc());
        assertEq(aliceSafeV2.weETH(), cashDataProvider.weETH());
    }
}
