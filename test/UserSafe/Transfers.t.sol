// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib, SpendingLimitLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC20, UserSafeSetup} from "./UserSafeSetup.t.sol";

contract UserSafeTransfersTest is UserSafeSetup {
    using MessageHashUtils for bytes32;

    uint256 aliceSafeUsdcBalanceBefore;
    uint256 aliceSafeWeETHBalanceBefore;
    function setUp() public override {
        super.setUp();

        aliceSafeUsdcBalanceBefore = 1 ether;
        aliceSafeWeETHBalanceBefore = 100 ether;

        deal(address(usdc), address(aliceSafe), aliceSafeUsdcBalanceBefore);
        deal(address(weETH), address(aliceSafe), aliceSafeWeETHBalanceBefore);
    }

    function test_TransferForSpendingToCashMultiSig() public {
        uint256 amount = 1000e6;

        uint256 multiSigUsdcBalBefore = usdc.balanceOf(settlementDispatcher);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.TransferForSpending(address(aliceSafe), address(usdc), amount);
        aliceSafe.transfer(address(usdc), amount);

        uint256 multiSigUsdcBalAfter = usdc.balanceOf(settlementDispatcher);

        assertEq(
            aliceSafeUsdcBalanceBefore - usdc.balanceOf(address(aliceSafe)),
            amount
        );
        assertEq(multiSigUsdcBalAfter - multiSigUsdcBalBefore, amount);
    }

    function test_CannotTransferForSpendingWhenBalanceIsInsufficient() public {
        uint256 amount = aliceSafeUsdcBalanceBefore + 1;
        vm.prank(alice);
        _updateSpendingLimit(amount, amount);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_OnlyCashWalletCanTransferForSpending() public {
        uint256 amount = 1000e6;
        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.transfer(address(usdc), amount);
    }

    function test_CannotTransferMoreThanSpendingLimit() public {
        uint256 amount = defaultDailySpendingLimit + 1;
        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.transfer(address(usdc), amount);
        
        // _updateSpendingLimit(1 ether, defaultMonthlySpendingLimit);

        // amount = defaultMonthlySpendingLimit + 1;
        // vm.prank(etherFiWallet);
        // vm.expectRevert(SpendingLimitLib.ExceededMonthlySpendingLimit.selector);
        // aliceSafe.transfer(address(usdc), amount);
    }

    function test_SwapAndTransferForSpending() public {
        uint256 inputAmountToSwap = 100e6;
        uint256 outputMinUsdcAmount = 90e6;
        uint256 amountUsdcToSend = 50e6;
        address usdt = chainConfig.usdt;

        address[] memory assets = new address[](1);

        if (isFork(chainId)) {
            deal(usdt, address(aliceSafe), 1 ether);
            assets[0] = usdt;
        } else assets[0] = address(weETH);

        swapper.approveAssets(assets);

        uint256 aliceSafeUsdtBalBefore = ERC20(assets[0]).balanceOf(address(aliceSafe));

        bytes memory swapData;
        if (isFork(chainId))
            swapData = getQuoteOpenOcean(
                chainId,
                address(swapper),
                address(aliceSafe),
                assets[0],
                address(usdc),
                inputAmountToSwap,
                ERC20(usdt).decimals()
            );

        uint256 cashMultiSigUsdcBalBefore = usdc.balanceOf(settlementDispatcher);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.SwapTransferForSpending(
            address(aliceSafe),
            assets[0],
            inputAmountToSwap,
            address(usdc),
            amountUsdcToSend
        );
        aliceSafe.swapAndTransfer(
            assets[0],
            address(usdc),
            inputAmountToSwap,
            outputMinUsdcAmount,
            0,
            amountUsdcToSend,
            swapData
        );

        uint256 cashMultiSigUsdcBalAfter = usdc.balanceOf(settlementDispatcher);

        assertEq(
            cashMultiSigUsdcBalAfter - cashMultiSigUsdcBalBefore,
            amountUsdcToSend
        );
        assertEq(
            aliceSafeUsdtBalBefore - ERC20(assets[0]).balanceOf(address(aliceSafe)),
            inputAmountToSwap
        );

        // test_CannotSwapWeEthToUsdcAndTransferIfAmountReceivedIsLess

        _updateSpendingLimit(100000e6, 100000e6);

        vm.warp(block.timestamp + delay + 1);
        uint256 newAmountUsdcToSend = 10000e6;
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.TransferAmountGreaterThanReceived.selector);
        aliceSafe.swapAndTransfer(
            assets[0],
            address(usdc),
            inputAmountToSwap,
            outputMinUsdcAmount,
            0,
            newAmountUsdcToSend,
            swapData
        );

        // test_CannotGoOverSpendingLimit
        _updateSpendingLimit(1000e6, 1000e6);

        vm.warp(block.timestamp + delay + 1);
        uint256 newInputAmt = 2000e6;
        newAmountUsdcToSend = aliceSafe.applicableSpendingLimit().dailyLimit + 1;
        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.swapAndTransfer(
            assets[0],
            address(usdc),
            newInputAmt,
            outputMinUsdcAmount,
            0,
            newAmountUsdcToSend,
            swapData
        );
    }

    function test_CannotSwapAndTransferIfBalanceIsInsufficient() public {
        uint256 inputAmountWeETHToSwap = aliceSafeWeETHBalanceBefore + 1 ether;
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.swapAndTransfer(
            address(weETH),
            address(usdc),
            inputAmountWeETHToSwap,
            0,
            0,
            0,
            hex""
        );
    }

    function test_AddCollateralToDebtManager() public {
        uint256 amount = 1 ether;

        (uint256 userCollateralBefore, ) = etherFiCashDebtManager.getUserCollateralForToken(
            address(aliceSafe),
            address(weETH)
        );

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.AddCollateralToDebtManager(address(aliceSafe), address(weETH), amount);
        aliceSafe.addCollateral(address(weETH), amount);

        (uint256 userCollateralAfter, ) = etherFiCashDebtManager.getUserCollateralForToken(
            address(aliceSafe), 
            address(weETH)
        );

        assertEq(
            aliceSafeWeETHBalanceBefore - weETH.balanceOf(address(aliceSafe)),
            amount
        );
        assertEq(
            userCollateralAfter - userCollateralBefore,
            amount
        );
    }

    function test_OnlyCashWalletCanTransferFundsForCollateral() public {
        uint256 amount = 1 ether;

        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.addCollateral(address(weETH), amount);
    }

    function test_CannotAddCollateralIfBalanceIsInsufficient() public {
        uint256 amount = aliceSafeWeETHBalanceBefore + 1;
        vm.prank(alice);
        _setCollateralLimit(amount);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.addCollateral(address(weETH), amount);
    }

    function test_CannotTransferUnsupportedTokensForSpending() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        uint256 amount = 1 ether;
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.transfer(unsupportedToken, amount);
    }

    function test_CannotTransferUnsupportedTokensForCollateral() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        uint256 amount = 1 ether;
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.addCollateral(unsupportedToken, amount);
    }

    function _updateSpendingLimit(uint256 dailyLimitInUsd, uint256 monthlyLimitInUsd) internal {
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.UPDATE_SPENDING_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                dailyLimitInUsd,
                monthlyLimitInUsd
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        aliceSafe.updateSpendingLimit(dailyLimitInUsd, monthlyLimitInUsd, signature);
    }

    function _setCollateralLimit(uint256 newCollateralLimit) internal {
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_COLLATERAL_LIMIT_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newCollateralLimit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.setCollateralLimit(newCollateralLimit, signature);
    }
}
