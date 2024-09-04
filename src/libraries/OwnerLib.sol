// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

library OwnerLib {
    struct OwnerObject {
        address ethAddr;
        uint256 x;
        uint256 y;
    }

    error OnlyOwner();
    error OwnerCannotBeZero();

    function getOwnerObject(
        bytes memory _ownerBytes
    ) internal pure returns (OwnerObject memory) {
        if (_ownerBytes.length == 32) {
            address addr;
            assembly ("memory-safe") {
                addr := mload(add(_ownerBytes, 32))
            }

            return OwnerObject({ethAddr: addr, x: 0, y: 0});
        }

        (uint256 x, uint256 y) = abi.decode(_ownerBytes, (uint256, uint256));
        return OwnerObject({ethAddr: address(0), x: x, y: y});
    }

    function getOwnerObject(
        address _owner
    ) internal pure returns (OwnerObject memory) {
        return OwnerObject({ethAddr: _owner, x: 0, y: 0});
    }

    function _onlyOwner(bytes memory _ownerBytes) internal view {
        if (_ownerBytes.length != 32) revert OnlyOwner();

        address __owner;
        assembly ("memory-safe") {
            __owner := mload(add(_ownerBytes, 32))
        }

        if (msg.sender != __owner) revert OnlyOwner();
    }

    function _ownerNotZero(OwnerObject memory owner) internal pure {
        if (owner.ethAddr == address(0) && owner.x == 0 && owner.y == 0)
            revert OwnerCannotBeZero();
    }
}
