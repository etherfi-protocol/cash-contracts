// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICashDataProvider {
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event SettlementDispatcherUpdated(address oldDispatcher, address newDispatcher);
    event CashDebtManagerUpdated(
        address oldDebtManager,
        address newDebtManager
    );
    event PriceProviderUpdated(
        address oldPriceProvider,
        address newPriceProvider
    );
    event SwapperUpdated(address oldSwapper, address newSwapper);
    event AaveAdapterUpdated(address oldAdapter, address newAdapter);
    event UserSafeFactoryUpdated(address oldFactory, address newFactory);
    event UserSafeWhitelisted(address userSafe);
    event EtherFiWalletAdded(address wallet);
    event EtherFiWalletRemoved(address wallet);

    error InvalidValue();
    error OnlyUserSafeFactory();
    error AlreadyAWhitelistedEtherFiWallet();
    error NotAWhitelistedEtherFiWallet();

    /**
     * @notice Function to fetch the timelock delay for tokens from User Safe
     * @return Timelock delay in seconds
     */
    function delay() external view returns (uint64);

    /**
     * @notice Function to check whether a wallet has the ETHER_FI_WALLET_ROLE
     * @return bool suggesting whether it is an EtherFi Wallet
     */
    function isEtherFiWallet(address wallet) external view returns (bool);

    /**
     * @notice Function to fetch the address of the Settlement Dispatcher contract
     * @return Settlement Dispatcher contract address
     */
    function settlementDispatcher() external view returns (address);

    /**
     * @notice Function to fetch the address of the EtherFi Cash Debt Manager contract
     * @return EtherFi Cash Debt Manager contract address
     */
    function etherFiCashDebtManager() external view returns (address);

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
     * @notice Function to fetch the address of the user safe factory
     * @return Address of the user safe factory
     */
    function userSafeFactory() external view returns (address);

    /**
     * @notice Function to check if an account is a user safe
     * @param account Address of the account
     * @return isUserSafe 
     */
    function isUserSafe(address account) external view returns (bool);


    /**
     * @notice Function to set the timelock delay for tokens from User Safe
     * @dev Can only be called by the admin of the contract
     * @param delay Timelock delay in seconds
     */
    function setDelay(uint64 delay) external;

    /**
     * @notice Function to grant ETHER_FI_WALLER_ROLE to an address
     * @dev Can only be called by the admin of the contract
     * @param wallet EtherFi Cash wallet address
     */
    function grantEtherFiWalletRole(address wallet) external;
    
    /**
     * @notice Function to revoke ETHER_FI_WALLER_ROLE to an address
     * @dev Can only be called by the admin of the contract
     * @param wallet EtherFi Cash wallet address
     */
    function revokeEtherFiWalletRole(address wallet) external;

    /**
     * @notice Function to set the address of the Settlement Dispatcher contract
     * @dev Can only be called by the admin of the contract
     * @param dispatcher Settlement Dispatcher contract address
     */
    function setSettlementDispatcher(address dispatcher) external;

    /**
     * @notice Function to set the address of the EtherFi Cash Debt Manager contract
     * @dev Can only be called by the admin of the contract
     * @param cashDebtManager EtherFi Cash Debt Manager contract address
     */
    function setEtherFiCashDebtManager(address cashDebtManager) external;

    /**
     * @notice Function to set the address of PriceProvider contract
     * @dev Can only be called by the admin of the contract
     * @param priceProvider PriceProvider contract address
     */
    function setPriceProvider(address priceProvider) external;

    /**
     * @notice Function to set the address of Swapper contract
     * @dev Can only be called by the admin of the contract
     * @param swapper Swapper contract address
     */
    function setSwapper(address swapper) external;

    /**
     * @notice Function to set the address of the Aave adapter
     * @dev Can only be called by the admin of the contract
     * @param adapter Aave adapter address
     */
    function setAaveAdapter(address adapter) external;

    /**
     * @notice Function to set the addrss of the user safe factory.
     * @param factory Address of the new factory
     */
    function setUserSafeFactory(address factory) external;
    
    /**
     * @notice Function to whitelist user safes
     * @notice Can only be called by the user safe factory
     * @param safe Address of the safe
     */
    function whitelistUserSafe(address safe) external;    
}