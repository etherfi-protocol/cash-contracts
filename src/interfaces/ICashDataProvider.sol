// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICashDataProvider {
    event WithdrawalDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event CashMultiSigUpdated(address oldMultiSig, address newMultiSig);
    event CashDebtManagerUpdated(
        address oldDebtManager,
        address newDebtManager
    );

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
    function etherFiCashMultiSig(address cashMultiSig) external;

    /**
     * @notice Function to set the address of the EtherFi Cash Debt Manager contract
     * @dev Can only be called by the owner of the contract
     * @param cashDebtManager EtherFi Cash Debt Manager contract address
     */
    function etherFiCashDebtManager(address cashDebtManager) external;
}
