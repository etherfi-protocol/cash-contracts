// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {CashTokenWrapperFactory, CashWrappedERC20} from "../../src/cash-wrapper-token/CashTokenWrapperFactory.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

error OwnableUnauthorizedAccount(address account);

contract CashWrappedERC20V2 is CashWrappedERC20 { 
    function version() public pure returns (uint256) {
        return 2;
    }
}

contract CashWrappedTokenFactoryTest is Test {
    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");

    CashTokenWrapperFactory tokenFactory;
    CashWrappedERC20 impl;
    MockERC20 weETH;
    MockERC20 usdc;
    CashWrappedERC20 wweETH;
    CashWrappedERC20 wUsdc;

    function setUp() public {
        vm.startPrank(owner);
        weETH = new MockERC20("Wrapped eETH", "weETH", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        impl = new CashWrappedERC20();
        tokenFactory = new CashTokenWrapperFactory(address(impl), owner);
        wweETH = CashWrappedERC20(tokenFactory.deployWrapper(address(weETH)));
        wUsdc = CashWrappedERC20(tokenFactory.deployWrapper(address(usdc)));
        vm.stopPrank();
    }

    function test_DeployCashWrappedTokenFactory() public view {
        assertEq(wweETH.name(), "eCash Wrapped eETH");
        assertEq(wweETH.symbol(), "ecweETH");
        assertEq(wweETH.decimals(), weETH.decimals());

        assertEq(wUsdc.name(), "eCash USDC");
        assertEq(wUsdc.symbol(), "ecUSDC");
        assertEq(wUsdc.decimals(), usdc.decimals());
    }


    function test_Upgrade() public {
        CashWrappedERC20V2 implV2 = new CashWrappedERC20V2();

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, notOwner));
        tokenFactory.upgradeTo(address(implV2));
        
        vm.prank(owner);
        tokenFactory.upgradeTo(address(implV2));

        assertEq(CashWrappedERC20V2(address(wUsdc)).version(), 2);
        assertEq(CashWrappedERC20V2(address(wweETH)).version(), 2);
    }
}
