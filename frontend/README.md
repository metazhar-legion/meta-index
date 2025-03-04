# Web3 Index Fund Frontend

This is the frontend application for the Web3 Index Fund project, a decentralized, DAO-governed index fund built on the ERC4626 vault standard. The application provides a user interface for interacting with the smart contracts, allowing users to deposit assets, withdraw shares, manage the index composition, and more.

## Overview

The frontend is built with React, TypeScript, and Material UI, providing a modern, responsive interface with a dark mode theme. It integrates with Ethereum wallets through Web3React and ethers.js, allowing users to interact with the smart contracts directly from their browser.

## Features

### User Roles

The application supports three different user roles, each with its own dashboard and functionality:

1. **Investor** - For users who want to deposit assets and invest in the index fund
2. **DAO Member** - For users who participate in governance and manage the index composition
3. **Portfolio Manager** - For administrators who manage the vault parameters and perform maintenance operations

### Pages and Functionality

#### Landing Page

- **Connect Wallet** - Allows users to connect their Ethereum wallet
- **Role Selection** - After connecting, users can select their role (Investor, DAO Member, or Portfolio Manager)

#### Investor Dashboard

- **Vault Statistics** - Displays total assets, total shares, share price, and user's position
- **Index Composition** - Shows the current tokens in the index and their weights
- **Deposit** - Allows users to deposit assets into the vault
- **Withdraw** - Allows users to withdraw assets by redeeming shares

#### DAO Member Dashboard

- **Index Composition** - Shows the current tokens in the index and their weights
- **Manage Index** - Interface for adding, updating, and removing tokens from the index
- **Future Features** - Placeholder for upcoming governance features

#### Portfolio Manager Dashboard

- **Vault Statistics** - Displays total assets, total shares, and share price
- **Index Composition** - Shows the current tokens in the index and their weights
- **Portfolio Actions** - Interface for rebalancing the portfolio and collecting fees
- **Configuration** - Controls for setting management and performance fees, price oracle, and DEX addresses

## Getting Started

### Prerequisites

- Node.js (v14 or later)
- npm or yarn
- MetaMask or another Ethereum wallet browser extension

### Installation

1. Clone the repository
2. Navigate to the frontend directory
3. Install dependencies:

```bash
npm install
```

### Running the Application

Start the development server:

```bash
npm start
```

This will launch the application at [http://localhost:3000](http://localhost:3000).

## Testing Scenarios

### Setup

Before testing, make sure you have:

1. MetaMask installed and configured with test accounts
2. The smart contracts deployed to a local blockchain or testnet
3. Updated the contract addresses in `src/hooks/useContracts.ts`

### Scenario 1: Investor Workflow

1. **Connect Wallet**:
   - Click the "Connect Wallet" button in the top-right corner
   - Approve the connection in MetaMask

2. **Select Investor Role**:
   - Click on the "Investor" role in the role selector

3. **View Index Composition**:
   - Examine the tokens and their weights in the index

4. **Deposit Assets**:
   - Ensure you have some tokens in your wallet that match the asset of the vault
   - Enter an amount in the deposit field
   - Click "Deposit"
   - Approve the token spending in MetaMask
   - Confirm the transaction

5. **Check Position**:
   - After the transaction is confirmed, verify that your shares and assets value are updated

6. **Withdraw Assets**:
   - Enter the number of shares to redeem in the withdraw tab
   - Click "Withdraw"
   - Confirm the transaction in MetaMask
   - Verify that your shares and assets are updated after the transaction

### Scenario 2: DAO Member Workflow

1. **Connect Wallet and Select DAO Member Role**

2. **View Current Index Composition**:
   - Check the current tokens and weights

3. **Add a New Token**:
   - Enter a valid ERC20 token address
   - Enter a weight (e.g., 1.0)
   - Click "Add Token"
   - Confirm the transaction in MetaMask
   - Verify the token appears in the index composition after the transaction

4. **Update Token Weight**:
   - Enter an existing token address
   - Enter a new weight
   - Click "Update Weight"
   - Confirm the transaction
   - Verify the weight is updated in the index composition

5. **Remove Token**:
   - Enter an existing token address
   - Click "Remove Token"
   - Confirm the transaction
   - Verify the token is removed from the index composition

### Scenario 3: Portfolio Manager Workflow

1. **Connect Wallet and Select Portfolio Manager Role**

2. **Rebalance Portfolio**:
   - Click the "Rebalance" button
   - Confirm the transaction
   - Verify the portfolio is rebalanced according to the target weights

3. **Collect Fees**:
   - Click "Collect" next to Management Fee or Performance Fee
   - Confirm the transaction
   - Verify the fees are collected

4. **Update Fee Structure**:
   - Enter a new management fee percentage (e.g., 2.0)
   - Click "Set Management Fee"
   - Confirm the transaction
   - Repeat for performance fee

5. **Update Infrastructure**:
   - Enter a new price oracle address
   - Click "Set Price Oracle"
   - Confirm the transaction
   - Repeat for DEX address

## Troubleshooting

### Common Issues

1. **Wallet Connection Issues**:
   - Make sure MetaMask is installed and unlocked
   - Try refreshing the page
   - Check that you're on the correct network

2. **Transaction Failures**:
   - Check the console for error messages
   - Ensure you have enough ETH for gas
   - Verify contract addresses are correct

3. **Data Not Loading**:
   - Check network connectivity
   - Verify contract addresses in the code
   - Make sure the contracts are deployed and initialized

## Building for Production

To create a production build:

```bash
npm run build
```

This will generate optimized files in the `build` directory that can be deployed to any static hosting service.

## Available Scripts

### `npm start`

Runs the app in the development mode.\
Open [http://localhost:3000](http://localhost:3000) to view it in the browser.

### `npm test`

Launches the test runner in the interactive watch mode.

### `npm run build`

Builds the app for production to the `build` folder.

## Learn More

You can learn more in the [Create React App documentation](https://facebook.github.io/create-react-app/docs/getting-started).

To learn React, check out the [React documentation](https://reactjs.org/).
