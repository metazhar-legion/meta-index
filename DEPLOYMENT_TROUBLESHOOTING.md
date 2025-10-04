# Deployment Troubleshooting Guide

## Common Deployment Issues and Solutions

### Issue 1: PRIVATE_KEY Environment Variable Error

**Error Message:**
```
Error: Environment variable "PRIVATE_KEY" not found
```

**Cause:**
The deployment script expects `PRIVATE_KEY` to be set as an environment variable, but it wasn't found.

**Solution:**

All deployment scripts have been updated to automatically export the private key. If you still see this error:

**Option A: Use the provided scripts (recommended)**
```bash
./run.sh
# OR
./deploy-and-test.sh
# OR
./deploy-and-update-frontend.sh
```

These scripts automatically set the `PRIVATE_KEY` environment variable.

**Option B: Manual deployment**
```bash
# Export the key first
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Then deploy
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url http://localhost:8545 \
    --broadcast
```

**Option C: Use command-line flag**
```bash
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url http://localhost:8545 \
    --broadcast \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

---

### Issue 2: Anvil Not Running

**Error Message:**
```
Error: Failed to connect to RPC
```
or
```
Error: Connection refused at http://localhost:8545
```

**Solution:**
```bash
# Check if Anvil is running
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# If not running, start it
anvil
```

---

### Issue 3: Port Already in Use

**Error Message:**
```
Error: Address already in use (port 8545)
```

**Solution:**
```bash
# Find and kill process on port 8545
lsof -ti :8545 | xargs kill -9

# Or use a different port
anvil --port 8546

# Update scripts to use new port
# Edit run.sh, deploy-and-test.sh, etc. to use 8546
```

---

### Issue 4: Insufficient Funds

**Error Message:**
```
Error: Insufficient funds for gas
```

**Solution:**

This shouldn't happen with Anvil's default accounts. If it does:

```bash
# Restart Anvil with more balance
anvil --balance 10000

# Or use a different account
# Anvil provides 10 accounts by default, all funded
```

---

### Issue 5: Contract Deployment Fails

**Error Message:**
```
Error: Contract deployment reverted
```

**Solution:**

1. **Check deployment logs:**
```bash
cat deploy.log
```

2. **Run with verbose output:**
```bash
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url http://localhost:8545 \
    --broadcast \
    -vvvv  # Very verbose
```

3. **Verify contracts compile:**
```bash
forge build
```

---

### Issue 6: Address Extraction Fails

**Error Message:**
```
Error: Could not extract contract addresses
```

**Solution:**

1. **Check deploy.log for actual addresses:**
```bash
grep "deployed at:" deploy.log
```

2. **Manually update addresses:**
If extraction fails, copy addresses from deployment output and update:
```bash
nano frontend/src/contracts/addresses.ts
```

3. **Verify deployment succeeded:**
The addresses should appear in the deployment output. If they don't, the deployment may have failed.

---

### Issue 7: Frontend Shows 0x000...000 Addresses

**Symptom:**
Frontend code references contracts but shows zero addresses.

**Solution:**

1. **Check addresses file:**
```bash
cat frontend/src/contracts/addresses.ts
```

2. **Re-run deployment:**
```bash
./run.sh
# OR
./deploy-and-update-frontend.sh
```

3. **Verify extraction patterns match:**
The scripts look for these patterns in deployment logs:
- `ComposableRWABundle deployed at:`
- `StrategyOptimizer deployed at:`
- `TRSExposureStrategy deployed at:`
- etc.

If deployment output format changed, the grep patterns may need updating.

---

### Issue 8: Multiple Anvil Instances Running

**Symptom:**
Deployment succeeds but frontend connects to wrong blockchain.

**Solution:**
```bash
# Kill all Anvil instances
pkill anvil

# Verify nothing on port 8545
lsof -i :8545

# Start fresh Anvil
anvil

# Re-deploy
./run.sh
```

---

## Quick Test Script

To quickly test if deployment works:

```bash
# 1. Start Anvil
anvil &

# 2. Wait a moment
sleep 3

# 3. Run test script
./test-deploy.sh
```

This will verify:
- Anvil is running
- Private key is set correctly
- Deployment completes successfully

---

## Verification Checklist

After deployment, verify everything worked:

```bash
# ✅ Check Anvil is running
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# ✅ Check deployment log exists
ls -lh deploy.log

# ✅ Check addresses were extracted
cat frontend/src/contracts/addresses.ts | grep "COMPOSABLE_RWA_BUNDLE"

# ✅ Check addresses are not placeholders
cat frontend/src/contracts/addresses.ts | grep -v "0x0000000000000000000000000000000000000000"

# ✅ Check frontend compiles
cd frontend && npm run build
```

---

## Debug Mode

For detailed debugging:

```bash
# Set debug mode
set -x

# Export key
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Deploy with maximum verbosity
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url http://localhost:8545 \
    --broadcast \
    -vvvv \
    2>&1 | tee detailed-deploy.log

# Unset debug mode
set +x
```

---

## Getting Help

If none of these solutions work:

1. **Collect information:**
   ```bash
   # Forge version
   forge --version

   # Anvil status
   ps aux | grep anvil

   # Port status
   lsof -i :8545

   # Recent deployment logs
   tail -100 deploy.log
   ```

2. **Check latest documentation:**
   - `DEPLOYMENT_SCRIPTS_GUIDE.md`
   - `FRONTEND_TESTING_GUIDE.md`
   - `README.md`

3. **File an issue** with:
   - Error messages
   - Steps to reproduce
   - Output from information collection above

---

## Success Indicators

You know deployment succeeded when:

✅ No error messages in terminal
✅ `deploy.log` contains "deployed at:" messages
✅ `frontend/src/contracts/addresses.ts` has real addresses (not 0x000...000)
✅ Frontend compiles without errors
✅ Can connect MetaMask to localhost:8545
✅ Can interact with contracts through frontend

---

## Reset Everything

If all else fails, start completely fresh:

```bash
# 1. Kill all services
pkill anvil
pkill node

# 2. Clean build artifacts
forge clean
rm -rf cache out broadcast

# 3. Clean frontend
cd frontend
rm -rf node_modules build
npm install
cd ..

# 4. Rebuild contracts
forge build

# 5. Start fresh
./run.sh
```

This will give you a completely clean slate.
