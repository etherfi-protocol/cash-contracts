// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol"; 
import {TopUpDest, PausableUpgradeable} from "../../src/top-up/TopUpDest.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TopUpDestTest is Test {
    address userSafeFactory = makeAddr("userSafeFactory");
    address owner = makeAddr("owner");
    address noRole = makeAddr("noRole");
    address userSafe = makeAddr("userSafe");
    address notUserSafe = makeAddr("notUserSafe");
    TopUpDest topUpDest;
    CashDataProvider cashDataProvider;

    MockERC20 token;

    function setUp() public {
        vm.startPrank(owner);
        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(address(
            new UUPSProxy(
                cashDataProviderImpl,
                abi.encodeWithSelector(
                    CashDataProvider.initialize.selector, 
                    owner,
                    100,
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    userSafeFactory
                )
            )
        ));

        address topUpDestImpl = address(new TopUpDest());
        topUpDest = TopUpDest(address(
            new UUPSProxy(
                topUpDestImpl,
                abi.encodeWithSelector(
                    TopUpDest.initialize.selector,
                    100,
                    owner,
                    address(cashDataProvider)
                )
            )
        ));


        token = new MockERC20("Mock", "MCK", 18);
        vm.stopPrank();

        vm.prank(userSafeFactory);
        cashDataProvider.whitelistUserSafe(userSafe);
    }

    function test_CanDeposit() external {
        uint256 amount = 1 ether;

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        vm.expectEmit(true, true, true, true);
        emit TopUpDest.Deposit(address(token), amount);
        topUpDest.deposit(address(token), amount);
        vm.stopPrank();

        assertEq(topUpDest.deposits(address(token)), amount);

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        vm.expectEmit(true, true, true, true);
        emit TopUpDest.Deposit(address(token), amount);
        topUpDest.deposit(address(token), amount);
        vm.stopPrank();
        
        assertEq(topUpDest.deposits(address(token)), 2 * amount);
    }

    function test_OnlyDepositorCanDeposit() public {
        uint256 amount = 1 ether;
        deal(address(token), noRole, amount);

        vm.startPrank(noRole);
        token.approve(address(topUpDest), amount);
        vm.expectRevert(buildAccessControlRevertData(noRole, topUpDest.DEPOSITOR_ROLE()));
        topUpDest.deposit(address(token), amount);
        vm.stopPrank();
    }

    function test_CannotDepositZeroAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpDest.AmountCannotBeZero.selector);
        topUpDest.deposit(address(token), 0);
        vm.stopPrank();
    }

    function test_CanWithdraw() public {
        uint256 amount = 1 ether;

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        vm.expectEmit(true, true, true, true);
        emit TopUpDest.Withdrawal(address(token), amount);
        topUpDest.withdraw(address(token), amount);
        vm.stopPrank();
    }

    function test_CannotWithdrawZeroAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpDest.AmountCannotBeZero.selector);
        topUpDest.withdraw(address(token), 0);
        vm.stopPrank();
    }

    function test_CannotWithdrawIfAmountGreaterThanDeposit() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpDest.AmountGreaterThanDeposit.selector);
        topUpDest.withdraw(address(token), 1);
        vm.stopPrank();
    }

    function test_CannotWithdrawIfBalanceTooLow() public {
        uint256 amount = 1 ether;

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        topUpDest.topUpUserSafe(bytes32(uint256(1)), userSafe, address(token), amount);

        vm.expectRevert(TopUpDest.BalanceTooLow.selector);
        topUpDest.withdraw(address(token), 1);
        vm.stopPrank();
    }

    function test_CanTopUpUserSafe() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        vm.expectEmit(true, true, true, true);
        emit TopUpDest.TopUp(txId, userSafe, address(token), amount);
        topUpDest.topUpUserSafe(txId, userSafe, address(token), amount);
        vm.stopPrank();

        assertEq(token.balanceOf(address(topUpDest)), 0);
        assertEq(token.balanceOf(address(userSafe)), amount);
    }

    function test_OnlyTopUpRoleCanTopUpUserSafe() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);
        vm.stopPrank();

        vm.startPrank(noRole);
        vm.expectRevert(buildAccessControlRevertData(noRole, topUpDest.TOP_UP_ROLE()));
        topUpDest.topUpUserSafe(txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfTxIdAlreadyCompleted() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        vm.expectEmit(true, true, true, true);
        emit TopUpDest.TopUp(txId, userSafe, address(token), amount);
        topUpDest.topUpUserSafe(txId, userSafe, address(token), amount);

        vm.expectRevert(TopUpDest.TransactionAlreadyCompleted.selector);
        topUpDest.topUpUserSafe(txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfNotAValidUserSafe() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        vm.expectRevert(TopUpDest.NotARegisteredUserSafe.selector);
        topUpDest.topUpUserSafe(txId, notUserSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfBalanceTooLow() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        vm.expectRevert(TopUpDest.BalanceTooLow.selector);
        topUpDest.topUpUserSafe(txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfPaused() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        topUpDest.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        topUpDest.topUpUserSafe(txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_OnlyPauserCanPause() public {
        address pauser = makeAddr("pauser");
        vm.startPrank(owner);
        topUpDest.grantRole(topUpDest.PAUSER_ROLE(), pauser);
        vm.stopPrank();

        vm.startPrank(pauser);
        topUpDest.pause();
        vm.stopPrank();
    }

    function test_OnlyDefaultAdminCanUnPause() public {
        address pauser = makeAddr("pauser");
        vm.startPrank(owner);
        topUpDest.grantRole(topUpDest.PAUSER_ROLE(), pauser);
        vm.stopPrank();

        vm.prank(pauser);
        topUpDest.pause();

        vm.startPrank(pauser);
        vm.expectRevert(buildAccessControlRevertData(pauser, topUpDest.DEFAULT_ADMIN_ROLE()));
        topUpDest.unpause();
        vm.stopPrank();

        vm.startPrank(owner);
        topUpDest.unpause();
        vm.stopPrank();
    }


    function test_CannotPauseIfAlreadyPaused() public {
        vm.startPrank(owner);
        topUpDest.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        topUpDest.pause();
        vm.stopPrank();
    }

    function test_CannotUnpauseIfNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        topUpDest.unpause();
    }


    function buildAccessControlRevertData(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                role
            );
    }
}