# ether.fi Cash Smart Contracts

Welcome to the ether.fi Cash Smart Contracts repository! This project powers the ether.fi Cash product, providing seamless debit and credit functionalities for users.

## Overview

ether.fi Cash allows users to manage their funds through two primary mechanisms:

- **Debit:** Users spend their own funds via the ether.fi card, with transactions flowing directly from their UserSafe contracts to the ether.fi Cash multisig wallet.
- **Credit:** Users can borrow funds by supplying collateral to the ether.fi Debt Manager. These funds are available for spending with the ether.fi card, much like a traditional credit card, but backed by the user's collateral.

## Key Contracts

The project comprises several smart contracts that ensure secure and efficient handling of user funds, collateral, and borrowing. Some of the main components include:

- **UserSafe**: Manages user-owned assets and permissions.
- **L2DebtManager**: Handles collateral and debt management for credit flows.
- **PriceProvider**: Supplies price data for collateral valuation.
- **SignatureUtils**: Manages signature verification, including WebAuthn support.

## Get Started

To deploy and interact with these smart contracts, clone the repository and follow the build and test instructions provided below.

### Clone the repository

```shell
git clone https://github.com/etherfi-protocol/cash-contracts
```

### Install dependencies

```shell
yarn
```

### Build the repo

```shell
yarn build
```

### Test

```shell
yarn test
```

## Security

The contracts are designed with security in mind, incorporating features like spending limits, delayed withdrawals, and recovery mechanisms.
