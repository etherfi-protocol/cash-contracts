// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafeV2Mock} from "../../src/mocks/UserSafeV2Mock.sol";
import {Swapper1InchV6} from "../../src/utils/Swapper1InchV6.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {UserSafeSetup, IUserSafe, UserSafeCore} from "./UserSafeSetup.t.sol";
import {OwnerLib} from "../../src/libraries/OwnerLib.sol";

error OwnableUnauthorizedAccount(address account);

contract UserSafeFactoryV2 is UserSafeFactory {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract UserSafeFactoryTest is UserSafeSetup {
    using OwnerLib for address;

    UserSafeV2Mock implV2;

    address bob = makeAddr("bob");
    bytes bobBytes = abi.encode(bob);

    IUserSafe bobSafe;
    bytes saltData = bytes("bobSafe");


    function setUp() public override {
        super.setUp();

        implV2 = new UserSafeV2Mock(address(cashDataProvider));

        vm.prank(owner);
        bobSafe = IUserSafe(
            factory.createUserSafe(
                saltData,
                abi.encodeWithSelector(
                    UserSafeCore.initialize.selector,
                    bobBytes,
                    defaultDailySpendingLimit,
                    defaultMonthlySpendingLimit,
                    collateralLimit,
                    timezoneOffset
                )
            )
        );

        vm.stopPrank();
    }

    function test_Deploy() public view {
        address deterministicAddress = factory.getUserSafeAddress(
            saltData, 
            abi.encodeWithSelector(
                UserSafeCore.initialize.selector,
                bobBytes,
                defaultDailySpendingLimit,
                defaultMonthlySpendingLimit,
                collateralLimit,
                timezoneOffset
            ));

        assertEq(deterministicAddress, address(bobSafe));
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(bobSafe.owner().ethAddr, bob);
    }

    function test_UpgradeUserSafeImpl() public {
        vm.prank(owner);
        factory.upgradeUserSafeCoreImpl(address(implV2));

        UserSafeV2Mock aliceSafeV2 = UserSafeV2Mock(address(aliceSafe));
        UserSafeV2Mock bobSafeV2 = UserSafeV2Mock(address(bobSafe));

        assertEq(aliceSafeV2.version(), 2);
        assertEq(bobSafeV2.version(), 2);
    }

    function test_UpgradeUserSafeFactory() public {
        UserSafeFactoryV2 factoryV2 = new UserSafeFactoryV2();
         
        vm.prank(owner);
        factory.upgradeToAndCall(address(factoryV2), "");

        assertEq(UserSafeFactoryV2(address(factory)).version(), 2);
    }

    function test_OnlyOwnerCanUpgradeUserSafeImpl() public {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, DEFAULT_ADMIN_ROLE));
        factory.upgradeUserSafeCoreImpl(address(implV2));
    }

    function test_OnlyOwnerCanUpgradeFactoryImpl() public {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, DEFAULT_ADMIN_ROLE));
        factory.upgradeToAndCall(address(1), "");
    }

    function test_OnlyAdminCanCreateUserSafe() public {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        factory.createUserSafe(
            saltData,
            abi.encodeWithSelector(
                UserSafeCore.initialize.selector,
                hex"112345",
                defaultDailySpendingLimit,
                defaultMonthlySpendingLimit,
                collateralLimit,
                timezoneOffset
            )
        );
    }

    function test_OnlyAdminCanSetBeacon() public {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        factory.setBeacon(address(1));
    }

    function test_SetBeacon() public {
        address newBeacon = address(1);

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit UserSafeFactory.BeaconSet(factory.beacon(), newBeacon);
        factory.setBeacon(newBeacon);
        assertEq(factory.beacon(), newBeacon);
        vm.stopPrank();
    }

    function test_CannotSetBeaconToAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(UserSafeFactory.InvalidValue.selector);
        factory.setBeacon(address(0));
    }

    function test_OnlyAdminCanSetCashDataProvider() public {
        vm.prank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        factory.setCashDataProvider(address(1));
    }

    function test_SetCashDataProvider() public {
        address newCashDataProvider = address(1);
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit UserSafeFactory.CashDataProviderSet(factory.cashDataProvider(), newCashDataProvider);
        factory.setCashDataProvider(newCashDataProvider);
        assertEq(factory.cashDataProvider(), newCashDataProvider);
        vm.stopPrank();
    }

    function test_CannotSetCashDataProviderToAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(UserSafeFactory.InvalidValue.selector);
        factory.setCashDataProvider(address(0));
    }
}