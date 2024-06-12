## Project Requirements
 **NFT minting with n functions (for n tiers):**
  - Number of tiers, price per tier, and total supply per tier can be configured during the construction of the contract.
  - Every tier has a total supply.
  - Tiers determine the order for NFT minting IDs:
    - First tier 1 minted -> NFT ID 1.
    - Assuming 10 total supply for tier 1, first tier 2 minted -> NFT ID 11.

- **Upgrading and Downgrading:**
  - Upgrading is not possible. Minting gives you the NFT, you can sell it and mint a different one if you need to.
  - Downgrading or cancelling the order is not possible.

- **Payment and Funds:**
  - Funds are sent to a company Gnosis Safe (the owner) after every mint.
  - Pulling locked funds (ERC20 tokens and ETH) should be possible for the owner.
  - Payment can be made in ETH and eETH (preferably with a permit signature instead of approval).

- **Security and Usability:**
  - Fallback function reverts to prevent people from randomly sending funds.
  - Ensure that Gnosis Safes can call the mint functions and a Gnosis Safe can be an owner of the smart contract.

- **Deployment and Trading:**
  - Contract will be deployed on Mainnet; ensure gas is realistic for minting.
  - Trading of the NFT should be possible on Opensea.
## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
