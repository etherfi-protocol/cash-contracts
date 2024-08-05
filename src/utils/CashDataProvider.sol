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
    uint64 private _withdrawalDelay;
    address private _etherFiCashMultiSig;
    address private _etherFiCashDebtManager;

    function intiailize(
        address __owner,
        uint64 __withdrawalDelay,
        address __etherFiCashMultiSig,
        address __etherFiCashDebtManager
    ) external initializer {
        __Ownable_init(__owner);
        _withdrawalDelay = __withdrawalDelay;
        _etherFiCashMultiSig = __etherFiCashMultiSig;
        _etherFiCashDebtManager = __etherFiCashDebtManager;
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
    function setWithdrawalDelay(uint64 delay) external onlyOwner {
        if (delay == 0) revert InvalidValue();
        emit WithdrawalDelayUpdated(_withdrawalDelay, delay);
        _withdrawalDelay = delay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiCashMultiSig(address cashMultiSig) external onlyOwner {
        if (cashMultiSig == address(0)) revert InvalidValue();

        emit CashMultiSigUpdated(_etherFiCashMultiSig, cashMultiSig);
        _etherFiCashMultiSig = cashMultiSig;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiCashDebtManager(
        address cashDebtManager
    ) external onlyOwner {
        if (cashDebtManager == address(0)) revert InvalidValue();

        emit CashDebtManagerUpdated(_etherFiCashDebtManager, cashDebtManager);
        _etherFiCashDebtManager = cashDebtManager;
    }
}
