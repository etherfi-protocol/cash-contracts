// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol"; 
import {TopUpSource, BridgeAdapterBase, PausableUpgradeable} from "../../src/top-up/TopUpSource.sol";
import {StargateAdapter} from "../../src/top-up/bridges/StargateAdapter.sol";
import {EtherFiOFTBridgeAdapter} from "../../src/top-up/bridges/EtherFiOFTBridgeAdapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TopUpSourceTest is Test {
    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    address alice = makeAddr("alice");
    address recoveryWallet = makeAddr("recoveryWallet");
    TopUpSource topUpSrc;
    EtherFiOFTBridgeAdapter oftBridgeAdapter;
    StargateAdapter stargateAdapter;

    uint96 maxSlippage = 100;

    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 weETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address weETHOftAddress = 0xcd2eb13D6831d4602D80E5db9230A57596CDCA63;
    address usdcStargatePool = 0xc026395860Db2d07ee33e05fE50ed7bD583189C7;

    function setUp() external {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");

        deal(owner, 100 ether);
        deal(alice, 100 ether);
        deal(address(usdc), alice, 100 ether);
        deal(address(weETH), alice, 100 ether);

        vm.startPrank(owner);
        stargateAdapter = new StargateAdapter();
        oftBridgeAdapter = new EtherFiOFTBridgeAdapter();

        address[] memory tokens = new address[](2);
        TopUpSource.TokenConfig[] memory tokenConfigs = new TopUpSource.TokenConfig[](2);
        
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(stargateAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(usdcStargatePool)
        });

        tokenConfigs[1] = TopUpSource.TokenConfig({
            bridgeAdapter: address(oftBridgeAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(weETHOftAddress)
        });

        address topUpSrcImpl = address(new TopUpSource());
        topUpSrc = TopUpSource(payable(address(
            new UUPSProxy(
                topUpSrcImpl,
                ""
            )
        ))); 

        vm.expectRevert(TopUpSource.DefaultAdminCannotBeZeroAddress.selector);
        topUpSrc.initialize(address(weth), address(0), recoveryWallet);
        
        vm.expectRevert(TopUpSource.RecoveryWalletCannotBeZeroAddress.selector);
        topUpSrc.initialize(address(weth), owner, address(0));

        topUpSrc.initialize(address(weth), owner, recoveryWallet);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);

        vm.stopPrank();
    }

    function test_Deploy() public view {
        assertEq(topUpSrc.hasRole(topUpSrc.DEFAULT_ADMIN_ROLE(), owner), true);
        assertEq(topUpSrc.hasRole(topUpSrc.BRIDGER_ROLE(), owner), true);
        assertEq(topUpSrc.hasRole(topUpSrc.PAUSER_ROLE(), owner), true);
        assertEq(topUpSrc.hasRole(topUpSrc.DEFAULT_ADMIN_ROLE(), notOwner), false);
        assertEq(topUpSrc.hasRole(topUpSrc.BRIDGER_ROLE(), notOwner), false);
        assertEq(topUpSrc.hasRole(topUpSrc.PAUSER_ROLE(), notOwner), false);
    }

    function test_EthConvertsToWeth() public {
        uint256 amount = 1 ether;
        vm.prank(alice);
        (bool success, ) = address(topUpSrc).call{value: amount}("");
        if (!success) revert("ETH Transfer failed");

        assertEq(weth.balanceOf(address(topUpSrc)), amount);
    }

    function test_CanSetTokenConfig() public {
        address[] memory tokens = new address[](2);
        TopUpSource.TokenConfig[] memory tokenConfigs = new TopUpSource.TokenConfig[](2);
        
        tokens[0] = address(usdc);
        tokens[1] = address(weETH);

        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(stargateAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(usdcStargatePool)
        });

        tokenConfigs[1] = TopUpSource.TokenConfig({
            bridgeAdapter: address(oftBridgeAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(weETHOftAddress)
        });

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.TokenConfigSet(tokens, tokenConfigs);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);

        assertEq(topUpSrc.tokenConfig(address(usdc)).bridgeAdapter, tokenConfigs[0].bridgeAdapter);
        assertEq(topUpSrc.tokenConfig(address(usdc)).recipientOnDestChain, tokenConfigs[0].recipientOnDestChain);
        assertEq(topUpSrc.tokenConfig(address(usdc)).maxSlippageInBps, tokenConfigs[0].maxSlippageInBps);
        assertEq(topUpSrc.tokenConfig(address(usdc)).additionalData, tokenConfigs[0].additionalData);

        assertEq(topUpSrc.tokenConfig(address(weETH)).bridgeAdapter, tokenConfigs[1].bridgeAdapter);
        assertEq(topUpSrc.tokenConfig(address(weETH)).recipientOnDestChain, tokenConfigs[1].recipientOnDestChain);
        assertEq(topUpSrc.tokenConfig(address(weETH)).maxSlippageInBps, tokenConfigs[1].maxSlippageInBps);
        assertEq(topUpSrc.tokenConfig(address(weETH)).additionalData, tokenConfigs[1].additionalData);
    }

    function test_OnlyOwnerCanSetTokenConfig() public {
        address[] memory tokens = new address[](1);
        TopUpSource.TokenConfig[] memory tokenConfigs = new TopUpSource.TokenConfig[](1);
        
        tokens[0] = address(usdc);
        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(stargateAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(usdcStargatePool)
        });

        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, topUpSrc.DEFAULT_ADMIN_ROLE()));
        topUpSrc.setTokenConfig(tokens, tokenConfigs);
        vm.stopPrank();
    }

    function test_CannotSetTokenConfigIfArrayLengthMismatch() public {
        address[] memory tokens = new address[](1);
        TopUpSource.TokenConfig[] memory tokenConfigs = new TopUpSource.TokenConfig[](2);

        vm.prank(owner);
        vm.expectRevert(TopUpSource.ArrayLengthMismatch.selector);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);
    }

    function test_CannotSetTokenConfigForNullToken() public {
        address[] memory tokens = new address[](1);
        TopUpSource.TokenConfig[] memory tokenConfigs = new TopUpSource.TokenConfig[](1);

        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(stargateAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(usdcStargatePool)
        });

        vm.prank(owner);
        vm.expectRevert(TopUpSource.TokenCannotBeZeroAddress.selector);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);
    }

    function test_CannotSetTokenConfigIfInvalidConfig() public {
        address[] memory tokens = new address[](1);
        TopUpSource.TokenConfig[] memory tokenConfigs = new TopUpSource.TokenConfig[](1);

        vm.startPrank(owner);
        tokens[0] = address(usdc);
        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(0),
            recipientOnDestChain: alice,
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(usdcStargatePool)
        });
        
        vm.expectRevert(TopUpSource.InvalidConfig.selector);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);
        
        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(stargateAdapter),
            recipientOnDestChain: address(0),
            maxSlippageInBps: maxSlippage,
            additionalData: abi.encode(usdcStargatePool)
        });
        
        vm.expectRevert(TopUpSource.InvalidConfig.selector);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);

        tokenConfigs[0] = TopUpSource.TokenConfig({
            bridgeAdapter: address(stargateAdapter),
            recipientOnDestChain: alice,
            maxSlippageInBps: topUpSrc.MAX_ALLOWED_SLIPPAGE() + 1,
            additionalData: abi.encode(usdcStargatePool)
        });
        vm.expectRevert(TopUpSource.InvalidConfig.selector);
        topUpSrc.setTokenConfig(tokens, tokenConfigs);
        
        vm.stopPrank();
    }

    function test_OnlyPauserCanPause() public {
        address pauser = makeAddr("pauser");
        vm.startPrank(owner);
        topUpSrc.grantRole(topUpSrc.PAUSER_ROLE(), pauser);
        vm.stopPrank();

        vm.startPrank(pauser);
        topUpSrc.pause();
        vm.stopPrank();
    }

    function test_OnlyDefaultAdminCanUnPause() public {
        address pauser = makeAddr("pauser");
        vm.startPrank(owner);
        topUpSrc.grantRole(topUpSrc.PAUSER_ROLE(), pauser);
        vm.stopPrank();

        vm.prank(pauser);
        topUpSrc.pause();

        vm.startPrank(pauser);
        vm.expectRevert(buildAccessControlRevertData(pauser, topUpSrc.DEFAULT_ADMIN_ROLE()));
        topUpSrc.unpause();
        vm.stopPrank();

        vm.startPrank(owner);
        topUpSrc.unpause();
        vm.stopPrank();
    }

    function test_CannotPauseIfAlreadyPaused() public {
        vm.startPrank(owner);
        topUpSrc.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        topUpSrc.pause();
        vm.stopPrank();
    }

    function test_CannotUnpauseIfNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        topUpSrc.unpause();
    }

    function test_BridgeUsdc() public {
        address token = address(usdc);
        uint256 amount = 100e6;
        deal(token, address(topUpSrc), amount);
        ( , uint256 fee) = topUpSrc.getBridgeFee(token);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.Bridge(token, amount);
        topUpSrc.bridge{value: fee}(token);
    }

    function test_BridgeWeETH() public {
        address token = address(weETH);
        uint256 amount = 1 ether;
        deal(token, address(topUpSrc), amount);
        ( , uint256 fee) = topUpSrc.getBridgeFee(token);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.Bridge(token, amount);
        topUpSrc.bridge{value: fee}(token);
    }

    function test_CannotBridgeIfInsufficientNativeFee() public {
        address token = address(usdc);
        uint256 amount = 100e6;
        deal(token, address(topUpSrc), amount);
        ( , uint256 fee) = topUpSrc.getBridgeFee(token);

        vm.prank(owner);
        vm.expectRevert();
        topUpSrc.bridge{value: fee - 1}(token);
    }

    function test_CannotBridgeIfTokenIsAddressZero() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpSource.TokenCannotBeZeroAddress.selector);
        topUpSrc.bridge(address(0));
        vm.stopPrank();
    }

    function test_CannotBridgeIfTokenConfigNotSet() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpSource.TokenConfigNotSet.selector);
        topUpSrc.bridge(address(weth));
        vm.stopPrank();
    }

    function test_CannotBridgeIfTokenBalanceIsZero() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpSource.ZeroBalance.selector);
        topUpSrc.bridge(address(usdc));
        vm.stopPrank();
    }

    function test_CannotBridgeWhenPaused() public {
        vm.startPrank(owner);
        topUpSrc.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        topUpSrc.bridge(address(usdc));
        vm.stopPrank();
    }

    function test_Recovery() public {
        uint256 amount = 1 ether;

        uint256 recoveryWalletBalBefore = 0;
        uint256 topUpSrcBalBefore = 100 ether;

        deal(address(usdc), recoveryWallet, recoveryWalletBalBefore);
        deal(address(usdc), address(topUpSrc), topUpSrcBalBefore);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.Recovery(recoveryWallet, address(usdc), amount);
        topUpSrc.recoverFunds(address(usdc), amount);

        uint256 recoveryWalletBalAfter = usdc.balanceOf(recoveryWallet);
        uint256 topUpSrcBalAfter = usdc.balanceOf(address(topUpSrc));

        assertEq(recoveryWalletBalAfter - recoveryWalletBalBefore, amount);
        assertEq(topUpSrcBalBefore - topUpSrcBalAfter, amount);
    }

    function test_OnlyDefaultAdminCanRecoverFunds() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, topUpSrc.DEFAULT_ADMIN_ROLE()));
        topUpSrc.recoverFunds(address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotRecoverIfTokenIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(TopUpSource.TokenCannotBeZeroAddress.selector);
        topUpSrc.recoverFunds(address(0), 1);
    }

    function test_CanSetRecoveryWallet() public {
        address newRecoveryWallet = makeAddr("newRecoveryWallet");
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.RecoveryWalletSet(recoveryWallet, newRecoveryWallet);
        topUpSrc.setRecoveryWallet(newRecoveryWallet);
        vm.stopPrank();

        assertEq(topUpSrc.recoveryWallet(), newRecoveryWallet);
    }

    function test_OnlyOwnerCanSetRecoveryWallet() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, topUpSrc.DEFAULT_ADMIN_ROLE()));
        topUpSrc.setRecoveryWallet(address(1));
        vm.stopPrank();
    }

    function test_CannotSetRecoveryWalletToAddressZero() public {
        vm.startPrank(owner);
        vm.expectRevert(TopUpSource.RecoveryWalletCannotBeZeroAddress.selector);
        topUpSrc.setRecoveryWallet(address(0));
        vm.stopPrank();
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