// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserSafeFactory} from "../../src/user-safe/UserSafeFactory.sol";
import {UserSafe} from "../../src//user-safe/UserSafe.sol";
import {UserSafeV2Mock} from "../../src/mocks/UserSafeV2Mock.sol";
import {Swapper1InchV6} from "../../src/utils/Swapper1InchV6.sol";
import {PriceProvider} from "../../src/oracle/PriceProvider.sol";
import {CashDataProvider} from "../../src/utils/CashDataProvider.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OwnerLib} from "../../src/libraries/OwnerLib.sol";

contract UserSafeSetup is Test {
    using OwnerLib for address;

    address owner = makeAddr("owner");

    address notOwner = makeAddr("notOwner");

    uint256 etherFiRecoverySignerPk;
    address etherFiRecoverySigner;
    uint256 thirdPartyRecoverySignerPk;
    address thirdPartyRecoverySigner;

    address etherFiRecoverySafe = makeAddr("etherFiRecoverySafe");

    UserSafeFactory factory;
    UserSafe impl;

    ERC20 usdc = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    ERC20 weETH = ERC20(0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe);
    Swapper1InchV6 swapper;
    PriceProvider priceProvider;
    CashDataProvider cashDataProvider;

    uint256 defaultSpendingLimit = 10000e6;
    uint64 withdrawalDelay = 10;
    address etherFiCashMultisig = makeAddr("multisig");
    address etherFiCashDebtManager = makeAddr("debtManager");
    address etherFiWallet = makeAddr("etherFiWallet");

    address weEthWethOracle = 0xE141425bc1594b8039De6390db1cDaf4397EA22b;
    address ethUsdcOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address swapRouter1InchV6 = 0x111111125421cA6dc452d289314280a0f8842A65;

    address alice;
    uint256 alicePk;
    bytes aliceBytes;
    UserSafe aliceSafe;

    uint256 passkeyPrivateKey =
        uint256(
            0x03d99692017473e2d631945a812607b23269d85721e0f370b8d3e7d29a874fd2
        );
    bytes passkeyOwner =
        hex"1c05286fe694493eae33312f2d2e0d0abeda8db76238b7a204be1fb87f54ce4228fef61ef4ac300f631657635c28e59bfb2fe71bce1634c81c65642042f6dc4d";
    UserSafe passkeyOwnerSafe;

    function setUp() public virtual {
        vm.createSelectFork("https://arbitrum-one.public.blastapi.io");
        address[] memory assets = new address[](1);
        assets[0] = address(weETH);

        vm.startPrank(owner);
        swapper = new Swapper1InchV6(swapRouter1InchV6, assets);
        priceProvider = new PriceProvider(weEthWethOracle, ethUsdcOracle);

        address proxy = Upgrades.deployUUPSProxy(
            "CashDataProvider.sol:CashDataProvider",
            abi.encodeWithSelector(
                // intiailize(address,uint64,address,address,address,address,address,address,address)
                0x04dfc293,
                owner,
                withdrawalDelay,
                etherFiCashMultisig,
                etherFiCashDebtManager,
                address(usdc),
                address(weETH),
                address(priceProvider),
                address(swapper),
                etherFiRecoverySafe
            )
        );
        cashDataProvider = CashDataProvider(proxy);

        (etherFiRecoverySigner, etherFiRecoverySignerPk) = makeAddrAndKey(
            "etherFiRecoverySigner"
        );

        (thirdPartyRecoverySigner, thirdPartyRecoverySignerPk) = makeAddrAndKey(
            "thirdPartyRecoverySigner"
        );

        impl = new UserSafe(
            address(cashDataProvider),
            etherFiRecoverySigner,
            thirdPartyRecoverySigner
        );

        factory = new UserSafeFactory(address(impl), owner);

        (alice, alicePk) = makeAddrAndKey("alice");
        aliceBytes = abi.encode(alice);

        aliceSafe = UserSafe(
            factory.createUserSafe(
                abi.encodeWithSelector(
                    // initialize(bytes,address,uint256)
                    0x80db4b91,
                    aliceBytes,
                    etherFiWallet,
                    defaultSpendingLimit
                )
            )
        );

        passkeyOwnerSafe = UserSafe(
            factory.createUserSafe(
                abi.encodeWithSelector(
                    // initialize(bytes,address,uint256)
                    0x80db4b91,
                    passkeyOwner,
                    etherFiWallet,
                    defaultSpendingLimit
                )
            )
        );

        deal(address(weETH), alice, 1000 ether);
        deal(address(usdc), alice, 1 ether);

        vm.stopPrank();
    }

    function test_Deploy() public view {
        assertEq(aliceSafe.owner().ethAddr, alice);
        assertEq(aliceSafe.etherFiRecoverySafe(), etherFiRecoverySafe);
        assertEq(aliceSafe.recoverySigners()[0].ethAddr, alice);
        assertEq(aliceSafe.recoverySigners()[1].ethAddr, etherFiRecoverySigner);
        assertEq(
            aliceSafe.recoverySigners()[2].ethAddr,
            thirdPartyRecoverySigner
        );

        assertEq(
            abi.encode(passkeyOwnerSafe.owner().x, passkeyOwnerSafe.owner().y),
            passkeyOwner
        );

        assertEq(passkeyOwnerSafe.etherFiRecoverySafe(), etherFiRecoverySafe);
        assertEq(
            abi.encode(
                passkeyOwnerSafe.recoverySigners()[0].x,
                passkeyOwnerSafe.recoverySigners()[0].y
            ),
            passkeyOwner
        );
        assertEq(
            passkeyOwnerSafe.recoverySigners()[1].ethAddr,
            etherFiRecoverySigner
        );
        assertEq(
            passkeyOwnerSafe.recoverySigners()[2].ethAddr,
            thirdPartyRecoverySigner
        );

        UserSafe.SpendingLimitData memory spendingLimit = aliceSafe
            .spendingLimit();
        assertEq(spendingLimit.spendingLimit, defaultSpendingLimit);
    }
}
