// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CashWrappedERC20} from "./CashWrappedERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract CashTokenWrapperFactory is UpgradeableBeacon {
    mapping (address inputToken => address wrappedToken) public cashWrappedToken;
    
    event WrappedTokenDeployed(address token);

    error InvalidValue();
    error WrappedTokenAlreadyExists();
    error WrappedTokenDoesntExists();

    constructor(
        address _implementation,
        address _owner
    ) UpgradeableBeacon(_implementation, _owner) {}

    function deployWrapper(address inputToken) external virtual onlyOwner returns (address) {
        if (inputToken == address(0)) revert InvalidValue();
        if (cashWrappedToken[inputToken] != address(0)) revert WrappedTokenAlreadyExists();
        bytes memory data = abi.encodeWithSelector(
            CashWrappedERC20.initialize.selector, 
            inputToken, 
            string(abi.encodePacked("eCash ", IERC20Metadata(inputToken).name())),
            string(abi.encodePacked("ec", IERC20Metadata(inputToken).symbol())),
            IERC20Metadata(inputToken).decimals()
        );

        address wrappedToken = address(new BeaconProxy(address(this), data));
        cashWrappedToken[inputToken] = wrappedToken;
        
        emit WrappedTokenDeployed(wrappedToken);
        return wrappedToken;
    }

    function whitelistMinters(
        address inputToken, 
        address[] calldata accounts, 
        bool[] calldata whitelists
    ) external onlyOwner {
        if (cashWrappedToken[inputToken] == address(0)) revert WrappedTokenDoesntExists();
        CashWrappedERC20(cashWrappedToken[inputToken]).whitelistMinters(accounts, whitelists);
    }

    function whitelistRecipients(
        address inputToken, 
        address[] calldata accounts, 
        bool[] calldata whitelists
    ) external onlyOwner {
        if (cashWrappedToken[inputToken] == address(0)) revert WrappedTokenDoesntExists();
        CashWrappedERC20(cashWrappedToken[inputToken]).whitelistRecipients(accounts, whitelists);
    }
}
