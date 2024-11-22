// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Setup, DebtManagerAdmin, PriceProvider, MockPriceProvider, IAggregatorV3, MockERC20} from "../Setup.t.sol";
import {IL2DebtManager} from "../../src/interfaces/IL2DebtManager.sol";
import {AaveLib} from "../../src/libraries/AaveLib.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IUserSafe, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";

contract DebtManagerSupplyAndWithdrawTest is Setup {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    uint256 collateralAmt = 0.01 ether;
    IERC20 weth;

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

        if (!isFork(chainId)) weth = IERC20(address(new MockERC20("WETH", "WETH", 18)));
        else weth = IERC20(chainConfig.weth);

        deal(address(weETH), address(aliceSafe), collateralAmt);
    }

    function test_SupplyAndWithdraw() public {
        deal(address(usdc), notOwner, 1 ether);
        uint256 principle = 0.01 ether;

        vm.startPrank(notOwner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), principle);
        debtManager.supply(notOwner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.supplierBalance(notOwner, address(usdc)),
            principle
        );

        uint256 earnings = _borrowAndRepay();

        assertEq(
            debtManager.supplierBalance(notOwner, address(usdc)),
            principle + earnings
        );

        vm.prank(notOwner);
        debtManager.withdrawBorrowToken(address(usdc), earnings + principle);

        assertEq(debtManager.supplierBalance(notOwner, address(usdc)), 0);
    }

    function test_CannotWithdrawLessThanMinShares() public {
        deal(address(usdc), notOwner, 1 ether);
        uint256 principle = debtManager.borrowTokenConfig(address(usdc)).minShares;

        vm.startPrank(notOwner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);
 
        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), principle);
        debtManager.supply(notOwner, address(usdc), principle);
        vm.stopPrank();

        assertEq(
            debtManager.supplierBalance(notOwner, address(usdc)),
            principle
        );

        vm.prank(notOwner);
        vm.expectRevert(IL2DebtManager.SharesCannotBeLessThanMinShares.selector);
        debtManager.withdrawBorrowToken(address(usdc), principle - 1);
    }

    function test_SupplyEighteenDecimalsTwice() public {
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = address(usdc);

        vm.startPrank(owner);
        if (isFork(chainId)) {
            address[] memory _tokens = new address[](1);
            _tokens[0] = address(weth);
            
            PriceProvider.Config[] memory _configs = new PriceProvider.Config[](1); 
            _configs[0] = PriceProvider.Config({
                oracle: ethUsdcOracle,
                priceFunctionCalldata: hex"",
                isChainlinkType: true,
                oraclePriceDecimals: IAggregatorV3(ethUsdcOracle).decimals(),
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
            address(weth),
            collateralTokenConfig
        );

        DebtManagerAdmin(address(debtManager)).supportBorrowToken(
            address(weth), 
            borrowApyPerSecond, 
            uint128(1 * 10 ** IERC20Metadata(address(weth)).decimals())
        );
        vm.stopPrank();

        uint256 principle = 1 ether;
        deal(address(weth), notOwner, principle);

        vm.startPrank(notOwner);
        IERC20(address(weth)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(weth), principle);
        debtManager.supply(notOwner, address(weth), principle);
        vm.stopPrank();

        address newSupplier = makeAddr("newSupplier");

        deal(address(weth), newSupplier, principle);
        
        vm.startPrank(newSupplier);
        IERC20(address(weth)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(newSupplier, newSupplier, address(weth), principle);
        debtManager.supply(newSupplier, address(weth), principle);
        vm.stopPrank();
    }

    function test_SupplyTwice() public {
        deal(address(usdc), notOwner, 1 ether);
        uint256 principle = 0.01 ether;
        vm.startPrank(notOwner);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(notOwner, notOwner, address(usdc), principle);
        debtManager.supply(notOwner, address(usdc), principle);
        vm.stopPrank();

        address newSupplier = makeAddr("newSupplier");

        deal(address(usdc), newSupplier, principle);
        
        vm.startPrank(newSupplier);
        IERC20(address(usdc)).forceApprove(address(debtManager), principle);

        vm.expectEmit(true, true, true, true);
        emit IL2DebtManager.Supplied(newSupplier, newSupplier, address(usdc), principle);
        debtManager.supply(newSupplier, address(usdc), principle);
        vm.stopPrank();
    }

    function test_CanOnlySupplyBorrowTokens() public {
        vm.prank(notOwner);
        vm.expectRevert(IL2DebtManager.UnsupportedBorrowToken.selector);
        debtManager.supply(owner, address(weETH), 1);
    }

    function test_UserSafeCannotSupply() public {
        vm.prank(alice);
        vm.expectRevert(IL2DebtManager.UserSafeCannotSupplyDebtTokens.selector);
        debtManager.supply(address(aliceSafe), address(usdc), 1);
    }

    function test_CannotWithdrawTokenThatWasNotSupplied() public {
        vm.prank(notOwner);
        vm.expectRevert(IL2DebtManager.ZeroTotalBorrowTokens.selector);
        debtManager.withdrawBorrowToken(address(weETH), 1 ether);
    }

    function _borrowAndRepay() internal returns (uint256) {
        vm.startPrank(etherFiWallet);
        uint256 borrowAmt = debtManager.remainingBorrowingCapacityInUSD(
            address(aliceSafe)
        ) / 2;
        aliceSafe.spend(txId, address(usdc), borrowAmt);

        // 1 day after, there should be some interest accumulated
        vm.warp(block.timestamp + 24 * 60 * 60);
        uint256 repayAmt = debtManager.borrowingOf(address(aliceSafe), address(usdc));
        deal(address(usdc), address(aliceSafe), repayAmt);
        aliceSafe.repay(address(usdc), repayAmt);
        vm.stopPrank();

        return repayAmt - borrowAmt;
    }
}
