# Frontend Testing Guide

## Overview
This guide will help you deploy the ComposableRWA system and test the frontend functionality.

## Prerequisites

1. **Node.js and npm** installed
2. **Foundry** installed (`forge`, `anvil`)
3. **MetaMask** browser extension installed

## Quick Start

### 1. Start Local Blockchain

In a terminal, start Anvil:
```bash
anvil
```

Keep this terminal running. Anvil will:
- Start a local Ethereum node on `http://localhost:8545`
- Create 10 test accounts with 10,000 ETH each
- Use Chain ID: 31337

### 2. Deploy Contracts and Update Frontend

In a new terminal:
```bash
./deploy-and-update-frontend.sh
```

This script will:
- Deploy the complete ComposableRWA system
- Extract deployed contract addresses
- Automatically update `frontend/src/contracts/addresses.ts`
- Display all deployed addresses

### 3. Start Frontend

```bash
cd frontend
npm install  # Only needed first time
npm start
```

The frontend will start on `http://localhost:3000`

### 4. Configure MetaMask

1. **Add Local Network:**
   - Network Name: `Localhost 8545`
   - RPC URL: `http://localhost:8545`
   - Chain ID: `31337`
   - Currency Symbol: `ETH`

2. **Import Test Account:**
   - Click "Import Account"
   - Paste private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
   - This account has 10,000 ETH for testing

3. **Connect to Frontend:**
   - Open `http://localhost:3000`
   - Click "Connect Wallet"
   - Select the imported account
   - Approve the connection

## Testing Features

### Available User Roles

The frontend supports multiple roles. You can switch between them in the UI:

1. **Investor** - Basic deposit/withdraw functionality
2. **DAO Member** - Governance and index composition
3. **Portfolio Manager** - Advanced rebalancing and fee collection
4. **Composable RWA User** - Full multi-strategy dashboard

### Testing Composable RWA Features

1. **View Dashboard:**
   - Navigate to "Composable RWA" page
   - View multi-strategy exposure breakdown
   - Check performance metrics

2. **Allocate Capital:**
   - Ensure you have USDC (the deployment script mints test USDC)
   - Enter amount to allocate
   - Approve USDC spending
   - Execute allocation across strategies

3. **Strategy Management:**
   - View TRS Strategy details
   - View Perpetual Strategy details
   - View Direct Token Strategy details
   - Monitor real-time costs and exposure

4. **Optimization:**
   - Trigger strategy optimization
   - View cost savings
   - Observe capital reallocation

## Test Scenarios

### Scenario 1: First-Time Investment

```
1. Connect wallet with test account
2. Navigate to Composable RWA page
3. Check USDC balance (should have test tokens)
4. Approve USDC spending (100,000 USDC)
5. Allocate capital (e.g., 10,000 USDC)
6. Verify allocation across strategies
7. Check bundle stats update
```

### Scenario 2: Strategy Optimization

```
1. After allocating capital (Scenario 1)
2. Click "Optimize Strategies"
3. Wait for optimization to complete
4. Observe any rebalancing that occurs
5. Check updated performance metrics
```

### Scenario 3: Withdraw Capital

```
1. After allocating capital
2. Click "Withdraw" or "Exit Position"
3. Enter amount to withdraw
4. Confirm transaction
5. Verify USDC balance increases
```

## Troubleshooting

### Frontend Won't Compile

**Issue:** TypeScript errors about missing contract addresses

**Solution:**
1. Ensure `deploy-and-update-frontend.sh` completed successfully
2. Check `frontend/src/contracts/addresses.ts` has valid addresses (not 0x000...000)
3. If addresses are placeholders, re-run the deployment script

### MetaMask Connection Issues

**Issue:** "Wrong network" or "Cannot connect"

**Solution:**
1. Ensure Anvil is running on port 8545
2. Check MetaMask is connected to "Localhost 8545" network
3. Verify Chain ID is 31337
4. Try resetting MetaMask account (Settings → Advanced → Reset Account)

### Transaction Failures

**Issue:** Transactions fail or revert

**Solution:**
1. Check you have sufficient USDC balance
2. Ensure USDC is approved for the ComposableRWABundle contract
3. Check Anvil terminal for error messages
4. Verify contract addresses in `addresses.ts` match deployed contracts

### "Insufficient Funds" Error

**Issue:** Cannot perform transactions

**Solution:**
1. The test account should have 10,000 ETH by default
2. If running multiple tests, restart Anvil to reset balances
3. For USDC, the deployment script should mint test tokens
4. Check the deployment logs to verify USDC was minted

## Manual Deployment (Alternative)

If the automatic script doesn't work, you can deploy manually:

```bash
# 1. Start Anvil
anvil

# 2. Deploy (in another terminal)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
  --rpc-url http://localhost:8545 \
  --broadcast

# 3. Copy deployed addresses from output
# 4. Manually update frontend/src/contracts/addresses.ts with the addresses
```

## Current Status

✅ **Compilation Issues:** All TypeScript errors resolved
✅ **Contract Addresses:** Placeholder addresses added (will be updated on deployment)
✅ **Deployment Script:** Ready to deploy and auto-update frontend

## Next Steps

1. Run `./deploy-and-update-frontend.sh` to deploy contracts
2. Start frontend with `cd frontend && npm start`
3. Test ComposableRWA features through the UI
4. Report any issues or unexpected behavior

## Additional Resources

- **Smart Contracts:** See `ARCHITECTURE.md` for system design
- **Testing:** See `TESTING_SCENARIOS.md` for contract testing
- **Deployment:** See `deploy-and-test.sh` for complete environment setup

## Support

If you encounter issues not covered in this guide:
1. Check Anvil terminal for blockchain errors
2. Check browser console for frontend errors
3. Check contract deployment logs for address extraction issues
4. Verify all prerequisites are properly installed
