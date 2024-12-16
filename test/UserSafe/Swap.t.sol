// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP1271SignatureUtils} from "../../src/libraries/EIP1271SignatureUtils.sol";
import {Setup, ERC20, IL2DebtManager} from "../Setup.t.sol";
import {OwnerLib} from "../../src/libraries/OwnerLib.sol";

contract UserSafeSwapTest is Setup {
    using MessageHashUtils for bytes32;
    using OwnerLib for address;

    function test_Swap() public {
        if (!isFork(chainId)) return;

        ERC20 weth = ERC20(chainConfig.weth);
        uint256 inputAmountToSwap = 1 ether;
        uint256 outputMinWethAmount = 0.9 ether;

        address[] memory assets = new address[](1);
        deal(address(weETH), address(aliceSafe), 1 ether);
        assets[0] = address(weETH);

        swapper.approveAssets(assets);

        bytes memory swapData = getQuoteOpenOcean(
            chainId,
            address(swapper),
            address(aliceSafe),
            assets[0],
            address(weth),
            inputAmountToSwap,
            ERC20(assets[0]).decimals()
        );

        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SWAP_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                address(assets[0]),
                address(weth),
                inputAmountToSwap,
                outputMinWethAmount,
                0,
                swapData
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 aliceSafeWeETHBalBefore = ERC20(assets[0]).balanceOf(address(aliceSafe));
        uint256 aliceSafeWethBalBefore = weth.balanceOf(address(aliceSafe));
        assertEq(aliceSafeWeETHBalBefore, 1 ether);
        assertEq(aliceSafeWethBalBefore, 0);

        aliceSafe.swap(
            address(assets[0]),
            address(weth),
            inputAmountToSwap,
            outputMinWethAmount,
            0,
            swapData,
            signature
        );

        uint256 aliceSafeWeETHBalAfter = ERC20(assets[0]).balanceOf(address(aliceSafe));
        uint256 aliceSafeWethBalAfter = weth.balanceOf(address(aliceSafe));

        assertEq(aliceSafeWeETHBalAfter, 0);
        assertGt(aliceSafeWethBalAfter, outputMinWethAmount);
    }

    function test_CannotSwapIfBorrowPositionBecomesUnhealthy() external {
        if (!isFork(chainId)) return;
        uint256 collateralBal = 1 ether;
        deal(address(weETH), address(aliceSafe), collateralBal);
        deal(address(usdc), address(debtManager), 1000e6);

        _setMode(IUserSafe.Mode.Credit);
        vm.warp(aliceSafe.incomingCreditModeStartTime() + 1);

        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), 100e6);

        ERC20 weth = ERC20(chainConfig.weth);
        uint256 inputAmountToSwap = collateralBal;
        uint256 outputMinWethAmount = 0.9 ether;

        address[] memory assets = new address[](1);
        assets[0] = address(weETH);

        swapper.approveAssets(assets);

        bytes memory swapData = getQuoteOpenOcean(
            chainId,
            address(swapper),
            address(aliceSafe),
            assets[0],
            address(weth),
            inputAmountToSwap,
            ERC20(assets[0]).decimals()
        );

        uint256 nonce = aliceSafe.nonce() + 1;
        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.SWAP_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                address(assets[0]),
                address(weth),
                inputAmountToSwap,
                outputMinWethAmount,
                0,
                swapData
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            alicePk,
            msgHash.toEthSignedMessageHash()
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(IL2DebtManager.AccountUnhealthy.selector);
        aliceSafe.swap(
            address(assets[0]),
            address(weth),
            inputAmountToSwap,
            outputMinWethAmount,
            0,
            swapData,
            signature
        );
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