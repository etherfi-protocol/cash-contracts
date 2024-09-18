// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CashTokenWrapperFactory} from "../cash-wrapper-token/CashTokenWrapperFactory.sol";
import {MockCashWrappedERC20, CashWrappedERC20} from "./MockCashWrappedERC20.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockCashTokenWrapperFactory is CashTokenWrapperFactory {
    constructor(address _implementation, address _owner) CashTokenWrapperFactory(_implementation, _owner) {}

    function setWrappedTokenAddress(address inputToken, address wrappedToken) external onlyOwner {
        cashWrappedToken[inputToken] =  wrappedToken;
    }

    function deployWrapper(address inputToken) external override onlyOwner returns (address) {
        if (cashWrappedToken[inputToken] != address(0)) revert WrappedTokenAlreadyExists();
        bytes memory data = abi.encodeWithSelector(
            CashWrappedERC20.initialize.selector, 
            inputToken, 
            string(abi.encodePacked("eCash ", IERC20Metadata(inputToken).name())),
            string(abi.encodePacked("ec", IERC20Metadata(inputToken).symbol())),
            MockCashWrappedERC20(inputToken).decimals()
        );

        address wrappedToken = address(new BeaconProxy(address(this), data));
        cashWrappedToken[inputToken] = wrappedToken;
        
        emit WrappedTokenDeployed(wrappedToken);
        return wrappedToken;
    }

}