// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol"; 
import {CashDataProvider, ICashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract CashDataProviderTest is Test {
    CashDataProvider cashDataProvider;

    bytes32 ETHER_FI_WALLET_ROLE = keccak256("ETHER_FI_WALLET_ROLE");
    bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    address owner = makeAddr("owner");
    address admin = makeAddr("admin");
    address notAdmin = makeAddr("notAdmin");
    address notOwner = makeAddr("notOwner");

    uint64 delay = 100;
    address etherFiWallet = makeAddr("etherFiWallet");
    address settlementDispatcher = makeAddr("settlementDispatcher");
    address priceProvider = makeAddr("priceProvider");
    address swapper = makeAddr("swapper");
    address aaveAdapter = makeAddr("aaveAdapter");
    address userSafeFactory = makeAddr("userSafeFactory");
    address debtManager = makeAddr("debtManager");
    address userSafeEventEmitter = makeAddr("userSafeEventEmitter");

    function setUp() public {
        vm.startPrank(owner);

        address cashDataProviderImpl = address(new CashDataProvider());
        cashDataProvider = CashDataProvider(
            address(new UUPSProxy(cashDataProviderImpl, ""))
        );

        cashDataProvider.initialize(
            owner,
            delay,
            etherFiWallet,
            settlementDispatcher,
            debtManager,
            priceProvider,
            swapper,
            aaveAdapter,
            userSafeFactory,
            userSafeEventEmitter
        );

        cashDataProvider.grantRole(ADMIN_ROLE, admin);

        vm.stopPrank();
    }

    function test_Deploy() public view {
        assertEq(cashDataProvider.owner(), owner);
        assertEq(cashDataProvider.delay(), delay);
        assertEq(cashDataProvider.isEtherFiWallet(etherFiWallet), true);
        assertEq(cashDataProvider.settlementDispatcher(), settlementDispatcher);
        assertEq(cashDataProvider.etherFiCashDebtManager(), debtManager);
        assertEq(cashDataProvider.priceProvider(), priceProvider);
        assertEq(cashDataProvider.swapper(), swapper);
        assertEq(cashDataProvider.aaveAdapter(), aaveAdapter);
        assertEq(cashDataProvider.userSafeFactory(), userSafeFactory);
        assertEq(cashDataProvider.userSafeEventEmitter(), userSafeEventEmitter);
        assertEq(cashDataProvider.hasRole(ADMIN_ROLE, owner), true);
        assertEq(cashDataProvider.hasRole(ADMIN_ROLE, admin), true);
    }

    function test_SetDelay() public {
        assertEq(cashDataProvider.delay(), delay);
        uint64 newDelay = 1000;
        
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setDelay(newDelay);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setDelay(0);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.DelayUpdated(delay, newDelay);
        cashDataProvider.setDelay(newDelay);
        assertEq(cashDataProvider.delay(), newDelay);
    }
 
    function test_GrantEtherFiWalletRole() public {
        address newWallet = makeAddr("newWallet");
        
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.grantEtherFiWalletRole(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.grantEtherFiWalletRole(address(0));
        
        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.AlreadyAWhitelistedEtherFiWallet.selector);
        cashDataProvider.grantEtherFiWalletRole(etherFiWallet);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.EtherFiWalletAdded(newWallet);
        cashDataProvider.grantEtherFiWalletRole(newWallet);
        assertEq(cashDataProvider.isEtherFiWallet(newWallet), true);
    }
  
    function test_RevokeEtherFiWalletRole() public {
        address newWallet = makeAddr("newWallet");
        
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.revokeEtherFiWalletRole(newWallet);
        
        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.NotAWhitelistedEtherFiWallet.selector);
        cashDataProvider.revokeEtherFiWalletRole(newWallet);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.EtherFiWalletRemoved(etherFiWallet);
        cashDataProvider.revokeEtherFiWalletRole(etherFiWallet);
        assertEq(cashDataProvider.isEtherFiWallet(etherFiWallet), false);
    }

    function test_SetSettlementDispatcher() public {
        address newWallet = makeAddr("newWallet");
        
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setSettlementDispatcher(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setSettlementDispatcher(address(0));
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.SettlementDispatcherUpdated(settlementDispatcher, newWallet);
        cashDataProvider.setSettlementDispatcher(newWallet);
        assertEq(cashDataProvider.settlementDispatcher(), newWallet);
    }

    function test_SetEtherFiCashDebtManager() public {
        address newWallet = makeAddr("newWallet");
    
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setEtherFiCashDebtManager(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setEtherFiCashDebtManager(address(0));
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.CashDebtManagerUpdated(debtManager, newWallet);
        cashDataProvider.setEtherFiCashDebtManager(newWallet);
        assertEq(cashDataProvider.etherFiCashDebtManager(), newWallet);
    }

    function test_SetPriceProvider() public {
        address newWallet = makeAddr("newWallet");
    
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setPriceProvider(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setPriceProvider(address(0));
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.PriceProviderUpdated(priceProvider, newWallet);
        cashDataProvider.setPriceProvider(newWallet);
        assertEq(cashDataProvider.priceProvider(), newWallet);
    }

    function test_SetSwapper() public {
        address newWallet = makeAddr("newWallet");
    
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setSwapper(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setSwapper(address(0));
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.SwapperUpdated(swapper, newWallet);
        cashDataProvider.setSwapper(newWallet);
        assertEq(cashDataProvider.swapper(), newWallet);
    }

    function test_SetAaveAdapter() public {
        address newWallet = makeAddr("newWallet");
    
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setAaveAdapter(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setAaveAdapter(address(0));
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.AaveAdapterUpdated(aaveAdapter, newWallet);
        cashDataProvider.setAaveAdapter(newWallet);
        assertEq(cashDataProvider.aaveAdapter(), newWallet);
    }

    function test_SetUserSafeFactory() public {
        address newWallet = makeAddr("newWallet");
    
        vm.prank(notAdmin);
        vm.expectRevert(buildAccessControlRevertData(notAdmin, ADMIN_ROLE));
        cashDataProvider.setUserSafeFactory(newWallet);

        vm.prank(admin);
        vm.expectRevert(ICashDataProvider.InvalidValue.selector);
        cashDataProvider.setUserSafeFactory(address(0));
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.UserSafeFactoryUpdated(userSafeFactory, newWallet);
        cashDataProvider.setUserSafeFactory(newWallet);
        assertEq(cashDataProvider.userSafeFactory(), newWallet);
    }

    function test_WhitelistUserSafe() public {
        address newWallet = makeAddr("newWallet");
    
        vm.prank(notAdmin);
        vm.expectRevert(ICashDataProvider.OnlyUserSafeFactory.selector);
        cashDataProvider.whitelistUserSafe(newWallet);
        
        vm.prank(userSafeFactory);
        vm.expectEmit(true, true, true, true);
        emit ICashDataProvider.UserSafeWhitelisted(newWallet);
        cashDataProvider.whitelistUserSafe(newWallet);
        assertEq(cashDataProvider.isUserSafe(newWallet), true);
    }

    function buildAccessControlRevertData(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                role
            );
    }
}