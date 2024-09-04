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
    // Delay for timelock
    uint64 private _delay;
    // Address of the Cash Wallet
    address private _etherFiWallet;
    // Address of the Cash MultiSig
    address private _etherFiCashMultiSig;
    // Address of the price provider
    address private _priceProvider;
    // Address of the swapper
    address private _swapper;
    // Address of aave adapter
    address private _aaveAdapter;

    address[] private _collateralTokens;
    address[] private _borrowTokens;
    mapping(address token => uint256 index)
        private _collateralTokenIndexPlusOne;
    mapping(address token => uint256 index) private _borrowTokenIndexPlusOne;

    function intiailize(
        address __owner,
        uint64 __delay,
        address __etherFiWallet,
        address __etherFiCashMultiSig,
        address __priceProvider,
        address __swapper,
        address __aaveAdapter,
        address[] memory __collateralTokens,
        address[] memory __borrowTokens
    ) external initializer {
        __Ownable_init(__owner);
        _delay = __delay;
        _etherFiWallet = __etherFiWallet;
        _etherFiCashMultiSig = __etherFiCashMultiSig;
        _priceProvider = __priceProvider;
        _swapper = __swapper;
        _aaveAdapter = __aaveAdapter;

        uint256 len = __collateralTokens.length;
        for (uint256 i = 0; i < len; ) {
            _supportCollateralToken(__collateralTokens[i]);
            unchecked {
                ++i;
            }
        }

        len = __borrowTokens.length;
        for (uint256 i = 0; i < len; ) {
            _supportBorrowToken(__borrowTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function delay() external view returns (uint64) {
        return _delay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function etherFiWallet() external view returns (address) {
        return _etherFiWallet;
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
    function collateralTokens() external view returns (address[] memory) {
        return _collateralTokens;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function borrowTokens() external view returns (address[] memory) {
        return _borrowTokens;
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
    function aaveAdapter() external view returns (address) {
        return _aaveAdapter;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function isCollateralToken(address token) external view returns (bool) {
        return _collateralTokenIndexPlusOne[token] != 0;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function isBorrowToken(address token) public view returns (bool) {
        return _borrowTokenIndexPlusOne[token] != 0;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function supportCollateralToken(address token) public onlyOwner {
        _supportCollateralToken(token);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function unsupportCollateralToken(address token) external onlyOwner {
        _removeFromArray(
            _collateralTokens,
            _collateralTokenIndexPlusOne,
            token
        );
        emit CollateralTokenRemoved(token);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function supportBorrowToken(address token) public onlyOwner {
        _supportBorrowToken(token);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function unsupportBorrowToken(address token) external onlyOwner {
        _removeFromArray(_borrowTokens, _borrowTokenIndexPlusOne, token);
        emit BorrowTokenRemoved(token);
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setDelay(uint64 __delay) external onlyOwner {
        if (__delay == 0) revert InvalidValue();
        emit DelayUpdated(_delay, __delay);
        _delay = __delay;
    }

    /**
     * @inheritdoc ICashDataProvider
     */
    function setEtherFiWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert InvalidValue();

        emit EtherFiWalletUpdated(_etherFiWallet, wallet);
        _etherFiWallet = wallet;
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

    /**
     * @inheritdoc ICashDataProvider
     */
    function setAaveAdapter(address adapter) external onlyOwner {
        if (adapter == address(0)) revert InvalidValue();
        emit AaveAdapterUpdated(_aaveAdapter, adapter);
        _aaveAdapter = adapter;
    }

    function _supportCollateralToken(address token) internal {
        if (token == address(0)) revert InvalidValue();

        if (_collateralTokenIndexPlusOne[token] != 0)
            revert AlreadyCollateralToken();

        _collateralTokens.push(token);
        _collateralTokenIndexPlusOne[token] = _collateralTokens.length;

        emit CollateralTokenAdded(token);
    }

    function _supportBorrowToken(address token) internal {
        if (token == address(0)) revert InvalidValue();

        if (_borrowTokenIndexPlusOne[token] != 0) revert AlreadyBorrowToken();

        _borrowTokens.push(token);
        _borrowTokenIndexPlusOne[token] = _borrowTokens.length;

        emit BorrowTokenAdded(token);
    }

    function _removeFromArray(
        address[] storage tokens,
        mapping(address token => uint256 indexPlusOne) storage indexPlusOne,
        address tokenToBeRemoved
    ) internal {
        if (tokenToBeRemoved == address(0)) revert InvalidValue();

        uint256 indexPlusOneForTokenToBeRemoved = indexPlusOne[
            tokenToBeRemoved
        ];

        if (indexPlusOneForTokenToBeRemoved == 0) revert NotASupportedToken();

        uint256 len = tokens.length;
        if (len == 1) revert ArrayBecomesEmptyAfterRemoval();

        indexPlusOne[tokens[len - 1]] = indexPlusOneForTokenToBeRemoved;

        tokens[indexPlusOneForTokenToBeRemoved - 1] = tokens[len - 1];

        tokens.pop();
        delete indexPlusOne[tokenToBeRemoved];
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
