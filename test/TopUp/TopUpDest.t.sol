// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol"; 
import {TopUpDest, EIP1271SignatureUtils, PausableUpgradeable} from "../../src/top-up/TopUpDest.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

bytes32 constant USER_SAFE_REGISTRY_TYPEHASH =
    keccak256("MapWalletToUserSafe(address wallet,address userSafe,uint256 nonce,uint256 deadline)");

struct MapWalletToUserSafe {
    address wallet;
    address userSafe;
    uint256 nonce;
    uint256 deadline;
}

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
                    abi.encode(
                        owner,
                        100,
                        address(0),
                        address(0),
                        address(0),
                        address(0),
                        address(0),
                        userSafeFactory,
                        address(0),
                        makeAddr("recoverySigner1"),
                        makeAddr("recoverySigner2")
                    )
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

    function test_CanRegisterWalletToUserSafe() public {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 domainSeparator = topUpDest.DOMAIN_SEPARATOR();
        MapWalletToUserSafe memory mapWalletToUserSafe = MapWalletToUserSafe({
            wallet: alice,
            userSafe: userSafe,
            nonce: topUpDest.nonces(alice),
            deadline: 100
        });
        
        bytes32 digest = getTypedDataHash(domainSeparator, mapWalletToUserSafe);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit TopUpDest.WalletToUserSafeRegistered(alice, userSafe);
        topUpDest.mapWalletToUserSafe(alice, userSafe, 100, signature);

        assertEq(topUpDest.walletToUserSafeRegistry(alice), userSafe);
    }

    function test_CannotRegisterWalletToUserSafeIfWalletIsAddressZero() public {
        vm.expectRevert(TopUpDest.WalletCannotBeAddressZero.selector);
        topUpDest.mapWalletToUserSafe(address(0), address(1), 10, new bytes(0));
    }

    function test_CannotRegisterWalletToUserSafeIfUserSafeIsNotRegistered() public {
        vm.expectRevert(TopUpDest.NotARegisteredUserSafe.selector);
        topUpDest.mapWalletToUserSafe(address(1), address(1), 10, new bytes(0));
    }

    function test_CannotRegisterWalletToUserSafeIfDeadlineHasPassed() public {
        vm.warp(100);
        vm.expectRevert(TopUpDest.ExpiredSignature.selector);
        topUpDest.mapWalletToUserSafe(address(1), userSafe, 10, new bytes(0));
    }

    function test_CannotRegisterWalletToUserSafeIfSignatureIsInvalid() public {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        bytes32 domainSeparator = topUpDest.DOMAIN_SEPARATOR();
        MapWalletToUserSafe memory mapWalletToUserSafe = MapWalletToUserSafe({
            wallet: alice,
            userSafe: userSafe,
            nonce: 0,
            deadline: 100
        });
        
        bytes32 digest = getTypedDataHash(domainSeparator, mapWalletToUserSafe);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(EIP1271SignatureUtils.InvalidSigner.selector);
        topUpDest.mapWalletToUserSafe(notUserSafe, userSafe, 100, signature);
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

        topUpDest.topUpUserSafe(1, bytes32(uint256(1)), userSafe, address(token), amount);

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
        emit TopUpDest.TopUp(1, txId, userSafe, address(token), amount);
        topUpDest.topUpUserSafe(1, txId, userSafe, address(token), amount);
        vm.stopPrank();

        assertEq(token.balanceOf(address(topUpDest)), 0);
        assertEq(token.balanceOf(address(userSafe)), amount);
    }

    function test_CanBatchTopUpUserSafe() public {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 2;

        bytes32[] memory txIds = new bytes32[](2);
        txIds[0] = bytes32(uint256(1));
        txIds[1] = bytes32(uint256(1));

        address[] memory userSafes = new address[](2);
        userSafes[0] = makeAddr("userSafe0");
        userSafes[1] = makeAddr("userSafe1");

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 0.1 ether;

        vm.startPrank(userSafeFactory);
        cashDataProvider.whitelistUserSafe(userSafes[0]);
        cashDataProvider.whitelistUserSafe(userSafes[1]);
        vm.stopPrank();
        
        deal(address(token), address(topUpDest), 100 ether);

        vm.startPrank(owner);
        
        uint256 balTopUpDestBefore = token.balanceOf(address(topUpDest));
        assertEq(token.balanceOf(address(userSafes[0])), 0);
        assertEq(token.balanceOf(address(userSafes[1])), 0);

        vm.expectEmit(true, true, true, true);
        emit TopUpDest.TopUpBatch(chainIds, txIds, userSafes, tokens, amounts);
        topUpDest.topUpUserSafe(chainIds, txIds, userSafes, tokens, amounts);
        vm.stopPrank();

        uint256 balTopUpDestAfter = token.balanceOf(address(topUpDest));

        assertEq(token.balanceOf(address(userSafes[0])), amounts[0]);
        assertEq(token.balanceOf(address(userSafes[1])), amounts[1]);
        assertEq(balTopUpDestBefore - balTopUpDestAfter, amounts[0] + amounts[1]);
    }

    function test_CannotBatchTopUpUserSafeIfArrayLengthMismatch() public {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 2;

        bytes32[] memory txIds = new bytes32[](2);
        txIds[0] = bytes32(uint256(1));
        txIds[1] = bytes32(uint256(1));

        address[] memory userSafes = new address[](2);
        userSafes[0] = makeAddr("userSafe0");
        userSafes[1] = makeAddr("userSafe1");

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 0.1 ether;
        
        vm.startPrank(owner);
        
        txIds = new bytes32[](3);
        vm.expectRevert(TopUpDest.ArrayLengthMismatch.selector);
        topUpDest.topUpUserSafe(chainIds, txIds, userSafes, tokens, amounts);
        
        txIds = new bytes32[](2);
        userSafes = new address[](3);
        vm.expectRevert(TopUpDest.ArrayLengthMismatch.selector);
        topUpDest.topUpUserSafe(chainIds, txIds, userSafes, tokens, amounts);
        
        txIds = new bytes32[](2);
        userSafes = new address[](2);
        tokens = new address[](3);
        vm.expectRevert(TopUpDest.ArrayLengthMismatch.selector);
        topUpDest.topUpUserSafe(chainIds, txIds, userSafes, tokens, amounts);

        txIds = new bytes32[](2);
        userSafes = new address[](2);
        tokens = new address[](2);
        amounts = new uint256[](3);
        vm.expectRevert(TopUpDest.ArrayLengthMismatch.selector);
        topUpDest.topUpUserSafe(chainIds, txIds, userSafes, tokens, amounts);

        vm.stopPrank();
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
        topUpDest.topUpUserSafe(1, txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfTxIdAlreadyCompleted() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        vm.expectEmit(true, true, true, true);
        emit TopUpDest.TopUp(1, txId, userSafe, address(token), amount);
        topUpDest.topUpUserSafe(1, txId, userSafe, address(token), amount);

        vm.expectRevert(TopUpDest.TransactionAlreadyCompleted.selector);
        topUpDest.topUpUserSafe(1, txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfNotAValidUserSafe() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        token.approve(address(topUpDest), amount);
        topUpDest.deposit(address(token), amount);

        vm.expectRevert(TopUpDest.NotARegisteredUserSafe.selector);
        topUpDest.topUpUserSafe(1, txId, notUserSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfBalanceTooLow() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        vm.expectRevert(TopUpDest.BalanceTooLow.selector);
        topUpDest.topUpUserSafe(1, txId, userSafe, address(token), amount);
        vm.stopPrank();
    }

    function test_CannotTopUpIfPaused() public {
        uint256 amount = 1 ether;
        bytes32 txId = bytes32(uint256(1));

        vm.startPrank(owner);
        topUpDest.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        topUpDest.topUpUserSafe(1, txId, userSafe, address(token), amount);
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

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(
        bytes32 DOMAIN_SEPARATOR,
        MapWalletToUserSafe memory _mapWalletToUserSafe
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_mapWalletToUserSafe)
                )
            );
    }

    // computes the hash of a permit
    function getStructHash(
        MapWalletToUserSafe memory _mapWalletToUserSafe
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    USER_SAFE_REGISTRY_TYPEHASH,
                    _mapWalletToUserSafe.wallet,
                    _mapWalletToUserSafe.userSafe,
                    _mapWalletToUserSafe.nonce,
                    _mapWalletToUserSafe.deadline
                )
            );
    }
}