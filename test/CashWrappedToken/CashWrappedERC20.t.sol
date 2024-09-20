// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {CashTokenWrapperFactory, CashWrappedERC20} from "../../src/cash-wrapper-token/CashTokenWrapperFactory.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

error OwnableUnauthorizedAccount(address account);

contract CashWrappedERC20Test is Test {
    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");

    CashTokenWrapperFactory tokenFactory;
    CashWrappedERC20 impl;
    MockERC20 weETH;
    CashWrappedERC20 wweETH;

    function setUp() public {
        vm.startPrank(owner);
        weETH = new MockERC20("Wrapped eETH", "weETH", 18);
        impl = new CashWrappedERC20();
        tokenFactory = new CashTokenWrapperFactory(address(impl), owner);
        wweETH = CashWrappedERC20(tokenFactory.deployWrapper(address(weETH)));
        vm.stopPrank();
    }

    function test_DeployCashWrappedToken() public view {
        assertEq(wweETH.name(), "eCash Wrapped eETH");
        assertEq(wweETH.symbol(), "ecweETH");
        assertEq(wweETH.decimals(), 18);
    }

    function test_WhitelistMinter() public {
        address[] memory minters = new address[](1);
        minters[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        vm.prank(notOwner);
        vm.expectRevert(CashWrappedERC20.OnlyFactory.selector);
        wweETH.whitelistMinters(minters, whitelists);

        vm.prank(address(tokenFactory));
        wweETH.whitelistMinters(minters, whitelists);

        assertEq(wweETH.isWhitelistedMinter(minters[0]), true);

        whitelists[0] = false;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, notOwner));
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);

        vm.prank(owner);
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);

        assertEq(wweETH.isWhitelistedMinter(minters[0]), false);
    }
    
    function test_WhitelistRecipient() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        vm.prank(notOwner);
        vm.expectRevert(CashWrappedERC20.OnlyFactory.selector);
        wweETH.whitelistRecipients(recipients, whitelists);

        vm.prank(address(tokenFactory));
        wweETH.whitelistRecipients(recipients, whitelists);

        assertEq(wweETH.isWhitelistedRecipient(recipients[0]), true);

        whitelists[0] = false;

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, notOwner));
        tokenFactory.whitelistRecipients(address(weETH), recipients, whitelists);

        vm.prank(owner);
        tokenFactory.whitelistRecipients(address(weETH), recipients, whitelists);

        assertEq(wweETH.isWhitelistedRecipient(recipients[0]), false);
    }

    function test_OnlyWhitelistedMintersCanMint() public {
        address[] memory minters = new address[](1);
        minters[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        assertEq(wweETH.isWhitelistedMinter(minters[0]), false);
        vm.prank(minters[0]);
        vm.expectRevert(CashWrappedERC20.OnlyWhitelistedMinter.selector);
        wweETH.mint(minters[0], 1);


        vm.startPrank(owner);
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);
        tokenFactory.whitelistRecipients(address(weETH), minters, whitelists);
        vm.stopPrank();

        uint256 amount = 10 ether;
        deal(address(weETH), minters[0], amount);

        assertEq(wweETH.balanceOf(minters[0]), 0);
        assertEq(weETH.balanceOf(minters[0]), amount);
        assertEq(weETH.balanceOf(address(wweETH)), 0);

        vm.startPrank(minters[0]);
        weETH.approve(address(wweETH), amount);
        wweETH.mint(minters[0], amount);
        vm.stopPrank();

        assertEq(wweETH.balanceOf(minters[0]), amount);
        assertEq(weETH.balanceOf(minters[0]), 0);
        assertEq(weETH.balanceOf(address(wweETH)), amount);
    }

    function test_OnlyWhitelistedRecipientCanReceiveWrappedToken() public {
        address[] memory minters = new address[](1);
        minters[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        vm.prank(owner);
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);

        uint256 amount = 10 ether;
        deal(address(weETH), minters[0], amount);

        vm.startPrank(minters[0]);
        weETH.approve(address(wweETH), amount);

        vm.expectRevert(CashWrappedERC20.NotAWhitelistedRecipient.selector);
        wweETH.mint(minters[0], amount);
        vm.stopPrank();

        vm.prank(owner);
        tokenFactory.whitelistRecipients(address(weETH), minters, whitelists);

        assertEq(wweETH.balanceOf(minters[0]), 0);
        assertEq(weETH.balanceOf(minters[0]), amount);
        assertEq(weETH.balanceOf(address(wweETH)), 0);

        vm.prank(minters[0]);
        wweETH.mint(minters[0], amount);

        assertEq(wweETH.balanceOf(minters[0]), amount);
        assertEq(weETH.balanceOf(minters[0]), 0);
        assertEq(weETH.balanceOf(address(wweETH)), amount);

        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient");

        vm.prank(minters[0]);
        vm.expectRevert(CashWrappedERC20.NotAWhitelistedRecipient.selector);    
        wweETH.transfer(recipients[0], amount);

        vm.prank(owner);
        tokenFactory.whitelistRecipients(address(weETH), recipients, whitelists);

        assertEq(wweETH.balanceOf(minters[0]), amount);
        assertEq(wweETH.balanceOf(recipients[0]), 0);

        vm.prank(minters[0]);
        wweETH.transfer(recipients[0], amount);

        assertEq(wweETH.balanceOf(minters[0]), 0);
        assertEq(wweETH.balanceOf(recipients[0]), amount);
    }

    function test_TransferWrappedERC20() public {
        address[] memory minters = new address[](1);
        minters[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        vm.startPrank(owner);
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);
        tokenFactory.whitelistRecipients(address(weETH), minters, whitelists);
        vm.stopPrank();

        uint256 amount = 10 ether;
        deal(address(weETH), minters[0], amount);

        vm.startPrank(minters[0]);
        weETH.approve(address(wweETH), amount);
        wweETH.mint(minters[0], amount);
        
        vm.expectRevert(CashWrappedERC20.NotAWhitelistedRecipient.selector);
        wweETH.transfer(owner, amount);
        vm.stopPrank();

        address[] memory newMinter = new address[](1);
        newMinter[0] = owner;
        vm.prank(owner);
        tokenFactory.whitelistRecipients(address(weETH), newMinter, whitelists);

        uint256 ownerBalBefore = wweETH.balanceOf(owner);
        uint256 minterBalBefore = wweETH.balanceOf(minters[0]);

        vm.prank(minters[0]);
        wweETH.transfer(owner, amount);

        uint256 ownerBalAfter = wweETH.balanceOf(owner);
        uint256 minterBalAfter = wweETH.balanceOf(minters[0]);

        assertEq(ownerBalAfter - ownerBalBefore, amount);
        assertEq(minterBalBefore - minterBalAfter, amount);
    }

    function test_TransferFromWrappedERC20() public {
        address[] memory minters = new address[](1);
        minters[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        vm.startPrank(owner);
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);
        tokenFactory.whitelistRecipients(address(weETH), minters, whitelists);
        vm.stopPrank();

        uint256 amount = 10 ether;
        deal(address(weETH), minters[0], amount);

        vm.startPrank(minters[0]);
        weETH.approve(address(wweETH), amount);
        wweETH.mint(minters[0], amount);
        wweETH.approve(owner, amount);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(CashWrappedERC20.NotAWhitelistedRecipient.selector);
        wweETH.transferFrom(minters[0], owner, amount);

        address[] memory newMinter = new address[](1);
        newMinter[0] = owner;
        tokenFactory.whitelistRecipients(address(weETH), newMinter, whitelists);
        
        uint256 ownerBalBefore = wweETH.balanceOf(owner);
        uint256 minterBalBefore = wweETH.balanceOf(minters[0]);
        wweETH.transferFrom(minters[0], owner, amount);

        uint256 ownerBalAfter = wweETH.balanceOf(owner);
        uint256 minterBalAfter = wweETH.balanceOf(minters[0]);

        assertEq(ownerBalAfter - ownerBalBefore, amount);
        assertEq(minterBalBefore - minterBalAfter, amount);
        vm.stopPrank();
    }

    function test_WithdrawWrappedToken() public {
        address[] memory minters = new address[](1);
        minters[0] = makeAddr("minter");
        bool[] memory whitelists = new bool[](1);
        whitelists[0] = true;

        vm.startPrank(owner);
        tokenFactory.whitelistMinters(address(weETH), minters, whitelists);
        tokenFactory.whitelistRecipients(address(weETH), minters, whitelists);
        vm.stopPrank();

        uint256 amount = 10 ether;
        deal(address(weETH), minters[0], amount);

        vm.startPrank(minters[0]);
        weETH.approve(address(wweETH), amount);
        wweETH.mint(minters[0], amount);
        vm.stopPrank();

        assertEq(wweETH.balanceOf(minters[0]), amount);
        assertEq(weETH.balanceOf(minters[0]), 0);
        assertEq(weETH.balanceOf(address(wweETH)), amount);

        vm.prank(minters[0]);
        wweETH.withdraw(minters[0], amount);

        assertEq(wweETH.balanceOf(minters[0]), 0);
        assertEq(weETH.balanceOf(minters[0]), amount);
        assertEq(weETH.balanceOf(address(wweETH)), 0);
    }
}
