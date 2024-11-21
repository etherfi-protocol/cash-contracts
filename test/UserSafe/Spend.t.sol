// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib, SpendingLimitLib, UserSafeStorage} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup, ERC20} from "../Setup.t.sol";

contract UserSafeSpendTest is Setup {
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

    function test_SpendWithDebitFlow() public {
        uint256 amount = 1000e6;

        uint256 settlementDispatcherUsdcBalBefore = usdc.balanceOf(settlementDispatcher);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Spend(address(aliceSafe), address(usdc), amount, UserSafeStorage.Mode.Debit);
        aliceSafe.spend(address(usdc), amount);

        uint256 settlementDispatcherUsdcBalAfter = usdc.balanceOf(settlementDispatcher);

        assertEq(
            aliceSafeUsdcBalanceBefore - usdc.balanceOf(address(aliceSafe)),
            amount
        );
        assertEq(settlementDispatcherUsdcBalAfter - settlementDispatcherUsdcBalBefore, amount);
    }

    function test_CanSpendWithDebitFlowIfBorrowIsWithinLimits() public {
        uint256 weETHCollateralAmount = 1 ether;
        uint256 usdcCollateralAmount = 1000e6;
        deal(address(weETH), address(aliceSafe), weETHCollateralAmount);
        deal(address(usdc), address(aliceSafe), usdcCollateralAmount);
        deal(address(usdc), address(debtManager), 1 ether); 

        uint256 totalMaxBorrow = debtManager.getMaxBorrowAmount(address(aliceSafe), true);
        uint256 spendDebitAmount = 10e6;
        uint256 borrowAmt = totalMaxBorrow - spendDebitAmount;

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);

        _setMode(IUserSafe.Mode.Debit);

        uint256 settlementDispatcherUsdcBalBefore = usdc.balanceOf(settlementDispatcher);

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), spendDebitAmount);
        
        uint256 settlementDispatcherUsdcBalAfter = usdc.balanceOf(settlementDispatcher);

        assertEq(settlementDispatcherUsdcBalAfter - settlementDispatcherUsdcBalBefore, spendDebitAmount);
    }

    function test_CannotSpendWithDebitModeWhenBorrowIsOverLimitAfterSpend() public {
        uint256 weETHCollateralAmount = 1 ether;
        uint256 usdcCollateralAmount = 1000e6;
        deal(address(weETH), address(aliceSafe), weETHCollateralAmount);
        deal(address(usdc), address(aliceSafe), usdcCollateralAmount);
        deal(address(usdc), address(debtManager), 1 ether); 

        uint256 totalMaxBorrow = debtManager.getMaxBorrowAmount(address(aliceSafe), true);
        uint256 spendDebitAmount = 10e6;
        uint256 borrowAmt = totalMaxBorrow;

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);

        _setMode(IUserSafe.Mode.Debit);

        vm.prank(etherFiWallet);
        vm.expectRevert("Borrowings greater than max borrow after spending");
        aliceSafe.spend(address(usdc), spendDebitAmount);
    }

    function test_CanSpendWithDebitModeEvenIfWithdrawalsBlockTheAmount() external {
        uint256 weETHCollateralAmount = 1 ether;
        uint256 usdcCollateralAmount = 1000e6;
        deal(address(weETH), address(aliceSafe), weETHCollateralAmount);
        deal(address(usdc), address(aliceSafe), usdcCollateralAmount);
        deal(address(usdc), address(debtManager), 1 ether); 
        
        uint256 totalMaxBorrow = debtManager.getMaxBorrowAmount(address(aliceSafe), true);
        uint256 spendDebitAmount = 10e6;
        uint256 borrowAmt = totalMaxBorrow - spendDebitAmount;

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);

        _setMode(IUserSafe.Mode.Debit);
        uint256 maxCanSpendBeforeWithdrawal = aliceSafe.maxCanSpend(address(usdc));

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e6;

        address recipient = notOwner;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                tokens,
                amounts,
                recipient
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);

        uint256 settlementDispatcherUsdcBalBefore = usdc.balanceOf(settlementDispatcher);
        uint256 aliceSafeUsdcBalBefore = usdc.balanceOf(address(aliceSafe));
        
        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), maxCanSpendBeforeWithdrawal);

        uint256 settlementDispatcherUsdcBalAfter = usdc.balanceOf(settlementDispatcher);
        uint256 aliceSafeUsdcBalAfter = usdc.balanceOf(address(aliceSafe));
        assertEq(
            aliceSafeUsdcBalBefore - aliceSafeUsdcBalAfter,
            maxCanSpendBeforeWithdrawal
        );
        assertEq(settlementDispatcherUsdcBalAfter - settlementDispatcherUsdcBalBefore, maxCanSpendBeforeWithdrawal);

        uint256 withdrawalAmt = aliceSafe.getPendingWithdrawalAmount(address(usdc));
        assertEq(withdrawalAmt, 0);
    }

    function test_CanSpendWithCreditModeEvenIfWithdrawalBlocksTheAmount() public {
        uint256 weETHCollateralAmount = 1 ether;
        uint256 usdcCollateralAmount = 1000e6;
        deal(address(weETH), address(aliceSafe), weETHCollateralAmount);
        deal(address(usdc), address(aliceSafe), usdcCollateralAmount);
        deal(address(usdc), address(debtManager), 1 ether); 
        
        uint256 totalMaxBorrow = debtManager.getMaxBorrowAmount(address(aliceSafe), true);
        uint256 futureBorrowAmt = 10e6;
        uint256 borrowAmt = totalMaxBorrow - futureBorrowAmt;

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), borrowAmt);
        
        uint256 maxCanWithdraw = 10e6;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = maxCanWithdraw;

        address recipient = notOwner;
        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.REQUEST_WITHDRAWAL_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                tokens,
                amounts,
                recipient
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.requestWithdrawal(tokens, amounts, recipient, signature);

        uint256 settlementDispatcherUsdcBalBefore = usdc.balanceOf(settlementDispatcher);

        vm.prank(etherFiWallet);
        aliceSafe.spend(address(usdc), futureBorrowAmt);

        uint256 settlementDispatcherUsdcBalAfter = usdc.balanceOf(settlementDispatcher);

        assertEq(settlementDispatcherUsdcBalAfter - settlementDispatcherUsdcBalBefore, futureBorrowAmt);

        uint256 withdrawalAmt = aliceSafe.getPendingWithdrawalAmount(address(usdc));
        assertEq(withdrawalAmt, 0);
    }

    function test_CannotSpendWithDebitFlowWhenBalanceIsInsufficient() public {
        uint256 amount = aliceSafeUsdcBalanceBefore + 1;
        vm.prank(alice);
        _updateSpendingLimit(amount, amount);

        vm.warp(block.timestamp + delay + 1);
        vm.prank(etherFiWallet);
        vm.expectRevert("Insufficient balance to spend with Debit flow");
        aliceSafe.spend(address(usdc), amount);
    }

    function test_OnlyCashWalletCanSpendWithDebitFlow() public {
        uint256 amount = 1000e6;
        vm.prank(notOwner);
        vm.expectRevert(IUserSafe.UnauthorizedCall.selector);
        aliceSafe.spend(address(usdc), amount);
    }

    function test_CannotSpendWithDebitFlowMoreThanSpendingLimit() public {
        uint256 amount = defaultDailySpendingLimit + 1;
        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.spend(address(usdc), amount);
        
        // _updateSpendingLimit(1 ether, defaultMonthlySpendingLimit);

        // amount = defaultMonthlySpendingLimit + 1;
        // vm.prank(etherFiWallet);
        // vm.expectRevert(SpendingLimitLib.ExceededMonthlySpendingLimit.selector);
        // aliceSafe.spend(address(usdc), amount);
    }

    function test_SwapAndSpend() public {
        uint256 inputAmountToSwap = 100e6;
        uint256 outputMinUsdcAmount = 90e6;
        uint256 amountUsdcToSend = 50e6;
        address usdt = chainConfig.usdt;

        address[] memory assets = new address[](1);

        if (isFork(chainId)) {
            deal(usdt, address(aliceSafe), 1 ether);
            assets[0] = usdt;
            swapper.approveAssets(assets);
        } else assets[0] = address(weETH);

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

        uint256 settlementDispatcherUsdcBalBefore = usdc.balanceOf(settlementDispatcher);

        vm.prank(etherFiWallet);
        aliceSafe.swapAndSpend(
            assets[0],
            address(usdc),
            inputAmountToSwap,
            outputMinUsdcAmount,
            0,
            amountUsdcToSend,
            swapData
        );

        uint256 settlementDispatcherUsdcBalAfter = usdc.balanceOf(settlementDispatcher);

        assertEq(
            settlementDispatcherUsdcBalAfter - settlementDispatcherUsdcBalBefore,
            amountUsdcToSend
        );
        assertEq(
            aliceSafeUsdtBalBefore - ERC20(assets[0]).balanceOf(address(aliceSafe)),
            inputAmountToSwap
        );

        // test_CannotGoOverSpendingLimit
        _updateSpendingLimit(1000e6, 1000e6);

        vm.warp(block.timestamp + delay + 1);
        uint256 newInputAmt = 2000e6;
        uint256 newAmountUsdcToSend = aliceSafe.applicableSpendingLimit().dailyLimit + 1;
        vm.prank(etherFiWallet);
        vm.expectRevert(SpendingLimitLib.ExceededDailySpendingLimit.selector);
        aliceSafe.swapAndSpend(
            assets[0],
            address(usdc),
            newInputAmt,
            outputMinUsdcAmount,
            0,
            newAmountUsdcToSend,
            swapData
        );
    }

    function test_CannotSwapAndSpendIfBalanceIsInsufficient() public {
        uint256 inputAmountWeETHToSwap = aliceSafeWeETHBalanceBefore + 1 ether;
        vm.prank(etherFiWallet);
        vm.expectRevert();
        aliceSafe.swapAndSpend(
            address(weETH),
            address(usdc),
            inputAmountWeETHToSwap,
            0,
            0,
            0,
            hex""
        );
    }

    function test_CannotSpendIfUnsupportedTokensForSpending() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        uint256 amount = 1 ether;
        vm.prank(etherFiWallet);
        vm.expectRevert(IUserSafe.UnsupportedToken.selector);
        aliceSafe.spend(unsupportedToken, amount);
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

    function _setMode(IUserSafe.Mode mode) internal {
        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_MODE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                mode
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.setMode(mode, signature);
    }
}
