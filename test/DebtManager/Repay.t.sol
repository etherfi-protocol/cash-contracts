// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup, ERC20} from "../Setup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IUserSafe, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";

contract DebtManagerRepayTest is Setup {
    using SafeERC20 for IERC20;
    using stdStorage for StdStorage;
    using MessageHashUtils for bytes32;

    uint256 collateralAmount = 0.01 ether;
    uint256 collateralValueInUsdc;
    uint256 borrowAmt;

    function setUp() public override {
        super.setUp();

        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SET_MODE_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                IUserSafe.Mode.Credit
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );

        bytes memory signature = abi.encodePacked(r, s, v);
        aliceSafe.setMode(IUserSafe.Mode.Credit, signature);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        deal(address(usdc), owner, 1 ether);
        deal(address(weETH), address(aliceSafe), collateralAmount);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);

        collateralValueInUsdc = debtManager.convertCollateralTokenToUsd(
            address(weETH),
            collateralAmount
        );

        deal(address(weETH), address(aliceSafe), collateralAmount);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);

        vm.startPrank(etherFiWallet);
        borrowAmt = debtManager.remainingBorrowingCapacityInUSD(address(aliceSafe)) / 2;
        aliceSafe.spend(txId, address(usdc), borrowAmt);
        vm.stopPrank();
    }

    function test_RepayWithUsdc() public {
        uint256 debtAmtBefore = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertGt(debtAmtBefore, 0);

        uint256 repayAmt = debtAmtBefore;
        deal(address(usdc), address(aliceSafe), repayAmt);
        vm.startPrank(etherFiWallet);
        aliceSafe.repay(address(usdc), repayAmt);
        vm.stopPrank();

        uint256 debtAmtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertEq(debtAmtBefore - debtAmtAfter, repayAmt);
    }

    function test_CannotRepayWithNonBorrowToken() public {
        vm.startPrank(etherFiWallet);
        vm.expectRevert(IUserSafe.OnlyBorrowToken.selector);
        aliceSafe.repay(address(weETH), 1 ether);
        vm.stopPrank();
    }

    function test_SwapAndRepay() public {
        if (!isFork(chainId)) return;
        uint256 debtAmtBefore = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertGt(debtAmtBefore, 0);

        uint256 repayAmt = debtAmtBefore;
        
        address usdt = chainConfig.usdt;
        address inputToken = usdt;
        uint256 inputAmountToSwap = 100e6;
        uint256 outputMinUsdcAmount = 90e6;
        uint256 amountUsdcToRepay = repayAmt;
        deal(usdt, address(aliceSafe), inputAmountToSwap);

        bytes memory swapData = getQuoteOpenOcean(
            chainId,
            address(swapper),
            address(aliceSafe),
            inputToken,
            address(usdc),
            inputAmountToSwap,
            ERC20(usdt).decimals()
        );

        vm.prank(etherFiWallet);
        aliceSafe.swapAndRepay(
            inputToken,
            address(usdc),
            inputAmountToSwap,
            outputMinUsdcAmount,
            0,
            amountUsdcToRepay,
            swapData
        );

        uint256 debtAmtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertEq(debtAmtAfter, 0);
    }

    function test_RepayAfterSomeTimeIncursInterestOnTheBorrowings() public {
        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        uint256 debtAmtBefore = borrowAmt + expectedInterest;

        assertEq(debtManager.borrowingOf(address(aliceSafe), address(usdc)), debtAmtBefore);
        uint256 repayAmt = debtAmtBefore;
        deal(address(usdc), address(aliceSafe), repayAmt);
        vm.prank(etherFiWallet);
        aliceSafe.repay(address(usdc), repayAmt);
        
        uint256 debtAmtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertEq(debtAmtBefore - debtAmtAfter, repayAmt);
    }

    function test_CannotRepayWithUsdcIfBalanceIsInsufficient() public {
        deal(address(usdc), address(aliceSafe), 0);

        vm.startPrank(etherFiWallet);
        if (!isFork(chainId))
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    address(aliceSafe),
                    0,
                    1
                )
            );
        else vm.expectRevert(IUserSafe.InsufficientBalance.selector);
        aliceSafe.repay(address(usdc), 1);
        vm.stopPrank();
    }

    function test_CanRepayForOtherUser() public {
        uint256 debtAmtBefore = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertGt(debtAmtBefore, 0);

        uint256 repayAmt = debtAmtBefore;

        vm.startPrank(notOwner);
        deal(address(usdc), notOwner, repayAmt);
        IERC20(address(usdc)).forceApprove(address(debtManager), repayAmt);
        debtManager.repay(address(aliceSafe), address(usdc), repayAmt);
        vm.stopPrank();

        uint256 debtAmtAfter = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertEq(debtAmtBefore - debtAmtAfter, repayAmt);
    }
}
