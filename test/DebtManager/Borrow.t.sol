// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup, MockERC20, UserSafeLib, IUserSafe, PriceProvider, MockPriceProvider, IAggregatorV3} from "../Setup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract DebtManagerBorrowTest is Setup {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    uint256 collateralAmount = 0.01 ether;
    uint256 collateralValueInUsdc;

    function setUp() public override {
        super.setUp();

        collateralValueInUsdc = debtManager.convertCollateralTokenToUsd(
            address(weETH),
            collateralAmount
        );

        deal(address(weETH), address(aliceSafe), collateralAmount);
        // so that debt manager has funds for borrowings
        deal(address(usdc), address(debtManager), 1 ether);

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

    function test_CanAddOrRemoveSupportedBorrowTokens() public {
        address newBorrowToken = address(new MockERC20("abc", "ABC", 12));
        uint64 borrowApy = 1e18;
        uint128 _minShares = 1e12;

        vm.startPrank(owner);
        if (isFork(chainId)) {
            address[] memory _tokens = new address[](1);
            _tokens[0] = address(newBorrowToken);
            
            PriceProvider.Config[] memory _configs = new PriceProvider.Config[](1); 
            _configs[0] = PriceProvider.Config({
                oracle: usdcUsdOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(usdcUsdOracle).decimals(),
                maxStaleness: 1 days,
                dataType: PriceProvider.ReturnType.Int256,
                isBaseTokenEth: false,
                isStableToken: true
            });
            priceProvider.setTokenConfig(_tokens, _configs);
        }

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = ltv;
        collateralTokenConfig.liquidationThreshold = liquidationThreshold;
        collateralTokenConfig.liquidationBonus = liquidationBonus;
        debtManager.supportCollateralToken(
            address(newBorrowToken),
            collateralTokenConfig
        );

        debtManager.supportBorrowToken(newBorrowToken, borrowApy, _minShares);

        assertEq(debtManager.borrowApyPerSecond(newBorrowToken), borrowApy);

        assertEq(debtManager.getBorrowTokens().length, 2);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));
        assertEq(debtManager.getBorrowTokens()[1], newBorrowToken);

        debtManager.unsupportBorrowToken(newBorrowToken);
        assertEq(debtManager.getBorrowTokens().length, 1);
        assertEq(debtManager.getBorrowTokens()[0], address(usdc));

        vm.stopPrank();
    }

    function test_CannotRemoveSupportIfBorrowTokenIsStillInTheSystem() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.BorrowTokenStillInTheSystem.selector);
        debtManager.unsupportBorrowToken(address(usdc));

        vm.stopPrank();
    }

    function test_OnlyAdminCanSupportOrUnsupportBorrowTokens() public {
        address newBorrowToken = address(new MockERC20("abc", "ABC", 12));

        vm.startPrank(alice);
        vm.expectRevert(
            buildAccessControlRevertData(alice, ADMIN_ROLE)
        );
        debtManager.supportBorrowToken(newBorrowToken, 1, 1);
        vm.expectRevert(
            buildAccessControlRevertData(alice, ADMIN_ROLE)
        );
        debtManager.unsupportBorrowToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotAddBorrowTokenIfAlreadySupported() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.AlreadyBorrowToken.selector);
        debtManager.supportBorrowToken(address(usdc), 1, 1);
        vm.stopPrank();
    }

    function test_CannotUnsupportTokenForBorrowIfItIsNotABorrowTokenAlready()
        public
    {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NotABorrowToken.selector);
        debtManager.unsupportBorrowToken(address(weETH));
        vm.stopPrank();
    }

    function test_CannotUnsupportAllTokensAsBorrowTokens() public {
        deal(address(usdc), address(debtManager), 0);
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.NoBorrowTokenLeft.selector);
        debtManager.unsupportBorrowToken(address(usdc));
        vm.stopPrank();
    }

    function test_CanSetBorrowApy() public {
        uint64 apy = 1;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.BorrowApySet(address(usdc), borrowApyPerSecond, apy);
        debtManager.setBorrowApy(address(usdc), apy);

        IL2DebtManager.BorrowTokenConfig memory config = debtManager.borrowTokenConfig(address(usdc));
        assertEq(config.borrowApy, apy);
        vm.stopPrank();
    }

    function test_OnlyAdminCanSetBorrowApy() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setBorrowApy(address(usdc), 1);
        vm.stopPrank();
    }

    function test_BorrowApyCannotBeZero() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.setBorrowApy(address(usdc), 0);
        vm.stopPrank();
    }

    function test_CannotSetBorrowApyForUnsupportedToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.setBorrowApy(address(weETH), 1);
        vm.stopPrank();
    }

    function test_CanSetMinBorrowTokenShares() public {
        uint128 shares = 100;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.MinSharesOfBorrowTokenSet(address(usdc), minShares, shares);
        debtManager.setMinBorrowTokenShares(address(usdc), shares);

        IL2DebtManager.BorrowTokenConfig memory config = debtManager.borrowTokenConfig(address(usdc));
        assertEq(config.minShares, shares);
    }

    function test_OnlyAdminCanSetBorrowTokenMinShares() public {
        vm.startPrank(notOwner);
        vm.expectRevert(buildAccessControlRevertData(notOwner, ADMIN_ROLE));
        debtManager.setMinBorrowTokenShares(address(usdc), 1);
        vm.stopPrank();
    }


    function test_BorrowTokenMinSharesCannotBeZero() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.InvalidValue.selector);
        debtManager.setMinBorrowTokenShares(address(usdc), 0);
        vm.stopPrank();
    }

    function test_CannotSetBorrowTokenMinSharesForUnsupportedToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.setMinBorrowTokenShares(address(weETH), 1);
        vm.stopPrank();
    }

    function test_Borrow() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSD(address(aliceSafe));
        uint256 borrowAmt = totalCanBorrow / 2;

        (, uint256 totalBorrowingAmountBefore) = debtManager.totalBorrowingAmounts();
        assertEq(totalBorrowingAmountBefore, 0);

        bool isUserLiquidatableBefore = debtManager.liquidatable(address(aliceSafe));
        assertEq(isUserLiquidatableBefore, false);

        (, uint256 borrowingOfUserBefore) = debtManager.borrowingOf(address(aliceSafe));
        assertEq(borrowingOfUserBefore, 0);

        vm.startPrank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), borrowAmt);
        vm.stopPrank();

        uint256 borrowInUsdc = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        assertEq(borrowInUsdc, borrowAmt);

        (, uint256 totalBorrowingAmountAfter) = debtManager
            .totalBorrowingAmounts();
        assertEq(totalBorrowingAmountAfter, borrowAmt);

        bool isUserLiquidatableAfter = debtManager.liquidatable(address(aliceSafe));
        assertEq(isUserLiquidatableAfter, false);

        (, uint256 borrowingOfUserAfter) = debtManager.borrowingOf(address(aliceSafe));
        assertEq(borrowingOfUserAfter, borrowAmt);
    }

    function test_BorrowIncursInterestWithTime() public {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(
            address(aliceSafe)
        ) / 2;

        vm.startPrank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), borrowAmt);
        vm.stopPrank();

        assertEq(debtManager.borrowingOf(address(aliceSafe), address(usdc)), borrowAmt);

        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        assertEq(
            debtManager.borrowingOf(address(aliceSafe), address(usdc)),
            borrowAmt + expectedInterest
        );
    }

    function test_BorrowTokenWithDecimalsOtherThanSix() public {
        MockERC20 newToken = new MockERC20("mockToken", "MTK", 12);
        deal(address(newToken), address(debtManager), 1 ether);
        uint64 borrowApy = 1e18;

        vm.startPrank(owner);
        if (isFork(chainId)) {
            address[] memory _tokens = new address[](1);
            _tokens[0] = address(newToken);

            PriceProvider.Config[] memory _configs = new PriceProvider.Config[](1); 
            _configs[0] = PriceProvider.Config({
                oracle: usdcUsdOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(usdcUsdOracle).decimals(),
                maxStaleness: 1 days,
                dataType: PriceProvider.ReturnType.Int256,
                isBaseTokenEth: false,
                isStableToken: true
            });
            priceProvider.setTokenConfig(_tokens, _configs);
        } else MockPriceProvider(address(priceProvider)).setStableToken(address(newToken));

        IL2DebtManager.CollateralTokenConfig memory collateralTokenConfig;
        collateralTokenConfig.ltv = ltv;
        collateralTokenConfig.liquidationThreshold = liquidationThreshold;
        collateralTokenConfig.liquidationBonus = liquidationBonus;
        debtManager.supportCollateralToken(
            address(newToken),
            collateralTokenConfig
        );
        debtManager.supportBorrowToken(address(newToken), borrowApy, 1);

        vm.stopPrank();

        uint256 remainingBorrowCapacityInUsdc = debtManager.remainingBorrowingCapacityInUSD(address(aliceSafe));
        (, uint256 totalBorrowingsOfAliceSafe) = debtManager.borrowingOf(address(aliceSafe));
        assertEq(totalBorrowingsOfAliceSafe, 0);

        uint256 borrowInToken = (remainingBorrowCapacityInUsdc * 1e12) / 1e6;
        uint256 debtManagerBalBefore = newToken.balanceOf(address(debtManager));

        vm.prank(etherFiWallet);
        aliceSafe.spend(
            txId,
            address(newToken),
            remainingBorrowCapacityInUsdc
        );

        (, totalBorrowingsOfAliceSafe) = debtManager.borrowingOf(address(aliceSafe));
        assertEq(totalBorrowingsOfAliceSafe, remainingBorrowCapacityInUsdc);
        
        uint256 debtManagerBalAfter = newToken.balanceOf(address(debtManager));
        assertEq(debtManagerBalBefore - debtManagerBalAfter, borrowInToken);
    }

    function test_NextBorrowAutomaticallyAddsInterestToThePreviousBorrows()
        public
    {
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(
            address(aliceSafe)
        ) / 4;

        vm.startPrank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), borrowAmt);

        assertEq(debtManager.borrowingOf(address(aliceSafe), address(usdc)), borrowAmt);

        uint256 timeElapsed = 10;

        vm.warp(block.timestamp + timeElapsed);
        uint256 expectedInterest = (borrowAmt *
            borrowApyPerSecond *
            timeElapsed) / 1e20;

        uint256 expectedTotalBorrowWithInterest = borrowAmt + expectedInterest;

        assertEq(
            debtManager.borrowingOf(address(aliceSafe), address(usdc)),
            expectedTotalBorrowWithInterest
        );

        aliceSafe.spend(keccak256("newTxId"), address(usdc), borrowAmt);

        assertEq(
            debtManager.borrowingOf(address(aliceSafe), address(usdc)),
            expectedTotalBorrowWithInterest + borrowAmt
        );

        vm.stopPrank();
    }

    function test_CannotBorrowIfTokenIsNotSupported() public {
        vm.prank(address(aliceSafe));        
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.borrow(address(weETH), 1);
    }

    function test_CannotBorrowIfDebtRatioGreaterThanThreshold() public {
        uint256 totalCanBorrow = debtManager.remainingBorrowingCapacityInUSD(
            address(aliceSafe)
        );
        vm.startPrank(etherFiWallet);
        aliceSafe.spend(txId, address(usdc), totalCanBorrow);

        vm.expectRevert("Insufficient borrowing power");
        aliceSafe.spend(keccak256("newTxId"), address(usdc), 1);

        vm.stopPrank();
    }

    function test_CannotBorrowIfUsdcBalanceInsufficientInDebtManager() public {
        deal(address(usdc), address(debtManager), 0);
        vm.startPrank(etherFiWallet);
        vm.expectRevert(IL2DebtManager.InsufficientLiquidity.selector);
        aliceSafe.spend(txId, address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotBorrowIfNoCollateral() public {
        deal(address(weETH), address(aliceSafe), 0);
        vm.startPrank(etherFiWallet);
        vm.expectRevert("Insufficient borrowing power");
        aliceSafe.spend(txId, address(usdc), 1);
        vm.stopPrank();
    }

    function test_CannotBorrowIfNotUserSafe() public {
        vm.expectRevert(IL2DebtManager.OnlyUserSafe.selector);
        debtManager.borrow(address(usdc), 1);
    }
}
