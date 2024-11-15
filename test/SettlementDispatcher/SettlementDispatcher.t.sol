// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test, console, stdError} from "forge-std/Test.sol";
import {SettlementDispatcher, Ticket, MessagingFee, OFTReceipt, SendParam} from "../../src/settlement-dispatcher/SettlementDispatcher.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract CashSafeTest is Test {
    bytes32 public constant BRIDGER_ROLE = keccak256("BRIDGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    address owner = makeAddr("owner");
    address bridger = makeAddr("bridger");
    address alice = makeAddr("alice");

    SettlementDispatcher settlementDispatcher;  
    // Scroll
    ERC20 usdc = ERC20(0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4);
    ERC20 weth = ERC20(0x5300000000000000000000000000000000000004);
    // https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/technical-reference/mainnet-contracts#scroll
    address stargateUsdcPool = 0x3Fc69CC4A842838bCDC9499178740226062b14E4;
    address stargateEthPool = 0xC2b638Cb5042c1B3c5d5C969361fB50569840583;
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 optimismDestEid = 30111;
    uint48 accessControlDelay = 100;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/scroll");

        vm.startPrank(owner);
        address settlementDispatcherImpl = address(new SettlementDispatcher());
        settlementDispatcher = SettlementDispatcher(payable(address(new UUPSProxy(settlementDispatcherImpl, hex""))));

        (address[] memory tokens, SettlementDispatcher.DestinationData[] memory destDatas) = getDestData();

        vm.expectEmit(true, true, true, true);
        emit SettlementDispatcher.DestinationDataSet(tokens, destDatas);
        settlementDispatcher.initialize(accessControlDelay, bridger, tokens, destDatas);
        vm.stopPrank();
    }

    function test_Deploy() public view {
        SettlementDispatcher.DestinationData memory destData = settlementDispatcher.destinationData(address(usdc));

        assertEq(destData.destEid, optimismDestEid);
        assertEq(destData.destRecipient, alice);
        assertEq(destData.stargate, stargateUsdcPool);
        
        assertEq(settlementDispatcher.hasRole(DEFAULT_ADMIN_ROLE, owner), true);
        assertEq(settlementDispatcher.hasRole(DEFAULT_ADMIN_ROLE, bridger), false);
        assertEq(settlementDispatcher.hasRole(DEFAULT_ADMIN_ROLE, alice), false);

        assertEq(settlementDispatcher.hasRole(BRIDGER_ROLE, bridger), true);
        assertEq(settlementDispatcher.hasRole(BRIDGER_ROLE, owner), false);
        assertEq(settlementDispatcher.hasRole(BRIDGER_ROLE, alice), false);
    }

    function test_CanSetDestinationData() public {
        (address[] memory tokens, SettlementDispatcher.DestinationData[] memory destDatas) = getDestData();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit SettlementDispatcher.DestinationDataSet(tokens, destDatas);
        settlementDispatcher.setDestinationData(tokens, destDatas);

        SettlementDispatcher.DestinationData memory destData = settlementDispatcher.destinationData(address(usdc));

        assertEq(destData.destEid, optimismDestEid);
        assertEq(destData.destRecipient, alice);
        assertEq(destData.stargate, stargateUsdcPool);
    }

    function test_OnlyAdminCanSetDestData() public {
        (address[] memory tokens, SettlementDispatcher.DestinationData[] memory destDatas) = getDestData();

        vm.prank(alice);
        vm.expectRevert(buildAccessControlRevertData(alice, DEFAULT_ADMIN_ROLE));
        settlementDispatcher.setDestinationData(tokens, destDatas);
    }

    function test_CannotSetDestDataIfArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        SettlementDispatcher.DestinationData[] memory destDatas = new SettlementDispatcher.DestinationData[](1);
        vm.prank(owner);
        vm.expectRevert(SettlementDispatcher.ArrayLengthMismatch.selector);
        settlementDispatcher.setDestinationData(tokens, destDatas);
    }

    function test_CannotSetInvalidValuesInDestData() public {
        (address[] memory tokens, SettlementDispatcher.DestinationData[] memory destDatas) = getDestData();

        vm.startPrank(owner);
        tokens[0] = address(0);

        vm.expectRevert(SettlementDispatcher.InvalidValue.selector);
        settlementDispatcher.setDestinationData(tokens, destDatas);

        tokens[0] = address(usdc);
        destDatas[0].destRecipient = address(0);

        vm.expectRevert(SettlementDispatcher.InvalidValue.selector);
        settlementDispatcher.setDestinationData(tokens, destDatas);

        destDatas[0].destRecipient = alice;
        destDatas[0].stargate = address(0);

        vm.expectRevert(SettlementDispatcher.InvalidValue.selector);
        settlementDispatcher.setDestinationData(tokens, destDatas);
        vm.stopPrank();
    }

    function test_CannotSetInvalidStargateValue() public {
        (address[] memory tokens, SettlementDispatcher.DestinationData[] memory destDatas) = getDestData();

        vm.startPrank(owner);
        destDatas[0].stargate = stargateEthPool;
        vm.expectRevert(SettlementDispatcher.StargateValueInvalid.selector);
        settlementDispatcher.setDestinationData(tokens, destDatas);
        vm.stopPrank();
    }

    function test_Bridge() public {
        uint256 balBefore = 100e6;
        deal(address(usdc), address(settlementDispatcher), balBefore);
        
        uint256 amount = 10e6;
        ( , uint256 valueToSend, , , ) = settlementDispatcher.prepareRideBus(address(usdc), amount);

        deal(address(settlementDispatcher), valueToSend);
        
        uint256 stargateBalBefore = usdc.balanceOf(address(stargateUsdcPool));

        vm.prank(bridger);
        settlementDispatcher.bridge(address(usdc), amount, 1);

        uint256 stargateBalAfter = usdc.balanceOf(address(stargateUsdcPool));

        assertEq(usdc.balanceOf(address(settlementDispatcher)), balBefore - amount);
        assertEq(stargateBalAfter - stargateBalBefore, amount);
    }

    function test_OnlyBridgerCanBridgeFunds() public {
        vm.prank(alice);
        vm.expectRevert(buildAccessControlRevertData(alice, BRIDGER_ROLE));
        settlementDispatcher.bridge(address(usdc), 1, 1);
    }

    function test_CannotBridgeIfInvalidValuesArePassed() public {
        vm.startPrank(bridger);
        vm.expectRevert(SettlementDispatcher.InvalidValue.selector);
        settlementDispatcher.bridge(address(0), 1, 1);
        
        vm.expectRevert(SettlementDispatcher.InvalidValue.selector);
        settlementDispatcher.bridge(address(usdc), 0, 1);
        vm.stopPrank();
    }

    function test_CannotBridgeIfDestDataIsNotSet() public {
        deal(address(weth), address(settlementDispatcher), 1 ether);
        vm.prank(bridger);
        vm.expectRevert(SettlementDispatcher.DestinationDataNotSet.selector);
        settlementDispatcher.bridge(address(weth), 1, 1);
    }

    function test_CannotBridgeFundsIfBalanceInsufficient() public {
        assertEq(usdc.balanceOf(address(settlementDispatcher)), 0);

        vm.prank(bridger);
        vm.expectRevert(SettlementDispatcher.InsufficientBalance.selector);
        settlementDispatcher.bridge(address(usdc), 1, 1);
    }

    function test_CannotBridgeFundsIfNoFee() public {
        uint256 balBefore = 100e6;
        deal(address(usdc), address(settlementDispatcher), balBefore);
        
        uint256 amount = 10e6;
        ( , uint256 valueToSend, , , ) = settlementDispatcher.prepareRideBus(address(usdc), amount);

        deal(address(settlementDispatcher), valueToSend - 1);
        
        vm.prank(bridger);
        vm.expectRevert(SettlementDispatcher.InsufficientFeeToCoverCost.selector);
        settlementDispatcher.bridge(address(usdc), amount, 1);
    }

    function test_CannotBridgeIfMinReturnIsTooLow() public {
        uint256 balBefore = 100e6;
        deal(address(usdc), address(settlementDispatcher), balBefore);
        uint256 amount = 10e6;
        ( , uint256 valueToSend, uint256 minReturnFromStargate, , ) = settlementDispatcher.prepareRideBus(address(usdc), amount);
        deal(address(settlementDispatcher), valueToSend);
        
        vm.prank(bridger);
        vm.expectRevert(SettlementDispatcher.InsufficientMinReturn.selector);
        settlementDispatcher.bridge(address(usdc), amount, minReturnFromStargate + 1);
    }

    function test_WithdrawErc20Funds() public {
        deal(address(usdc), address(settlementDispatcher), 1 ether);
        uint256 amount = 100e6;

        uint256 aliceBalBefore = usdc.balanceOf(alice);
        uint256 safeBalBefore = usdc.balanceOf(address(settlementDispatcher));
        
        vm.prank(owner);
        settlementDispatcher.withdrawFunds(address(usdc), alice, amount);

        uint256 aliceBalAfter = usdc.balanceOf(alice);
        uint256 safeBalAfter = usdc.balanceOf(address(settlementDispatcher));

        assertEq(aliceBalAfter - aliceBalBefore, amount);
        assertEq(safeBalBefore - safeBalAfter, amount);

        // withdraw all
        vm.prank(owner);
        settlementDispatcher.withdrawFunds(address(usdc), alice, 0);

        aliceBalAfter = usdc.balanceOf(alice);
        safeBalAfter = usdc.balanceOf(address(settlementDispatcher));

        assertEq(aliceBalAfter - aliceBalBefore, safeBalBefore);
        assertEq(safeBalAfter, 0);
    }

    function test_WithdrawNativeFunds() public {
        deal(address(settlementDispatcher), 1 ether);
        uint256 amount = 100e6;

        uint256 aliceBalBefore = alice.balance;
        uint256 safeBalBefore = address(settlementDispatcher).balance;
        
        vm.prank(owner);
        settlementDispatcher.withdrawFunds(address(0), alice, amount);

        uint256 aliceBalAfter = alice.balance;
        uint256 safeBalAfter = address(settlementDispatcher).balance;

        assertEq(aliceBalAfter - aliceBalBefore, amount);
        assertEq(safeBalBefore - safeBalAfter, amount);

        // withdraw all
        vm.prank(owner);
        settlementDispatcher.withdrawFunds(address(0), alice, 0);

        aliceBalAfter = alice.balance;
        safeBalAfter = address(settlementDispatcher).balance;

        assertEq(aliceBalAfter - aliceBalBefore, safeBalBefore);
        assertEq(safeBalAfter, 0);
    }

    function test_CannotWithdrawIfRecipientIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(SettlementDispatcher.InvalidValue.selector);
        settlementDispatcher.withdrawFunds(address(usdc), address(0), 1);
    }

    function test_CannotWithdrawIfNoBalance() public {
        vm.prank(owner);
        vm.expectRevert(SettlementDispatcher.CannotWithdrawZeroAmount.selector);
        settlementDispatcher.withdrawFunds(address(usdc), alice, 0);
        
        vm.prank(owner);
        vm.expectRevert(SettlementDispatcher.CannotWithdrawZeroAmount.selector);
        settlementDispatcher.withdrawFunds(address(0), alice, 0);
    }

    function test_CannotWithdrawIfInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert();
        settlementDispatcher.withdrawFunds(address(usdc), alice, 1);
        
        vm.prank(owner);
        vm.expectRevert(SettlementDispatcher.WithdrawFundsFailed.selector);
        settlementDispatcher.withdrawFunds(address(0), alice, 1);
    }

    function getDestData() internal view returns (address[] memory tokens, SettlementDispatcher.DestinationData[] memory destDatas) {
        tokens = new address[](1);
        tokens[0] = address(usdc);

        destDatas = new SettlementDispatcher.DestinationData[](1);
        destDatas[0] = SettlementDispatcher.DestinationData({
            destEid: optimismDestEid,
            destRecipient: alice,
            stargate: stargateUsdcPool
        });
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