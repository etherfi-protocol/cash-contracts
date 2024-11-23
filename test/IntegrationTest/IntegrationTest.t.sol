// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {Setup, PriceProvider, MockPriceProvider, MockERC20} from "../Setup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract IntegrationTest is Setup {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    IERC20 weth;
    uint256 collateralAmount = 0.01 ether;
    uint256 supplyAmount = 10e6;
    uint256 borrowAmount = 1e6;

    function setUp() public override {
        super.setUp();

        if (!isFork(chainId)) {
            /// If not mainnet, give some usdc to debt manager so it can provide debt
            vm.startPrank(owner);
            weth = IERC20(address(new MockERC20("WETH", "WETH", 18)));

            usdc.approve(address(debtManager), supplyAmount);
            debtManager.supply(
                address(owner),
                address(usdc),
                supplyAmount
            );
            vm.stopPrank();
        } else {
            vm.startPrank(owner);

            weth = IERC20(chainConfig.weth);

            priceProvider = PriceProvider(
                address(new MockPriceProvider(mockWeETHPriceInUsd, address(usdc)))
            );
            cashDataProvider.setPriceProvider(address(priceProvider));

            address newCollateralToken = address(weth);
            uint80 newLtv = 80e18;
            uint80 newLiquidationThreshold = 85e18;
            uint96 newLiquidationBonus = 8.5e18;

            IL2DebtManager.CollateralTokenConfig memory config = IL2DebtManager.CollateralTokenConfig({
                ltv: newLtv,
                liquidationThreshold: newLiquidationThreshold,
                liquidationBonus: newLiquidationBonus
            });

            debtManager.supportCollateralToken(
                newCollateralToken,
                config
            );

            deal(address(usdc), address(owner), supplyAmount);
            usdc.approve(address(debtManager), supplyAmount);
            debtManager.supply(address(owner), address(usdc), supplyAmount);
            vm.stopPrank();
        }

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
    }

    function test_MultipleSuppliers() public {
        vm.startPrank(owner);
        MockERC20 newCollateralToken = new MockERC20("CollToken", "CTK", 18);
        MockERC20 newBorrowToken = new MockERC20("DebtToken", "DTK", 18);

        uint80 newCollateralLtv = 80e18;
        uint80 newCollateralLiquidationThreshold = 85e18;
        uint96 newCollateralLiquidationBonus = 5e18;
        uint64 newBorrowTokenApy = 1e18;

        IL2DebtManager.CollateralTokenConfig memory config;
        config.ltv = newCollateralLtv;
        config.liquidationThreshold = newCollateralLiquidationThreshold;
        config.liquidationBonus = newCollateralLiquidationBonus;

        debtManager.supportCollateralToken(
            address(newCollateralToken),
            config
        );
        debtManager.supportCollateralToken(
            address(newBorrowToken),
            config
        );
        debtManager.supportBorrowToken(
            address(newBorrowToken),
            newBorrowTokenApy,
            1
        );
        
        MockPriceProvider(address(priceProvider)).setStableToken(address(newBorrowToken));

        vm.stopPrank();

        deal(address(newCollateralToken), address(aliceSafe), 1000 ether);
        deal(address(newBorrowToken), address(aliceSafe), 1000 ether);
        deal(address(newBorrowToken), address(alice), 1000 ether);
        deal(address(newBorrowToken), address(owner), 1000 ether);

        uint256 newBorrowTokenSupplyAmt = 1 ether;
        vm.startPrank(alice);
        newBorrowToken.approve(
            address(debtManager),
            newBorrowTokenSupplyAmt
        );
        debtManager.supply(
            alice,
            address(newBorrowToken),
            newBorrowTokenSupplyAmt
        );

        assertEq(
            debtManager.supplierBalance(
                alice,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt
        );

        IL2DebtManager.BorrowTokenConfig
            memory borrowTokenConfig = debtManager.borrowTokenConfig(
                address(newBorrowToken)
            );

        assertEq(
            borrowTokenConfig.totalSharesOfBorrowTokens,
            newBorrowTokenSupplyAmt
        );
        vm.stopPrank();

        vm.startPrank(owner);
        newBorrowToken.approve(
            address(debtManager),
            newBorrowTokenSupplyAmt
        );
        debtManager.supply(
            owner,
            address(newBorrowToken),
            newBorrowTokenSupplyAmt
        );

        assertEq(
            debtManager.supplierBalance(
                owner,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt
        );

        borrowTokenConfig = debtManager.borrowTokenConfig(
            address(newBorrowToken)
        );

        assertEq(
            borrowTokenConfig.totalSharesOfBorrowTokens,
            2 * newBorrowTokenSupplyAmt
        );
        vm.stopPrank();

        uint256 oneUsdWorthNewBorrowToken = 1e6;
        vm.prank(etherFiWallet);
        aliceSafe.spend(txId, address(newBorrowToken), oneUsdWorthNewBorrowToken);

        uint256 timeElapsed = 24 * 60 * 60;
        uint256 expectedInterest = 1 ether * ((newBorrowTokenApy * timeElapsed) / 1e20);
        
        vm.warp(block.timestamp + timeElapsed);

        assertEq(
            debtManager.borrowingOf(
                address(aliceSafe),
                address(newBorrowToken)
            ),
            ((1 ether + expectedInterest) * 1e6) /
                10 ** newBorrowToken.decimals()
        );

        vm.prank(etherFiWallet);
        aliceSafe.repay(address(newBorrowToken), 1 ether + expectedInterest);

        assertEq(
            debtManager.supplierBalance(
                alice,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt + expectedInterest / 2
        );
        assertEq(
            debtManager.supplierBalance(
                owner,
                address(newBorrowToken)
            ),
            newBorrowTokenSupplyAmt + expectedInterest / 2
        );
    }
}
