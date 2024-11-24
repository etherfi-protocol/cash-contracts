// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib, UserSafeStorage, SpendingLimit, SpendingLimitLib} from "../../src/user-safe/UserSafeCore.sol";
import {TimeLib} from "../../src/libraries/TimeLib.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup, MockPriceProvider, PriceProvider, UserSafeLens} from "../Setup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract UserSafeLensTest is Setup {
    using MessageHashUtils for bytes32;
    using Math for uint256;

    uint256 weETHCollateralBal = 1 ether;

    function setUp() public override {
        super.setUp();
        priceProvider = PriceProvider(address(new MockPriceProvider(mockWeETHPriceInUsd, address(usdc))));
        vm.prank(owner);
        cashDataProvider.setPriceProvider(address(priceProvider));

        deal(address(weETH), address(aliceSafe), weETHCollateralBal);
    }

    function test_Deploy() public view {
        UserSafeLens.UserSafeData memory data = userSafeLens.getUserSafeData(address(aliceSafe));
        uint256 collateralBalInUsd = weETHCollateralBal.mulDiv(mockWeETHPriceInUsd, 10 ** weETH.decimals());

        assertEq(data.collateralBalances.length, 1);
        assertEq(data.collateralBalances[0].token, address(weETH));
        assertEq(data.collateralBalances[0].amount, weETHCollateralBal);

        assertEq(data.borrows.length, 0);

        assertEq(data.withdrawalRequest.tokens.length, 0);
        assertEq(data.withdrawalRequest.amounts.length, 0);
        assertEq(data.withdrawalRequest.finalizeTime, 0);
        assertEq(data.withdrawalRequest.recipient, address(0));

        assertEq(data.totalCollateral, collateralBalInUsd);
        assertEq(data.totalBorrow, 0);        
        assertEq(data.maxBorrow, collateralBalInUsd.mulDiv(ltv, HUNDRED_PERCENT));

        assertEq(data.tokenPrices.length, 2);
        assertEq(data.tokenPrices[0].token, address(weETH));
        assertEq(data.tokenPrices[0].amount, priceProvider.price(address(weETH)));

        assertEq(data.tokenPrices[1].token, address(usdc));
        assertEq(data.tokenPrices[1].amount, priceProvider.price(address(usdc)));
    }

    function test_CanGetUserDataWithWithdrawals() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.5 ether;

        address recipient = notOwner;

        uint256 finalizeTime = block.timestamp + cashDataProvider.delay();
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

        UserSafeLens.UserSafeData memory data = userSafeLens.getUserSafeData(address(aliceSafe));

        uint256 effectiveCollateralBal = weETHCollateralBal - amounts[0];
        uint256 collateralBalInUsd = effectiveCollateralBal.mulDiv(mockWeETHPriceInUsd, 10 ** weETH.decimals());
        
        assertEq(data.collateralBalances.length, 1);
        assertEq(data.collateralBalances[0].token, address(weETH));
        assertEq(data.collateralBalances[0].amount, effectiveCollateralBal);

        assertEq(data.borrows.length, 0);

        assertEq(data.withdrawalRequest.tokens.length, 1);
        assertEq(data.withdrawalRequest.tokens[0], address(weETH));
        assertEq(data.withdrawalRequest.amounts.length, 1);
        assertEq(data.withdrawalRequest.amounts[0], amounts[0]);
        assertEq(data.withdrawalRequest.finalizeTime, finalizeTime);
        assertEq(data.withdrawalRequest.recipient, recipient);

        assertEq(data.totalCollateral, collateralBalInUsd);
        assertEq(data.totalBorrow, 0);        
        assertEq(data.maxBorrow, collateralBalInUsd.mulDiv(ltv, HUNDRED_PERCENT));
    }
    
    function test_CanGetUserDataWithBorrows() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(weETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.5 ether;

        address recipient = notOwner;

        uint256 finalizeTime = block.timestamp + cashDataProvider.delay();
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

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        deal(address(usdc), address(debtManager), 1000e6);
        uint256 borrowAmt = 10e6;
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), borrowAmt);

        UserSafeLens.UserSafeData memory data = userSafeLens.getUserSafeData(address(aliceSafe));

        uint256 effectiveCollateralBal = weETHCollateralBal - amounts[0];
        uint256 collateralBalInUsd = effectiveCollateralBal.mulDiv(mockWeETHPriceInUsd, 10 ** weETH.decimals());
        
        assertEq(data.collateralBalances.length, 1);
        assertEq(data.collateralBalances[0].token, address(weETH));
        assertEq(data.collateralBalances[0].amount, effectiveCollateralBal);

        assertEq(data.borrows.length, 1);
        assertEq(data.borrows[0].token, address(usdc));
        assertEq(data.borrows[0].amount, borrowAmt);

        assertEq(data.withdrawalRequest.tokens.length, 1);
        assertEq(data.withdrawalRequest.tokens[0], address(weETH));
        assertEq(data.withdrawalRequest.amounts.length, 1);
        assertEq(data.withdrawalRequest.amounts[0], amounts[0]);
        assertEq(data.withdrawalRequest.finalizeTime, finalizeTime);
        assertEq(data.withdrawalRequest.recipient, recipient);

        assertEq(data.totalCollateral, collateralBalInUsd);
        assertEq(data.totalBorrow, borrowAmt);        
        assertEq(data.maxBorrow, collateralBalInUsd.mulDiv(ltv, HUNDRED_PERCENT));
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