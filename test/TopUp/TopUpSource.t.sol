// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol"; 
import {TopUpSource, BridgeAdapterBase, PausableUpgradeable} from "../../src/top-up/TopUpSource.sol";
import {StargateAdapter} from "../../src/top-up/bridges/StargateAdapter.sol";
import {EtherFiOFTBridgeAdapter} from "../../src/top-up/bridges/EtherFiOFTBridgeAdapter.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

// keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
bytes32 constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

struct Permit {
    address owner;
    address spender;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
}

contract TopUpSourceTest is Test {
    using SafeERC20 for IERC20;

    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    address alice = makeAddr("alice");
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
        topUpSrc.initialize(address(weth), address(0));
        
        topUpSrc.initialize(address(weth), owner);
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

    function test_TopUpWithPermit() public {
        uint256 amount = 10 ether;
        uint256 deadline = type(uint256).max;
        bytes32 DOMAIN_SEPARATOR_WEETH = 0xe481930428c599d86cf3522b2e43b0e3006041a472f66cb41fa924ac01d3a22b;

        (address jake, uint256 jakePk) = makeAddrAndKey("jake");
        deal(address(weETH), address(jake), 100 ether);

        Permit memory permit = Permit({
            owner: jake,
            spender: address(topUpSrc),
            value: amount,
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = getTypedDataHash(DOMAIN_SEPARATOR_WEETH, permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(jakePk, digest);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.TopUpUser(address(jake), address(weETH), 1 ether);
        topUpSrc.approveAndTopUpWithPermit(
            jake,
            address(weETH),
            amount,
            deadline,
            r,
            s,
            v,
            1 ether
        );
        
    }

    function test_TopUpJustPermit() public {
        uint256 amount = 10 ether;
        uint256 deadline = type(uint256).max;
        bytes32 DOMAIN_SEPARATOR_WEETH = 0xe481930428c599d86cf3522b2e43b0e3006041a472f66cb41fa924ac01d3a22b;

        (address jake, uint256 jakePk) = makeAddrAndKey("jake");
        deal(address(weETH), address(jake), 100 ether);

        Permit memory permit = Permit({
            owner: jake,
            spender: address(topUpSrc),
            value: amount,
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = getTypedDataHash(DOMAIN_SEPARATOR_WEETH, permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(jakePk, digest);

        vm.prank(notOwner);
        topUpSrc.approveAndTopUpWithPermit(
            jake,
            address(weETH),
            amount,
            deadline,
            r,
            s,
            v,
            0
        );
        
        assertEq(weETH.allowance(jake, address(topUpSrc)), amount);
    }

    function test_TopUpWithAllowance() public {
        uint256 amount = 1 ether;
        deal(address(weETH), address(alice), 100 ether);

        vm.prank(alice);
        weETH.approve(address(topUpSrc), amount);
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TopUpSource.TopUpUser(address(alice), address(weETH), amount);
        topUpSrc.topUpUser(
            alice,
            address(weETH),
            amount
        );
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

    function getTypedDataHash(
        bytes32 DOMAIN_SEPARATOR,
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_permit)
                )
            );
    }

    // computes the hash of a permit
    function getStructHash(
        Permit memory _permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }
}