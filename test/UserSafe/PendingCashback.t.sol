// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib, SpendingLimitLib, UserSafeStorage} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup, ERC20, MockPriceProvider} from "../Setup.t.sol";
import {ICashDataProvider} from "../../src/interfaces/ICashDataProvider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract UserSafePendingCashbackTest is Setup {
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

    function test_CanGetPendingCashback() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);

        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        assertEq(aliceSafe.pendingCashback(), 0);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        assertEq(aliceSafe.pendingCashback(), cashbackInUsdc);
        assertEq(aliceSafe.totalCashbackEarnedInUsd(), cashbackInUsdc);
    }

    function test_RetrievePendingCashback() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);

        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        assertEq(aliceSafe.pendingCashback(), 0);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        assertEq(aliceSafe.pendingCashback(), cashbackInUsdc);
        assertEq(aliceSafe.totalCashbackEarnedInUsd(), cashbackInUsdc);

        deal(address(scr), address(cashbackDispatcher), cashbackInScroll);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.PendingCashbackCleared(address(aliceSafe), address(scr), cashbackInScroll, cashbackInUsdc);
        aliceSafe.retrievePendingCashback();
        
        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertApproxEqAbs(aliceSafeScrBalAfter - aliceSafeScrBalBefore, cashbackInScroll, 1000);
        assertEq(aliceSafe.totalCashbackEarnedInUsd(), cashbackInUsdc);
    }

    function test_RetrievePendingCashbackWhenNoPendingCashbackJustReturns() public {
        assertEq(aliceSafe.pendingCashback(), 0);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        aliceSafe.retrievePendingCashback();        
        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertEq(aliceSafeScrBalAfter, aliceSafeScrBalBefore);
    }

    function test_RetrievePendingCashbackWhenBalNotAvailableJustReturns() public {
        uint256 spendAmt = 100e6;
        deal(address(usdc), address(aliceSafe), 100e6);

        // alice is pepe, so cashback is 2% -> 2 USDC in scroll tokens
        uint256 cashbackInUsdc = (spendAmt * pepeCashbackPercentage) / HUNDRED_PERCENT_IN_BPS;
        uint256 cashbackInScroll = (cashbackInUsdc * 10 ** scr.decimals()) / priceProvider.price(address(scr));

        assertEq(aliceSafe.pendingCashback(), 0);

        vm.prank(etherFiWallet);
        vm.expectEmit(true, true, true, true);
        emit UserSafeEventEmitter.Cashback(address(aliceSafe), spendAmt, address(scr), cashbackInScroll, cashbackInUsdc, false);
        aliceSafe.spend(txId, address(usdc), spendAmt);

        assertEq(aliceSafe.pendingCashback(), cashbackInUsdc);

        uint256 aliceSafeScrBalBefore = scr.balanceOf(address(aliceSafe));
        aliceSafe.retrievePendingCashback();
        
        uint256 aliceSafeScrBalAfter = scr.balanceOf(address(aliceSafe));
        assertEq(aliceSafeScrBalAfter, aliceSafeScrBalBefore);
        assertEq(aliceSafe.pendingCashback(), cashbackInUsdc);
    }
}