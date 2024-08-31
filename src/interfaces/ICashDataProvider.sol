// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICashDataProvider {
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event EtherFiWalletUpdated(address oldWallet, address newWallet);
    event CashMultiSigUpdated(address oldMultiSig, address newMultiSig);
    event UsdcAddressUpdated(address oldUsdc, address newUsdc);
    event WeETHAddressUpdated(address OldWeETH, address newWeETH);
    event PriceProviderUpdated(
        address oldPriceProvider,
        address newPriceProvider
    );
    event SwapperUpdated(address oldSwapper, address newSwapper);
    event EtherFiRecoverySafeUpdated(address oldSafe, address newSafe);
    event AaveAdapterUpdated(address oldAdapter, address newAdapter);
    event CollateralTokenAdded(address token);
    event BorrowTokenAdded(address token);

    error InvalidValue();
    error AlreadyCollateralToken();
    error AlreadyBorrowToken();

    /**
     * @notice Function to fetch the timelock delay for tokens from User Safe
     * @return Timelock delay in seconds
     */
    function delay() external view returns (uint64);

    /**
     * @notice Function to fetch the address of the EtherFi Cash wallet
     * @notice Only this wallet should be able to pull funds from User Safe
     * @return EtherFi Cash wallet address
     */
    function etherFiWallet() external view returns (address);

    /**
     * @notice Function to fetch the address of the EtherFi Cash MultiSig wallet
     * @return EtherFi Cash MultiSig wallet address
     */
    function etherFiCashMultiSig() external view returns (address);

    /**
     * @notice Function to fetch the array of addresses of all collateral tokens
     * @return array of addresses of all collateral tokens
     */
    function collateralTokens() external view returns (address[] memory);

    /**
     * @notice Function to fetch the array of addresses of all borrow tokens
     * @return array of addresses of all borrow tokens
     */
    function borrowTokens() external view returns (address[] memory);

    /**
     * @notice Function to fetch the address of the Price Provider contract
     * @return Price Provider contract address
     */
    function priceProvider() external view returns (address);

    /**
     * @notice Function to fetch the address of the Swapper contract
     * @return Swapper contract address
     */
    function swapper() external view returns (address);

    /**
     * @notice Function to fetch the address of the Aave adapter
     * @return Aave adapter address
     */
    function aaveAdapter() external view returns (address);

    /**
     * @notice Function to set the timelock delay for tokens from User Safe
     * @dev Can only be called by the owner of the contract
     * @param delay Timelock delay in seconds
     */
    function setDelay(uint64 delay) external;

    /**
     * @notice Function to check whether a token is a collateral token
     * @return Boolean value suggesting if token is a collateral token
     */
    function isCollateralToken(address token) external view returns (bool);

    /**
     * @notice Function to check whether a token is a borrow token
     * @return Boolean value suggesting if token is a borrow token
     */
    function isBorrowToken(address token) external view returns (bool);

    /**
     * @notice Function to add support for a new collateral token
     * @dev Can only be called by the owner of the contract
     * @param tokens Array of addresses of the token to be supported as collateral
     */
    function supportCollateralToken(address[] memory tokens) external;

    /**
     * @notice Function to add support for a new borrow token
     * @dev Can only be called by the owner of the contract
     * @param tokens Array of addresses of the token to be supported as debt
     */
    function supportBorrowToken(address[] memory tokens) external;

    /**
     * @notice Function to set the address of the EtherFi wallet
     * @dev Can only be called by the owner of the contract
     * @param wallet EtherFi Cash wallet address
     */
    function setEtherFiWallet(address wallet) external;

    /**
     * @notice Function to set the address of the EtherFi Cash MultiSig wallet
     * @dev Can only be called by the owner of the contract
     * @param cashMultiSig EtherFi Cash MultiSig wallet address
     */
    function setEtherFiCashMultiSig(address cashMultiSig) external;

    /**
     * @notice Function to set the address of PriceProvider contract
     * @dev Can only be called by the owner of the contract
     * @param priceProvider PriceProvider contract address
     */
    function setPriceProvider(address priceProvider) external;

    /**
     * @notice Function to set the address of Swapper contract
     * @dev Can only be called by the owner of the contract
     * @param swapper Swapper contract address
     */
    function setSwapper(address swapper) external;

    /**
     * @notice Function to set the address of the Aave adapter
     * @dev Can only be called by the owner of the contract
     * @param adapter Aave adapter address
     */
    function setAaveAdapter(address adapter) external;
}
