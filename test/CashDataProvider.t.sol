// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ICashDataProvider, CashDataProvider} from "../src/utils/CashDataProvider.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";

error OwnableUnauthorizedAccount(address account);

contract CashDataProviderTest is Test {
    CashDataProvider cashDataProvider;
    address owner = makeAddr("owner");
    address notOwner = makeAddr("notOwner");
    uint256 delay = 100;
    address etherFiWallet = makeAddr("etherFiWallet");
    address etherFiCashMultisig = makeAddr("etherFiCashMultisig");
    address priceProvider = makeAddr("priceProvider");
    address swapper = makeAddr("swapper");
    address aaveV3Adapter = makeAddr("aaveV3Adapter");
    address collateralToken = makeAddr("collateralToken");
    address borrowToken = makeAddr("borrowToken");

    function setUp() public {
        vm.startPrank(owner);
        address cashDataProviderImpl = address(new CashDataProvider());

        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = collateralToken;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = borrowToken;

        (bool success, ) = address(cashDataProvider).call(
            abi.encodeWithSelector(
                // intiailize(address,uint64,address,address,address,address,address,address,address[],address[])
                0x7b8628c9,
                owner,
                delay,
                etherFiWallet,
                etherFiCashMultisig,
                address(priceProvider),
                address(swapper),
                address(aaveV3Adapter),
                collateralTokens,
                borrowTokens
            )
        );
        if (!success) revert("Initialize failed on Cash Data Provider");

        vm.stopPrank();
    }

    function test_Deploy() public view {
        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = collateralToken;
        address[] memory borrowTokens = new address[](1);
        borrowTokens[0] = borrowToken;

        assertEq(cashDataProvider.owner(), owner);
        assertEq(cashDataProvider.delay(), delay);
        assertEq(cashDataProvider.etherFiWallet(), etherFiWallet);
        assertEq(cashDataProvider.etherFiCashMultiSig(), etherFiCashMultisig);
        assertEq(cashDataProvider.priceProvider(), priceProvider);
        assertEq(cashDataProvider.swapper(), swapper);
        assertEq(cashDataProvider.aaveAdapter(), aaveV3Adapter);
        assertEq(cashDataProvider.collateralTokens(), collateralTokens);
        assertEq(cashDataProvider.borrowTokens(), borrowTokens);
        assertEq(cashDataProvider.isCollateralToken(collateralToken), true);
        assertEq(cashDataProvider.isBorrowToken(borrowToken), true);
    }

    function test_Setters() public {
        uint256 newDelay = 10;
        setValue(
            abi.encodeWithSelector(
                ICashDataProvider.setDelay.selector,
                newDelay
            ),
            abi.encodeWithSelector(ICashDataProvider.delay.selector),
            abi.encode(newDelay)
        );

        address newEtherFiWallet = makeAddr("newEtherFiWallet");
        setValue(
            abi.encodeWithSelector(
                ICashDataProvider.setEtherFiWallet.selector,
                newEtherFiWallet
            ),
            abi.encodeWithSelector(ICashDataProvider.etherFiWallet.selector),
            abi.encode(newEtherFiWallet)
        );

        address newEtherFiCashMultiSig = makeAddr("newEtherFiCashMultiSig");
        setValue(
            abi.encodeWithSelector(
                ICashDataProvider.setEtherFiCashMultiSig.selector,
                newEtherFiCashMultiSig
            ),
            abi.encodeWithSelector(
                ICashDataProvider.etherFiCashMultiSig.selector
            ),
            abi.encode(newEtherFiCashMultiSig)
        );

        address newPriceProvider = makeAddr("newPriceProvider");
        setValue(
            abi.encodeWithSelector(
                ICashDataProvider.setPriceProvider.selector,
                newPriceProvider
            ),
            abi.encodeWithSelector(ICashDataProvider.priceProvider.selector),
            abi.encode(newPriceProvider)
        );

        address newSwapper = makeAddr("newSwapper");
        setValue(
            abi.encodeWithSelector(
                ICashDataProvider.setSwapper.selector,
                newSwapper
            ),
            abi.encodeWithSelector(ICashDataProvider.swapper.selector),
            abi.encode(newSwapper)
        );

        address newAaveAdapter = makeAddr("newAaveAdapter");
        setValue(
            abi.encodeWithSelector(
                ICashDataProvider.setAaveAdapter.selector,
                newAaveAdapter
            ),
            abi.encodeWithSelector(ICashDataProvider.aaveAdapter.selector),
            abi.encode(newAaveAdapter)
        );
    }

    function test_SupportCollateralToken() public {
        supportTokensTest(true);
    }

    function test_SupportBorrowToken() public {
        supportTokensTest(false);
    }

    function test_UnsupportCollateralToken() public {
        unsupportTokensTest(true);
    }

    function test_UnsupportBorrowToken() public {
        unsupportTokensTest(false);
    }

    function unsupportTokensTest(bool isCollateral) internal {
        address token = makeAddr("token");

        if (isCollateral) {
            // Add a new collateral token so the other one can be removed
            vm.prank(owner);
            cashDataProvider.supportCollateralToken(token);

            vm.prank(notOwner);
            vm.expectRevert(
                abi.encodeWithSelector(
                    OwnableUnauthorizedAccount.selector,
                    notOwner
                )
            );
            cashDataProvider.unsupportCollateralToken(collateralToken);

            vm.prank(owner);
            vm.expectEmit(true, true, true, true);
            emit ICashDataProvider.CollateralTokenRemoved(collateralToken);
            cashDataProvider.unsupportCollateralToken(collateralToken);

            assertEq(
                cashDataProvider.isCollateralToken(collateralToken),
                false
            );

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.InvalidValue.selector);
            cashDataProvider.unsupportCollateralToken(address(0));

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.NotASupportedToken.selector);
            cashDataProvider.unsupportCollateralToken(collateralToken);

            vm.prank(owner);
            vm.expectRevert(
                ICashDataProvider.ArrayBecomesEmptyAfterRemoval.selector
            );
            cashDataProvider.unsupportCollateralToken(token);
        } else {
            // Add a new debt token so the other one can be removed
            vm.prank(owner);
            cashDataProvider.supportBorrowToken(token);

            vm.prank(notOwner);
            vm.expectRevert(
                abi.encodeWithSelector(
                    OwnableUnauthorizedAccount.selector,
                    notOwner
                )
            );
            cashDataProvider.unsupportBorrowToken(borrowToken);

            vm.prank(owner);
            vm.expectEmit(true, true, true, true);
            emit ICashDataProvider.BorrowTokenRemoved(borrowToken);
            cashDataProvider.unsupportBorrowToken(borrowToken);

            assertEq(cashDataProvider.isBorrowToken(borrowToken), false);

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.InvalidValue.selector);
            cashDataProvider.unsupportBorrowToken(address(0));

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.NotASupportedToken.selector);
            cashDataProvider.unsupportBorrowToken(borrowToken);

            vm.prank(owner);
            vm.expectRevert(
                ICashDataProvider.ArrayBecomesEmptyAfterRemoval.selector
            );
            cashDataProvider.unsupportBorrowToken(token);
        }
    }

    function supportTokensTest(bool isCollateral) internal {
        address token = makeAddr("token");

        if (isCollateral) {
            vm.prank(notOwner);
            vm.expectRevert(
                abi.encodeWithSelector(
                    OwnableUnauthorizedAccount.selector,
                    notOwner
                )
            );
            cashDataProvider.supportCollateralToken(token);

            vm.prank(owner);
            vm.expectEmit(true, true, true, true);
            emit ICashDataProvider.CollateralTokenAdded(token);
            cashDataProvider.supportCollateralToken(token);

            assertEq(cashDataProvider.isCollateralToken(token), true);

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.AlreadyCollateralToken.selector);
            cashDataProvider.supportCollateralToken(token);

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.InvalidValue.selector);
            cashDataProvider.supportCollateralToken(address(0));
        } else {
            vm.prank(notOwner);
            vm.expectRevert(
                abi.encodeWithSelector(
                    OwnableUnauthorizedAccount.selector,
                    notOwner
                )
            );
            cashDataProvider.supportBorrowToken(token);

            vm.prank(owner);
            vm.expectEmit(true, true, true, true);
            emit ICashDataProvider.BorrowTokenAdded(token);
            cashDataProvider.supportBorrowToken(token);

            assertEq(cashDataProvider.isBorrowToken(token), true);

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.AlreadyBorrowToken.selector);
            cashDataProvider.supportBorrowToken(token);

            vm.prank(owner);
            vm.expectRevert(ICashDataProvider.InvalidValue.selector);
            cashDataProvider.supportBorrowToken(address(0));
        }
    }

    function setValue(
        bytes memory _calldata,
        bytes memory getValueCalldata,
        bytes memory value
    ) internal {
        vm.prank(notOwner);
        (bool success, bytes memory data) = address(cashDataProvider).call(
            _calldata
        );
        assertEq(success, false);
        assertEq(
            data,
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );

        vm.prank(owner);
        (success, ) = address(cashDataProvider).call(_calldata);
        assertEq(success, true);

        bytes memory val;
        (success, val) = address(cashDataProvider).staticcall(getValueCalldata);
        assertEq(success, true);
        assertEq(val, value);
    }
}
