// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICashDataProvider} from "../interfaces/ICashDataProvider.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title CashDataProvider
 * @author ether.fi [shivam@ether.fi]
 * @notice Contract which stores necessary data required for Cash contracts
 */
contract CashDataProvider is
    ICashDataProvider,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    // Withdrawal delay
    uint64 private _withdrawalDelay;
    // Address of the Cash MultiSig
    address private _etherFiCashMultiSig;
    // Address of the Cash Debt Manager
    address private _etherFiCashDebtManager;
    // Address of the USDC token
    address private _usdc;
    // Address of the weETH token
    address private _weETH;
    // Address of the price provider
    address private _priceProvider;
    // Address of the swapper
    address private _swapper;

    function intiailize(
        address __owner,
        uint64 __withdrawalDelay,
        address __etherFiCashMultiSig,
        address __etherFiCashDebtManager,
        address __usdc,
        address __weETH,
        address __priceProvider,
        address __swapper
    ) external initializer {
        __Ownable_init(__owner);
        _withdrawalDelay = __withdrawalDelay;
        _etherFiCashMultiSig = __etherFiCashMultiSig;
        _etherFiCashDebtManager = __etherFiCashDebtManager;
        _usdc = __usdc;
        _weETH = __weETH;
        _priceProvider = __priceProvider;
        _swapper = __swapper;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @inheritdoc ICashDataProvider
     */
    function withdrawalDelay() external view returns (uint64) {
        return _withdrawalDelay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiCashMultiSig() external view returns (address) {
        return _etherFiCashMultiSig;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiCashDebtManager() external view returns (address) {
        return _etherFiCashDebtManager;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function usdc() external view returns (address) {
        return _usdc;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function weETH() external view returns (address) {
        return _weETH;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function priceProvider() external view returns (address) {
        return _priceProvider;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function swapper() external view returns (address) {
        return _swapper;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setWithdrawalDelay(uint64 delay) external onlyOwner {
        if (delay == 0) revert InvalidValue();
        emit WithdrawalDelayUpdated(_withdrawalDelay, delay);
        _withdrawalDelay = delay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setEtherFiCashMultiSig(address cashMultiSig) external onlyOwner {
        if (cashMultiSig == address(0)) revert InvalidValue();

        emit CashMultiSigUpdated(_etherFiCashMultiSig, cashMultiSig);
        _etherFiCashMultiSig = cashMultiSig;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setEtherFiCashDebtManager(
        address cashDebtManager
    ) external onlyOwner {
        if (cashDebtManager == address(0)) revert InvalidValue();

        emit CashDebtManagerUpdated(_etherFiCashDebtManager, cashDebtManager);
        _etherFiCashDebtManager = cashDebtManager;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setUsdcAddress(address usdcAddr) external onlyOwner {
        if (_usdc == address(0)) revert InvalidValue();
        emit UsdcAddressUpdated(_usdc, usdcAddr);
        _usdc = usdcAddr;
    }
    /**
     * @inheritdoc ICashDataProvider
     */
    function setWeETHAddress(address weETHAddr) external onlyOwner {
        if (_weETH == address(0)) revert InvalidValue();
        emit WeETHAddressUpdated(_weETH, weETHAddr);
        _weETH = weETHAddr;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setPriceProvider(address priceProviderAddr) external onlyOwner {
        if (_priceProvider == address(0)) revert InvalidValue();
        emit PriceProviderUpdated(_priceProvider, priceProviderAddr);
        _priceProvider = priceProviderAddr;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setSwapper(address swapperAddr) external onlyOwner {
        if (_swapper == address(0)) revert InvalidValue();
        emit SwapperUpdated(_swapper, swapperAddr);
        _swapper = swapperAddr;
    }
}
