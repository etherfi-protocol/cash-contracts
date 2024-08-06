// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICashDataProvider {
    event WithdrawalDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event CashMultiSigUpdated(address oldMultiSig, address newMultiSig);
    event CashDebtManagerUpdated(
        address oldDebtManager,
        address newDebtManager
    );
    event UsdcAddressUpdated(address oldUsdc, address newUsdc);
    event WeETHAddressUpdated(address OldWeETH, address newWeETH);
    event PriceProviderUpdated(
        address oldPriceProvider,
        address newPriceProvider
    );
    event SwapperUpdated(address oldSwapper, address newSwapper);

    error InvalidValue();

    /**
     * @notice Function to fetch the withdrawal delay for tokens from User Safe
     * @return Withdrawal delay in seconds
     */
    function withdrawalDelay() external view returns (uint64);

    /**
     * @notice Function to fetch the address of the EtherFi Cash MultiSig wallet
     * @return EtherFi Cash MultiSig wallet address
     */
    function etherFiCashMultiSig() external view returns (address);

    /**
     * @notice Function to fetch the address of the EtherFi Cash Debt Manager contract
     * @return EtherFi Cash Debt Manager contract address
     */
    function etherFiCashDebtManager() external view returns (address);

    /**
     * @notice Function to fetch the address of the USDC contract
     * @return USDC contract address
     */
    function usdc() external view returns (address);

    /**
     * @notice Function to fetch the address of the weETH contract
     * @return weETH contract address
     */ function weETH() external view returns (address);

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
     * @notice Function to set the withdrawal delay for tokens from User Safe
     * @dev Can only be called by the owner of the contract
     * @param delay Delay in seconds
     */
    function setWithdrawalDelay(uint64 delay) external;

    /**
     * @notice Function to set the address of the EtherFi Cash MultiSig wallet
     * @dev Can only be called by the owner of the contract
     * @param cashMultiSig EtherFi Cash MultiSig wallet address
     */
    function setEtherFiCashMultiSig(address cashMultiSig) external;

    /**
     * @notice Function to set the address of the EtherFi Cash Debt Manager contract
     * @dev Can only be called by the owner of the contract
     * @param cashDebtManager EtherFi Cash Debt Manager contract address
     */
    function setEtherFiCashDebtManager(address cashDebtManager) external;

    /**
     * @notice Function to set the address of USDC
     * @dev Can only be called by the owner of the contract
     * @param usdc USDC contract address
     */
    function setUsdcAddress(address usdc) external;

    /**
     * @notice Function to set the address of weETH
     * @dev Can only be called by the owner of the contract
     * @param weETH weETH contract address
     */
    function setWeETHAddress(address weETH) external;

    /**
     * @notice Function to set the address of PriceProvider contract
     * @dev Can only be called by the owner of the PriceProvider contract
     * @param priceProvider PriceProvider contract address
     */
    function setPriceProvider(address priceProvider) external;

    /**
     * @notice Function to set the address of Swapper contract
     * @dev Can only be called by the owner of the Swapper contract
     * @param swapper Swapper contract address
     */ function setSwapper(address swapper) external;
}
