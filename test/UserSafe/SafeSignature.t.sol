// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserSafe, UserSafeEventEmitter, OwnerLib, UserSafeLib} from "../../src/user-safe/UserSafeCore.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Setup} from "../Setup.t.sol";
import {console} from "forge-std/Test.sol";

contract SafeOwnerTest is Setup {
    using MessageHashUtils for bytes32;
    using OwnerLib for bytes;

    address recoverySigner1 = 0xbfCe61CE31359267605F18dcE65Cb6c3cc9694A7;
    address recoverySigner2 = 0xa265C271adbb0984EFd67310cfe85A77f449e291;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        cashDataProvider.setEtherFiRecoverySigner(recoverySigner1);
        cashDataProvider.setThirdPartyRecoverySigner(recoverySigner2);
        vm.stopPrank();
    }

    function test_SetOwnerWithSafeSignature() public {
        (address newOwner, ) = makeAddrAndKey("newOwner");
        bytes memory newOwnerBytes = abi.encode(newOwner);

        uint256 nonce = aliceSafe.nonce() + 1;

        bytes32 msgHash = keccak256(
            abi.encode(
                UserSafeLib.RECOVERY_METHOD,
                block.chainid,
                address(aliceSafe),
                nonce,
                newOwnerBytes
            )
        );

        proposeRecoverySignature(msgHash.toEthSignedMessageHash());
    }

    function proposeRecoverySignature(bytes32 messageHash) internal {
        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/safeRecoveryPropose.ts";
        inputs[3] = vm.toString(messageHash);

        vm.ffi(inputs);
    }

}