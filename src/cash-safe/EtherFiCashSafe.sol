// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract EtherFiCashSafe is Initializable, UUPSUpgradeable {
    mapping(address account => bool isSigner) private _isSigner;
    uint256 private _quorum;

    function quorum() external view returns (uint256) {
        return _quorum;
    }

    function isSigner(address account) external view returns (bool) {
        return _isSigner[account];
    }

    function receiveFunds(address token, uint256 amount) external {}

    function _authorizeUpgrade(address newImplementation) internal override {}
}
