// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafeLib, SpendingLimit, SpendingLimitLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup, IUserSafe, UserSafeEventEmitter, CashbackDispatcher, MockPriceProvider} from "../Setup.t.sol";
import {ICashDataProvider} from "../../src/interfaces/ICashDataProvider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract CashbackDispatcherTest is Setup {
    using MessageHashUtils for bytes32;

    uint256 pepeCashbackPercentage = 200;
    uint256 wojakCashbackPercentage = 300;
    uint256 chadCashbackPercentage = 400;
    uint256 whaleCashbackPercentage = 500;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);

        if (!isFork(chainId)) MockPriceProvider(address(priceProvider)).setStableToken(address(scr));

        ICashDataProvider.UserSafeTiers[] memory userSafeTiers = new ICashDataProvider.UserSafeTiers[](4);
        userSafeTiers[0] = ICashDataProvider.UserSafeTiers.Pepe;
        userSafeTiers[1] = ICashDataProvider.UserSafeTiers.Wojak;
        userSafeTiers[2] = ICashDataProvider.UserSafeTiers.Chad;
        userSafeTiers[3] = ICashDataProvider.UserSafeTiers.Whale;

        uint256[] memory cashbackPercentages = new uint256[](4);
        cashbackPercentages[0] = pepeCashbackPercentage;
        cashbackPercentages[1] = wojakCashbackPercentage;
        cashbackPercentages[2] = chadCashbackPercentage;
        cashbackPercentages[3] = whaleCashbackPercentage;

        cashDataProvider.setTierCashbackPercentage(userSafeTiers, cashbackPercentages);

        vm.stopPrank();
    }

    function test_Deploy() public view {
        assertEq(address(cashbackDispatcher.cashDataProvider()), address(cashDataProvider));
        assertEq(address(cashbackDispatcher.priceProvider()), address(priceProvider));
        assertEq(cashbackDispatcher.cashbackToken(), address(scr));

        assertEq(uint8(cashDataProvider.getUserSafeTier(address(aliceSafe))), uint8(ICashDataProvider.UserSafeTiers.Pepe));
        assertEq(cashDataProvider.getTierCashbackPercentage(ICashDataProvider.UserSafeTiers.Pepe), pepeCashbackPercentage);
        assertEq(cashDataProvider.getTierCashbackPercentage(ICashDataProvider.UserSafeTiers.Wojak), wojakCashbackPercentage);
        assertEq(cashDataProvider.getTierCashbackPercentage(ICashDataProvider.UserSafeTiers.Chad), chadCashbackPercentage);
        assertEq(cashDataProvider.getTierCashbackPercentage(ICashDataProvider.UserSafeTiers.Whale), whaleCashbackPercentage);
    }

    function test_CashbackPaidDebitFlowPepe() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidCreditFlowPepe() public {
        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 10000e6);
        deal(address(usdc), address(debtManager), 10000e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidDebitFlowWojak() public {
        setTier(ICashDataProvider.UserSafeTiers.Wojak);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        uint256 cashbackInUsdc = (spendAmt * wojakCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidCreditFlowWojak() public {
        setTier(ICashDataProvider.UserSafeTiers.Wojak);

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 10000e6);
        deal(address(usdc), address(debtManager), 10000e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        uint256 cashbackInUsdc = (spendAmt * wojakCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidDebitFlowChad() public {
        setTier(ICashDataProvider.UserSafeTiers.Chad);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        uint256 cashbackInUsdc = (spendAmt * chadCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidCreditFlowChad() public {
        setTier(ICashDataProvider.UserSafeTiers.Chad);

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 10000e6);
        deal(address(usdc), address(debtManager), 10000e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        uint256 cashbackInUsdc = (spendAmt * chadCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidDebitFlowWhale() public {
        setTier(ICashDataProvider.UserSafeTiers.Whale);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        uint256 cashbackInUsdc = (spendAmt * whaleCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackPaidCreditFlowWhale() public {
        setTier(ICashDataProvider.UserSafeTiers.Whale);

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 10000e6);
        deal(address(usdc), address(debtManager), 10000e6);
        deal(address(scr), address(cashbackDispatcher), 100 ether);
        
        uint256 cashbackInUsdc = (spendAmt * whaleCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CashbackUnpaid() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);
        
        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafePendingCashbackBefore = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackBefore, 0);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertEq(aliceSafeScrBalAfter, aliceSafeScrBalBefore);

        uint256 aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, cashbackInUsdc);
    }

    function test_UnpaidCashbackIsAccumulatedInNextTx() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), spendAmt);
        
        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafePendingCashbackBefore = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackBefore, 0);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertEq(aliceSafeScrBalAfter, aliceSafeScrBalBefore);

        uint256 aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, cashbackInUsdc);

        deal(address(usdc), address(aliceSafe), spendAmt);
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(keccak256("newTxId"), address(usdc), spendAmt);

        aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, cashbackInUsdc * 2);
    }

    function test_UnpaidCashbackIsPaidIfBalAvailableInNextTx() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), spendAmt);
        
        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafePendingCashbackBefore = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackBefore, 0);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertEq(aliceSafeScrBalAfter, aliceSafeScrBalBefore);

        uint256 aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, cashbackInUsdc);

        deal(address(usdc), address(aliceSafe), spendAmt);
        deal(address(scr), address(cashbackDispatcher), 1000 ether);

        aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.PendingCashbackCleared(address(aliceSafe),address(scr), cashbackInScroll, cashbackInUsdc);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, true);
        aliceSafe.spend(keccak256("newTxId"), address(usdc), spendAmt);

        aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, 0);

        aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, 2 * cashbackInScroll, 1000);
    }

    function test_UnpaidCashbackIsPaidAndAccumulatesIfTotalBalNotAvailableInNextTx() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), spendAmt);
        
        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        uint256 aliceSafePendingCashbackBefore = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackBefore, 0);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertEq(aliceSafeScrBalAfter, aliceSafeScrBalBefore);

        uint256 aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, cashbackInUsdc);

        deal(address(usdc), address(aliceSafe), spendAmt);
        deal(address(scr), address(cashbackDispatcher), cashbackInScroll);

        aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.PendingCashbackCleared(address(aliceSafe),address(scr), cashbackInScroll, cashbackInUsdc);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(keccak256("newTxId"), address(usdc), spendAmt);

        aliceSafePendingCashbackAfter = aliceSafe.pendingCashback();
        assertEq(aliceSafePendingCashbackAfter, cashbackInUsdc);

        aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
    }

    function test_CanSetCashDataProvider() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CashbackDispatcher.CashDataProviderSet(address(cashDataProvider), address(1));
        cashbackDispatcher.setCashDataProvider(address(1));
    }

    function test_CannotSetAddressZeroAsCashDataProvider() public {
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.InvalidValue.selector);
        cashbackDispatcher.setCashDataProvider(address(0));
    }

    function test_OnlyOwnerCanSetCashDataProvider() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, cashbackDispatcher.ADMIN_ROLE()));
        cashbackDispatcher.setCashDataProvider(address(cashDataProvider));
        vm.stopPrank();
    }

    function test_CanSetPriceProvider() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CashbackDispatcher.PriceProviderSet(address(priceProvider), address(priceProvider));
        cashbackDispatcher.setPriceProvider(address(priceProvider));
    }

    function test_CannotSetAddressZeroAsPriceProvider() public {
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.InvalidValue.selector);
        cashbackDispatcher.setPriceProvider(address(0));
    }

    function test_OnlyOwnerCanSetPriceProvider() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, cashbackDispatcher.ADMIN_ROLE()));
        cashbackDispatcher.setPriceProvider(address(priceProvider));
        vm.stopPrank();
    }

    function test_CanSetCashbackToken() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CashbackDispatcher.CashbackTokenSet(address(scr), address(usdc));
        cashbackDispatcher.setCashbackToken(address(usdc));
    }

    function test_CannotSetAddressZeroAsCashbackToken() public {
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.InvalidValue.selector);
        cashbackDispatcher.setCashbackToken(address(0));
    }

    function test_OnlyOwnerCanSetCashbackToken() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, cashbackDispatcher.ADMIN_ROLE()));
        cashbackDispatcher.setCashbackToken(address(usdc));
        vm.stopPrank();
    }

    function test_WithdrawErc20Funds() public {
        deal(address(usdc), address(cashbackDispatcher), 1 ether);
        uint256 amount = 100e6;

        uint256 aliceBalBefore = usdc.balanceOf(alice);
        uint256 safeBalBefore = usdc.balanceOf(address(cashbackDispatcher));
        
        vm.prank(owner);
        cashbackDispatcher.withdrawFunds(address(usdc), alice, amount);

        uint256 aliceBalAfter = usdc.balanceOf(alice);
        uint256 safeBalAfter = usdc.balanceOf(address(cashbackDispatcher));

        assertEq(aliceBalAfter - aliceBalBefore, amount);
        assertEq(safeBalBefore - safeBalAfter, amount);

        // withdraw all
        vm.prank(owner);
        cashbackDispatcher.withdrawFunds(address(usdc), alice, 0);

        aliceBalAfter = usdc.balanceOf(alice);
        safeBalAfter = usdc.balanceOf(address(cashbackDispatcher));

        assertEq(aliceBalAfter - aliceBalBefore, safeBalBefore);
        assertEq(safeBalAfter, 0);
    }

    function test_WithdrawNativeFunds() public {
        deal(address(cashbackDispatcher), 1 ether);
        uint256 amount = 100e6;

        uint256 aliceBalBefore = alice.balance;
        uint256 safeBalBefore = address(cashbackDispatcher).balance;
        
        vm.prank(owner);
        cashbackDispatcher.withdrawFunds(address(0), alice, amount);

        uint256 aliceBalAfter = alice.balance;
        uint256 safeBalAfter = address(cashbackDispatcher).balance;

        assertEq(aliceBalAfter - aliceBalBefore, amount);
        assertEq(safeBalBefore - safeBalAfter, amount);

        // withdraw all
        vm.prank(owner);
        cashbackDispatcher.withdrawFunds(address(0), alice, 0);

        aliceBalAfter = alice.balance;
        safeBalAfter = address(cashbackDispatcher).balance;

        assertEq(aliceBalAfter - aliceBalBefore, safeBalBefore);
        assertEq(safeBalAfter, 0);
    }

    function test_CannotWithdrawIfRecipientIsAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.InvalidValue.selector);
        cashbackDispatcher.withdrawFunds(address(usdc), address(0), 1);
    }

    function test_CannotWithdrawIfNoBalance() public {
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.CannotWithdrawZeroAmount.selector);
        cashbackDispatcher.withdrawFunds(address(usdc), alice, 0);
        
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.CannotWithdrawZeroAmount.selector);
        cashbackDispatcher.withdrawFunds(address(0), alice, 0);
    }

    function test_CannotWithdrawIfInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert();
        cashbackDispatcher.withdrawFunds(address(usdc), alice, 1);
        
        vm.prank(owner);
        vm.expectRevert(CashbackDispatcher.WithdrawFundsFailed.selector);
        cashbackDispatcher.withdrawFunds(address(0), alice, 1);
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

    function setTier(ICashDataProvider.UserSafeTiers tier) internal {
        address[] memory safes = new address[](1);
        safes[0] = address(aliceSafe);
        ICashDataProvider.UserSafeTiers[] memory tiers = new ICashDataProvider.UserSafeTiers[](1);
        tiers[0] = tier;

        vm.prank(etherFiWallet);
        cashDataProvider.setUserSafeTier(safes, tiers);
    }
}