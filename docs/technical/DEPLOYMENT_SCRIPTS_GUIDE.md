# Deployment Scripts Guide

This document explains the different deployment scripts and when to use each one.

## Available Scripts

### 1. `run.sh` - **RECOMMENDED for Development**

**What it does:**
- ✅ Starts Anvil local blockchain
- ✅ Deploys ComposableRWA system
- ✅ Extracts and updates frontend addresses **automatically**
- ✅ Mints USDC to test accounts
- ✅ Starts frontend development server
- ✅ Keeps everything running until you stop it (Ctrl+C)

**Use when:**
- You want a one-command development environment
- You want seamless testing with automatic address updates
- You're testing the frontend

**Usage:**
```bash
./run.sh
```

**What you get:**
- Anvil running on http://localhost:8545
- Frontend running on http://localhost:3000
- All contract addresses automatically updated in `frontend/src/contracts/addresses.ts`
- Test accounts funded with ETH and USDC

---

### 2. `deploy-and-test.sh` - Complete Setup with Testing

**What it does:**
- ✅ Starts Anvil local blockchain
- ✅ Builds smart contracts
- ✅ Runs contract tests
- ✅ Deploys ComposableRWA system
- ✅ Extracts addresses using `jq` (if available)
- ✅ Updates frontend addresses **automatically**
- ✅ Installs frontend dependencies
- ✅ Starts frontend server
- ✅ Keeps everything running

**Use when:**
- You want to verify tests pass before deployment
- You want comprehensive pre-flight checks
- You have `jq` installed for better address extraction

**Usage:**
```bash
./deploy-and-test.sh
```

**Requirements:**
- `jq` (optional but recommended): `brew install jq` on macOS

---

### 3. `deploy-and-update-frontend.sh` - Manual Deployment

**What it does:**
- ✅ Checks if Anvil is running
- ✅ Deploys ComposableRWA system
- ✅ Extracts contract addresses from forge output
- ✅ Updates frontend addresses **automatically**
- ❌ Does NOT start Anvil or frontend

**Use when:**
- Anvil is already running
- You want to deploy contracts only
- You want to update addresses without restarting everything

**Usage:**
```bash
# Terminal 1: Start Anvil first
anvil

# Terminal 2: Deploy and update
./deploy-and-update-frontend.sh

# Terminal 3: Start frontend
cd frontend && npm start
```

---

## Automatic Address Updates

All three scripts automatically update `frontend/src/contracts/addresses.ts` with:

✅ **ComposableRWA System:**
- `COMPOSABLE_RWA_BUNDLE`
- `STRATEGY_OPTIMIZER`

✅ **Exposure Strategies:**
- `TRS_EXPOSURE_STRATEGY`
- `PERPETUAL_STRATEGY`
- `DIRECT_TOKEN_STRATEGY`

✅ **Mock Tokens:**
- `USDC` / `MOCK_USDC`
- `WBTC`, `WETH`, `LINK`, `UNI`, `AAVE`

✅ **Infrastructure:**
- `PRICE_ORACLE`
- `DEX`
- `RWA_TOKEN`

✅ **Legacy Aliases (for backward compatibility):**
- `VAULT` / `LEGACY_VAULT`
- `REGISTRY` / `LEGACY_REGISTRY`

## Address Extraction Methods

### run.sh
- Uses `grep` and `awk` to extract from deployment logs
- Parses text output from forge deployment
- Fallback to placeholder addresses if extraction fails

### deploy-and-test.sh
- Uses `jq` to parse broadcast JSON (if available)
- More reliable extraction from `broadcast/` folder
- Falls back to manual copy if `jq` not available

### deploy-and-update-frontend.sh
- Uses `grep` and `awk` to extract from deployment output
- Similar to `run.sh` but standalone
- Provides clear error messages if extraction fails

## Comparison Table

| Feature | run.sh | deploy-and-test.sh | deploy-and-update-frontend.sh |
|---------|--------|-------------------|-------------------------------|
| Start Anvil | ✅ | ✅ | ❌ |
| Build Contracts | ❌ | ✅ | ❌ |
| Run Tests | ❌ | ✅ | ❌ |
| Deploy Contracts | ✅ | ✅ | ✅ |
| Update Addresses | ✅ | ✅ | ✅ |
| Start Frontend | ✅ | ✅ | ❌ |
| Mint USDC | ✅ | ❌ | ❌ |
| Keep Running | ✅ | ✅ | ❌ |
| Requires jq | ❌ | Optional | ❌ |
| One Command | ✅ | ✅ | ❌ |

## Quick Start Recommendation

**For most users, use `run.sh`:**

```bash
# One command to rule them all
./run.sh

# Wait for services to start
# Open http://localhost:3000 in your browser
# Connect MetaMask to localhost:8545
# Start testing!
```

Press `Ctrl+C` when done to stop everything.

## Troubleshooting

### Addresses Not Updating

**Problem:** Frontend shows 0x000...000 addresses

**Solution:**
1. Check if deployment succeeded (look for errors in terminal)
2. Check `deploy.log` for deployment output
3. Verify contract deployment messages contain addresses
4. Try running the script again
5. Manually check `frontend/src/contracts/addresses.ts`

### Address Extraction Failed

**Problem:** Script says "Could not extract contract addresses"

**Solution for run.sh:**
```bash
# Check deployment log
cat deploy.log | grep "deployed at"

# If addresses are there but not extracted, the grep pattern might need adjustment
# Manually update frontend/src/contracts/addresses.ts with the addresses
```

**Solution for deploy-and-test.sh:**
```bash
# Install jq for better extraction
brew install jq  # macOS
apt-get install jq  # Linux

# Or manually check broadcast JSON
cat broadcast/DeployComposableRWA.s.sol/31337/run-latest.json
```

### Frontend Won't Start

**Problem:** Script fails to start frontend

**Solution:**
```bash
# Check if port 3000 is already in use
lsof -i :3000

# Kill existing process
kill -9 <PID>

# Or use a different port
cd frontend
PORT=3001 npm start
```

### Anvil Won't Start

**Problem:** Script fails to start Anvil

**Solution:**
```bash
# Check if port 8545 is already in use
lsof -i :8545

# Kill existing Anvil
pkill anvil

# Or manually start Anvil on different port
anvil --port 8546
# Then update scripts to use 8546
```

## Testing the Setup

After running any script, verify everything works:

```bash
# 1. Check Anvil is running
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 2. Check addresses file was updated
cat frontend/src/contracts/addresses.ts

# 3. Check frontend compiles
cd frontend
npm run build

# 4. Open browser and test
# http://localhost:3000
```

## Additional Resources

- **Frontend Testing:** See `FRONTEND_TESTING_GUIDE.md`
- **Architecture:** See `ARCHITECTURE.md`
- **Smart Contracts:** See `README.md`
- **Test Scenarios:** See `TESTING_SCENARIOS.md`

## Support

If automatic address updates fail:
1. Check deployment succeeded
2. Look at `deploy.log` for addresses
3. Manually update `frontend/src/contracts/addresses.ts`
4. Report issues with log excerpts
