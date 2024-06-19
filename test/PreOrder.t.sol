// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {PreOrder} from "../src/PreOrder.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract PreOrderTest is Test {
    // Default contract 
    PreOrder public preorder;

    // Default users
    address public whale;
    address public whale2;
    address public tuna;
    address public eBeggar;

    // Default contract inputs
    address public owner;
    address public admin;
    address public gnosis;
    address public eEthToken;
    PreOrder.TierConfig[] public tiers;

    function setUp() public {
        whale = vm.addr(0x111111);
        whale2 = vm.addr(0x222222);
        tuna = vm.addr(0x333333);
        eBeggar = vm.addr(0x444444);

        owner = vm.addr(0x12345678);
        admin = vm.addr(0x87654321);

        gnosis = address(0xbeef);
        eEthToken = address(0xdead);

        // Initialize a PreOrder contract
        tiers.push(PreOrder.TierConfig({
            costWei: 1000 ether,
            maxSupply: 10
        }));
        tiers.push(PreOrder.TierConfig({
            costWei: 1 ether,
            maxSupply: 100
        }));
        tiers.push(PreOrder.TierConfig({
            costWei: 0.01 ether,
            maxSupply: 10000
        }));

        preorder = new PreOrder();
        preorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com",
            tiers
        );

        // Deal some tokens to the users
        vm.deal(whale, 10_000 ether);
        vm.deal(whale2, 10_000 ether);
        vm.deal(tuna, 10_000 ether);
        vm.deal(eBeggar, 1 ether);

    }

    function testAssemblyProperlySetsArrayLength() public view {
        // Assert the max supply is correctly set based on the tier configurations
        uint256 expectedMaxSupply = tiers[0].maxSupply + tiers[1].maxSupply + tiers[2].maxSupply;
        assertEq(preorder.maxSupply(), expectedMaxSupply);
    }

    function testMint() public {
        // Mint increment test 
        vm.prank(whale);
        uint gnosisBalanceStart = gnosis.balance;
        preorder.mint{value: 1000 ether}(0);
        vm.prank(whale2);
        preorder.mint{value: 1000 ether}(0);
        uint gnosisBalanceEnd = gnosis.balance;

        // Ensure payment was recieved and the correct tokens were minted
        assertEq(gnosisBalanceEnd - gnosisBalanceStart, 2000 ether);
        assertEq(preorder.balanceOf(whale, 0), 1);
        assertEq(preorder.balanceOf(whale2, 1), 1);

        // Minting from different tiers
        // The mint ids are staggered by tier
        vm.prank(tuna);
        preorder.mint{value: 1 ether}(1);
        vm.prank(eBeggar);
        preorder.mint{value: 0.01 ether}(2);

        assertEq(preorder.balanceOf(tuna, 10), 1);
        assertEq(preorder.balanceOf(eBeggar, 110), 1);

        // Minting over the max supply
        vm.startPrank(tuna);
        // 99 more of the tuna tier can be minted
        for (uint256 i = 0; i < 99; i++) {
            preorder.mint{value: 1 ether}(1);
        }

        // Tuna user should have all of the tuna tier tokens
        for (uint256 i = 0; i < 100; i++) {
            assertEq(preorder.balanceOf(tuna, i + 10), 1);
        }

        // Tuna tier is now maxed out and payment should fail
        uint gnosisBalanceStart2 = gnosis.balance;
        vm.expectRevert("Tier sold out");
        preorder.mint{value: 1 ether}(1);
        uint gnosisBalanceEnd2 = gnosis.balance;

        assertEq(gnosisBalanceEnd2 - gnosisBalanceStart2, 0);
    }

    function testRevert() public {
        // Revert on incorrect amount sent
        vm.startPrank(whale);
        vm.expectRevert("Incorrect amount sent");
        preorder.mint{value: 1001 ether}(0);
        vm.expectRevert("Incorrect amount sent");
        preorder.mint{value: 999 ether}(0);

        // Revert on ETH direct sends to the contract
        vm.expectRevert("Direct transfers not allowed");
        address(preorder).call{value: 1 ether}("");

        vm.expectRevert("Direct transfers not allowed");
        payable(address(preorder)).transfer(1 ether);

        // revert on admin/owner functions
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, whale)
        );
        preorder.setAdmin(whale);
        vm.expectRevert("Not the admin");
        preorder.setTierData(0, 100 ether);
    }

    function testPause() public {
        // Pause and unpause
        vm.prank(admin);
        preorder.pauseContract();
        vm.startPrank(whale);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        preorder.mint{value: 1000 ether}(0);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        preorder.MintWithPermit(0, 1 ether, 0, 0x0, 0x0, 0x0);

        vm.expectRevert("Not the admin");
        preorder.unPauseContract();

        // can still call admin functions while paused
        vm.startPrank(admin);
        preorder.unPauseContract();

        vm.startPrank(whale);
        preorder.mint{value: 1000 ether}(0);
        assertEq(preorder.balanceOf(whale, 0), 1);
    }

    function testMintWithPermit() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        address eEthWhale = 0xe48793B1533b351Ae184E1c3119D0955DdE7b330;

        IERC20 eEthMainnet = IERC20(0x35fA164735182de50811E8e2E824cFb9B6118ac2);

        PreOrder.TierConfig[] memory singleTier = new PreOrder.TierConfig[](1);
        singleTier[0] = PreOrder.TierConfig({
            costWei: 1 ether,
            maxSupply: 10
        });

        preorder = new PreOrder();
        preorder.initialize(
            owner,
            gnosis,
            admin,
            address(eEthMainnet),
            "https://www.cool-kid-metadata.com",
            singleTier
        );

        // Send eEth to alice
        vm.prank(eEthWhale);
        eEthMainnet.transfer(alice, 100 ether);
        assertGe(eEthMainnet.balanceOf(alice),  10 ether);

        // Set up permit signature for MintWithPermit
        uint256 nonce = IERC20Permit(address(eEthMainnet)).nonces(alice);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IERC20Permit(address(eEthMainnet)).DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                    alice,
                    address(preorder),
                    1 ether,
                    0,
                    deadline
                ))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, permitHash);


        vm.startPrank(alice);
        vm.expectRevert("Incorrect amount sent");
        preorder.MintWithPermit(0, 2 ether, deadline, v, r, s);

        vm.expectRevert("Incorrect amount sent");
        preorder.MintWithPermit(0, 0.9 ether, deadline, v, r, s);

        preorder.MintWithPermit(0, 1 ether, deadline, v, r, s);

        vm.expectRevert("ERC20Permit: invalid signature");
        preorder.MintWithPermit(0, 1 ether, deadline, v, r, s);

        assertEq(preorder.balanceOf(alice, 0), 1);

        // Note: Due to the share system rounding down to protect the protocol from losses,
        // the actual transfer amount is a few wei less than 1 ether
        // Verifies | balance - expected amount ether| ≤ 5 wei
        assertApproxEqRel(eEthMainnet.balanceOf(alice), 99 ether, 5);
        assertApproxEqRel(eEthMainnet.balanceOf(gnosis), 1 ether, 5);


        // Testing signature with insufficient funds
        nonce = IERC20Permit(address(eEthMainnet)).nonces(alice);
        deadline = block.timestamp + 1 hours;
        permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IERC20Permit(address(eEthMainnet)).DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                    alice,
                    address(preorder),
                    0.9 ether,
                    0,
                    deadline
                ))
            )
        );
        (v, r, s) = vm.sign(alicePk, permitHash);

        vm.expectRevert("ERC20Permit: invalid signature");
        preorder.MintWithPermit(0, 1 ether, deadline, v, r, s);
    }

    function testSellOutTiers() public {
        // Create new tiers with small supplies
        PreOrder.TierConfig[] memory smallTiers = new PreOrder.TierConfig[](3);
        smallTiers[0] = PreOrder.TierConfig({
            costWei: 0.1 ether,
            maxSupply: 2
        });
        smallTiers[1] = PreOrder.TierConfig({
            costWei: 0.2 ether,
            maxSupply: 3
        });
        smallTiers[2] = PreOrder.TierConfig({
            costWei: 0.3 ether,
            maxSupply: 1
        });

        // Initialize a new PreOrder contract with small tiers
        PreOrder smallPreorder = new PreOrder();
        smallPreorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com/small-tiers",
            smallTiers
        );

        // Mint tokens until each tier is sold out
        uint gnosisBalanceStart = gnosis.balance;

        // sell out each tier in a random order
        vm.prank(whale);
        smallPreorder.mint{value: 0.1 ether}(0);
        vm.prank(whale2);
        smallPreorder.mint{value: 0.3 ether}(2);
        vm.expectRevert("Tier sold out");
        smallPreorder.mint{value: 0.3 ether}(2);
        vm.prank(tuna);
        smallPreorder.mint{value: 0.2 ether}(1);
        vm.prank(eBeggar);
        smallPreorder.mint{value: 0.2 ether}(1);

        vm.prank(whale2);
        smallPreorder.mint{value: 0.1 ether}(0);
        vm.expectRevert("Tier sold out");
        smallPreorder.mint{value: 0.1 ether}(0);
        vm.prank(whale);
        smallPreorder.mint{value: 0.2 ether}(1);
        vm.expectRevert("Tier sold out");
        smallPreorder.mint{value: 0.2 ether}(1);

        

        uint gnosisBalanceEnd = gnosis.balance;

        // Ensure payments were received and the correct tokens were minted
        assertEq(gnosisBalanceEnd - gnosisBalanceStart, 1.1 ether);
        assertEq(smallPreorder.balanceOf(whale, 0), 1);
        assertEq(smallPreorder.balanceOf(whale2, 1), 1);
        assertEq(smallPreorder.balanceOf(tuna, 2), 1);
        assertEq(smallPreorder.balanceOf(eBeggar, 3), 1);
        assertEq(smallPreorder.balanceOf(whale, 4), 1);
        assertEq(smallPreorder.balanceOf(whale2, 5), 1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert("NOT_AUTHORIZED");
        smallPreorder.safeBatchTransferFrom(whale, eBeggar, ids, amounts, hex"");

        vm.prank(whale);
        smallPreorder.safeBatchTransferFrom(whale, eBeggar, ids, amounts, hex"");

        assertEq(smallPreorder.balanceOf(eBeggar, 0), 1);
        assertEq(smallPreorder.balanceOf(whale, 0), 0);
    }

    function testTiersLengthCheck() public {
        for (uint256 i = 0; i < 300; i++) {
            tiers.push(PreOrder.TierConfig({
                costWei: 0.1 ether,
                maxSupply: 1
            }));
        }

        preorder = new PreOrder();
        vm.expectRevert(stdError.arithmeticError);
        preorder.initialize(
            owner,
            gnosis,
            admin,
            eEthToken,
            "https://www.cool-kid-metadata.com",
            tiers
        );
    }
}
