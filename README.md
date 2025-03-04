# Web3 Index Fund

A decentralized ERC4626-compliant index fund vault that allows participants to deposit tokens and invest in a basket of assets. The indices can be voted on by a DAO, but are initially implemented by the vault owner.

## Overview

This project implements a web3-based index fund using Solidity smart contracts with the following key components:

- **ERC4626 Vault**: A standard-compliant tokenized vault that handles deposits, withdrawals, and accounting
- **Index Registry**: Manages the composition of the index (tokens and their weights)
- **DAO Governance**: Allows token holders to vote on index changes (optional)
- **Price Oracle Integration**: For accurate asset pricing
- **DEX Integration**: For rebalancing and trading between assets

## Key Features

- **Automated Rebalancing**: Maintains the desired asset allocation
- **Fee Structure**: Management and performance fees
- **DAO Governance**: Decentralized control of the index composition
- **Cross-Chain Support**: Extensible for cross-chain assets (future enhancement)
- **RWA Support**: Extensible for real-world assets (future enhancement)

## Project Structure

```
├── src/
│   ├── IndexFundVault.sol       # Main vault contract
│   ├── IndexRegistry.sol        # Index composition registry
│   ├── interfaces/              # Contract interfaces
│   └── mocks/                   # Mock contracts for testing
├── script/                      # Deployment scripts
├── test/                        # Test files
└── frontend/                    # React TypeScript UI
    ├── src/
    │   ├── components/          # Reusable UI components
    │   ├── contexts/            # React contexts including Web3Context
    │   ├── hooks/               # Custom hooks for contracts
    │   ├── pages/               # Page components for different user roles
    │   ├── theme/               # UI theme configuration
    │   └── contracts/           # Contract interfaces and ABIs
    └── public/                  # Static assets
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

## Local Deployment

1. Start a local Anvil node:

```shell
anvil
```

2. In a new terminal, deploy the contracts to the local node:

```shell
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Note: The private key above is the default private key for the first account in Anvil.

## Sepolia Testnet Deployment

1. Create a `.env` file with your private key:

```
PRIVATE_KEY=your_private_key_here
```

2. Deploy to Sepolia testnet:

```shell
source .env
forge script script/DeploySepolia.s.sol:DeploySepolia --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY --broadcast
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

### IndexFundVault

The main vault contract that implements the ERC4626 standard. It handles deposits, withdrawals, and rebalancing of the index.

### IndexRegistry

Manages the composition of the index, including token addresses and their weights.

### DAO Governance

Allows token holders to vote on proposals to change the index composition.

## Fee Structure

- **Management Fee**: Annual fee based on total assets under management (default: 1%)
- **Performance Fee**: Fee on profits above the high water mark (default: 10%)

## Security Considerations

- The contracts use OpenZeppelin's security libraries
- Reentrancy protection is implemented for critical functions
- Fee limits are enforced to prevent excessive fees

## Frontend Application

The project includes a React TypeScript frontend that provides a user interface for interacting with the smart contracts.

### Features

- **User Roles**: Support for Investors, DAO Members, and Portfolio Managers
- **Dark Mode UI**: Modern Material UI design with dark mode
- **Wallet Integration**: Connect with MetaMask and other Ethereum wallets
- **Role-Based Dashboards**: Different interfaces for different user types

### Running the Frontend

1. Navigate to the frontend directory:

```shell
cd frontend
```

2. Install dependencies:

```shell
npm install
```

3. Start the development server:

```shell
npm start
```

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
