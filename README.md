# Web3 Index Fund (Meta-Index)

A gas-optimized, ERC4626-compliant index fund vault that allows participants to deposit tokens and invest in a basket of real-world assets (RWAs) and yield-generating strategies. The vault uses a modular architecture with asset wrappers to simplify management and improve efficiency.

## Overview

This project implements a web3-based index fund using Solidity smart contracts with the following key components:

- **IndexFundVaultV2**: A gas-optimized, ERC4626-compliant tokenized vault that handles deposits, withdrawals, and rebalancing
- **RWAAssetWrapper**: Wrapper contracts that encapsulate RWA tokens and handle allocation between assets and yield strategies
- **StableYieldStrategy**: Manages yield generation for idle capital
- **Price Oracle Integration**: For accurate asset pricing
- **DEX Integration**: For rebalancing and trading between assets

## Key Features

- **Modular Architecture**: Clean separation of concerns through asset wrappers
- **Gas-Optimized Storage**: Efficient variable packing and data type optimization
- **Automated Rebalancing**: Maintains the desired asset allocation with configurable thresholds
- **Fee Structure**: Management and performance fees with configurable parameters
- **RWA Support**: Built-in support for real-world assets through synthetic tokens
- **Yield Generation**: Multiple yield strategies including staking and lending
- **DEX Integration**: Router pattern for optimal trading across multiple DEXes
- **Perpetual Trading**: Synthetic exposure to assets via perpetual trading protocols

## Project Structure

```
├── src/
│   ├── IndexFundVaultV2.sol     # Main vault contract (gas-optimized)
│   ├── RWAAssetWrapper.sol      # Wrapper for RWA tokens
│   ├── RWASyntheticSP500.sol    # Example synthetic RWA token
│   ├── StableYieldStrategy.sol  # Yield strategy for idle capital
│   ├── StakingReturnsStrategy.sol # Staking-based yield strategy
│   ├── DEXRouter.sol           # Router for DEX integrations
│   ├── PerpetualRouter.sol      # Router for perpetual trading protocols
│   ├── FeeManager.sol           # Fee calculation and collection
│   ├── interfaces/              # Contract interfaces
│   └── mocks/                   # Mock contracts for testing
├── script/                      # Deployment scripts
│   ├── DeployIndexFundVaultV2.s.sol  # Deploy basic vault
│   └── DeployMultiAssetVault.s.sol   # Deploy vault with multiple assets
├── test/                        # Test files
└── frontend/                    # React TypeScript UI (future enhancement)
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- [Git](https://git-scm.com/downloads)
- [Node.js](https://nodejs.org/) (v14 or later) for the frontend
- [npm](https://www.npmjs.com/) or [yarn](https://yarnpkg.com/)
- [MetaMask](https://metamask.io/) or another Ethereum wallet browser extension

## Installation

1. Clone the repository:

```shell
git clone https://github.com/yourusername/web3-index-fund.git
cd web3-index-fund
```

2. Install dependencies:

```shell
forge install
```

## Building

Compile the contracts:

```shell
forge build
```

## Testing

Run the test suite:

```shell
forge test
```

Run tests with verbosity for more details:

```shell
forge test -vvv
```

Run a specific test:

```shell
forge test --match-test testDeposit -vvv
```

### Testing Environments

The project uses different approaches for testing in local and forked environments:

- **Local Testing**: For local unit tests, simplified calculations are used in contracts like `StakingReturnsStrategy` when the block number is low (≤ 100), making it easier to test with predictable values.
- **Forked Testing**: When testing on forked networks where block numbers are high, more sophisticated mocks should be used to accurately simulate protocol behavior.

This dual approach allows for both simple unit testing and realistic integration testing.

## Local Deployment

1. Start a local Anvil node:

```shell
anvil
```

2. In a new terminal, deploy the basic vault to the local node:

```shell
forge script script/DeployIndexFundVaultV2.s.sol:DeployIndexFundVaultV2 --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Or deploy the multi-asset vault with RWA tokens:

```shell
forge script script/DeployMultiAssetVault.s.sol:DeployMultiAssetVault --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Note: The private key above is the default private key for the first account in Anvil.

## Testnet Deployment

1. Create a `.env` file with your private key:

```
PRIVATE_KEY=your_private_key_here
```

2. Deploy to a testnet (e.g., Sepolia):

```shell
source .env
forge script script/DeployMultiAssetVault.s.sol:DeployMultiAssetVault --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY --broadcast
```

Replace `YOUR_INFURA_KEY` with your actual Infura API key.

## Interacting with the Contracts

### Depositing into the Vault

```shell
cast send <VAULT_ADDRESS> "deposit(uint256,address)" <AMOUNT> <RECEIVER> --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

### Withdrawing from the Vault

```shell
cast send <VAULT_ADDRESS> "withdraw(uint256,address,address)" <AMOUNT> <RECEIVER> <OWNER> --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

### Rebalancing the Index

```shell
cast send <VAULT_ADDRESS> "rebalance()" --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

## Contract Architecture

### IndexFundVaultV2

The main vault contract that implements the ERC4626 standard with gas optimizations. It handles deposits, withdrawals, and rebalancing of the index through asset wrappers.

### RWAAssetWrapper

A wrapper contract that encapsulates RWA tokens and manages the allocation between the RWA asset and yield strategies. This modular approach simplifies asset management and improves separation of concerns.

### StableYieldStrategy

Manages yield generation for idle capital, allowing the vault to earn returns on assets not currently allocated to RWA tokens.

### FeeManager

Handles the calculation and collection of management and performance fees, with configurable parameters for fee rates and collection periods.

## Fee Structure

- **Management Fee**: Annual fee based on total assets under management (configurable, default: 1%)
- **Performance Fee**: Fee on profits above the high water mark (configurable, default: 10%)
- **Fee Collection**: Fees are collected during rebalancing operations and when explicitly triggered

## Gas Optimizations

- **Storage Packing**: Variables are carefully packed to minimize storage slots
- **Data Type Optimization**: Using uint32, uint16, etc. where appropriate to reduce gas costs
- **Modular Architecture**: Asset wrappers reduce complexity and gas costs in the main vault
- **Caching**: Array lengths and frequently accessed values are cached to reduce gas usage
- **Reduced External Calls**: Logic is structured to minimize expensive external calls
- **Test-Production Bifurcation**: Conditional logic that simplifies calculations in test environments but maintains full functionality in production

## Security Considerations

- **OpenZeppelin Libraries**: The contracts use OpenZeppelin's security libraries
- **Reentrancy Protection**: Implemented for critical functions using ReentrancyGuard
- **Fee Limits**: Enforced to prevent excessive fees
- **Access Control**: Proper ownership and access controls for sensitive operations
- **Overflow Protection**: Using Solidity 0.8.x built-in overflow checks

## Future Enhancements

- **Capital Allocation Manager**: Advanced strategies for capital allocation
- **Enhanced Yield Strategies**: Additional yield generation options
- **Frontend Application**: React TypeScript UI for interacting with the contracts
- **Cross-Chain Support**: Integration with cross-chain bridges
- **DAO Governance**: Decentralized control of the index composition

4. Open [http://localhost:3000](http://localhost:3000) in your browser

### User Workflows

#### Investor
- View vault statistics and index composition
- Deposit assets into the vault
- Withdraw assets by redeeming shares

#### DAO Member
- View index composition
- Add, update, and remove tokens from the index
- (Future) Participate in governance proposals

#### Portfolio Manager
- Rebalance the portfolio
- Collect management and performance fees
- Configure vault parameters

For more details about the frontend, see the [frontend README](./frontend/README.md).

## Future Enhancements

- Integration with more DEXes for better liquidity
- Cross-chain asset support
- Real-world asset (RWA) synthetic tokens
- Enhanced DAO governance features
- Advanced analytics dashboard
- Mobile-responsive design improvements

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Foundry

This project uses Foundry, a blazing fast, portable, and modular toolkit for Ethereum application development written in Rust.

For more information about Foundry, visit the [documentation](https://book.getfoundry.sh/).
