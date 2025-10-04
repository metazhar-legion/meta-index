# Frontend Error Analysis & Simple Fixes

## Critical Issues Identified

Based on the log file analysis, there are **3 main categories of errors** with simple fixes:

---

## 1. ❌ VAULT ADDRESS IS ZERO (CRITICAL)

**Error:**
```
VAULT: '0x0000000000000000000000000000000000000000'
```

**Impact:** All vault contract calls fail because the address is invalid.

**Root Cause:** The `run.sh` script is using `DeployBasicSetup.s.sol` which deploys the old vault architecture, but the frontend expects the new ComposableRWA system.

### ✅ SIMPLE FIX:

**Update `run.sh` line 75:**

```bash
# OLD (line 75):
forge script script/DeployBasicSetup.s.sol:DeployBasicSetup --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 > deploy.log 2>&1

# NEW:
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 > deploy.log 2>&1
```

**Update `run.sh` lines 89-92 to extract correct addresses:**

```bash
# OLD:
VAULT_ADDRESS=$(grep "IndexFundVaultV2 deployed at:" deploy.log | awk '{print $NF}')
USDC_ADDRESS=$(grep "MockUSDC deployed at:" deploy.log | awk '{print $NF}')
PRICE_ORACLE_ADDRESS=$(grep "MockPriceOracle deployed at:" deploy.log | awk '{print $NF}')
DEX_ADDRESS=$(grep "MockDEX deployed at:" deploy.log | awk '{print $NF}')

# NEW:
VAULT_ADDRESS=$(grep "ComposableRWABundle deployed at:" deploy.log | awk '{print $NF}')
USDC_ADDRESS=$(grep "MockUSDC deployed at:" deploy.log | awk '{print $NF}')
PRICE_ORACLE_ADDRESS=$(grep "MockPriceOracle deployed at:" deploy.log | awk '{print $NF}')
DEX_ADDRESS=$(grep "MockDEX deployed at:" deploy.log | awk '{print $NF}')
```

---

## 2. ❌ MISSING CONTRACT FUNCTIONS

**Error:**
```
TypeError: vaultContract.lastRebalance is not a function
```

**Root Cause:** The `CapitalAllocation.tsx` component is trying to call `lastRebalance()` which doesn't exist on the ComposableRWABundle contract.

### ✅ SIMPLE FIX:

**Option A: Remove the lastRebalance call (Quickest)**

Edit `/frontend/src/components/CapitalAllocation.tsx`:

```typescript
// REMOVE lines 113-114:
// const lastRebalanceTimestamp = await vaultContract.lastRebalance();

// UPDATE line 146:
lastRebalanced: 0  // Or use Date.now() / 1000 for current timestamp
```

**Option B: Use the correct contract (Better)**

The component should use `ComposableRWABundle` contract instead of the old vault contract. The ComposableRWABundle has different methods:
- `getExposureStrategies()` instead of `assetList()`
- `getYieldBundle()` for yield strategies
- No `lastRebalance()` - this would need to be tracked differently

---

## 3. ❌ PROVIDER CREATION FAILURES

**Error:**
```
Error: Failed to create provider after connection
MetaMask - RPC Error: Execution prevented because the circuit breaker is open
```

**Root Cause:** MetaMask's circuit breaker is triggered by too many rapid RPC calls, likely from:
1. Multiple components trying to initialize contracts simultaneously
2. Auto-connect attempting to connect before MetaMask is ready
3. Polling intervals that are too aggressive

### ✅ SIMPLE FIXES:

**Fix 1: Add delay to auto-connect**

Edit `/frontend/src/contexts/Web3Context.tsx` around line 200:

```typescript
// In the useEffect for auto-connect, add a delay:
useEffect(() => {
  const tryAutoConnect = async () => {
    const wasConnected = localStorage.getItem('isWalletConnected');
    if (wasConnected === 'true' && !account) {
      // Add delay to let MetaMask initialize
      await new Promise(resolve => setTimeout(resolve, 1000));
      await connect();
    }
  };
  tryAutoConnect();
}, []);
```

**Fix 2: Reduce polling frequency**

Edit `/frontend/src/components/VaultStats.tsx`:

```typescript
// Change polling interval from 5 seconds to 10 seconds
const POLLING_INTERVAL = 10000; // was 5000
```

**Fix 3: Add retry logic with exponential backoff**

Edit `/frontend/src/contexts/Web3Context.tsx` in the `getProvider` function:

```typescript
const getProvider = useCallback(async (retries = 3): Promise<ethers.BrowserProvider | null> => {
  if (typeof window.ethereum === 'undefined') {
    return null;
  }

  for (let i = 0; i < retries; i++) {
    try {
      const provider = new ethers.BrowserProvider(window.ethereum);
      await provider.getNetwork(); // Test the connection
      return provider;
    } catch (error) {
      if (i === retries - 1) throw error;
      // Exponential backoff: 500ms, 1000ms, 2000ms
      await new Promise(resolve => setTimeout(resolve, 500 * Math.pow(2, i)));
    }
  }
  return null;
}, []);
```

---

## 4. ⚠️ MISSING PRICE ORACLE ADDRESS

**Issue:**
```
PRICE_ORACLE: '',
```

**Impact:** Any component using the price oracle will fail.

### ✅ SIMPLE FIX:

The `DeployComposableRWA.s.sol` script should output the price oracle address. Update the extraction in `run.sh`:

```bash
PRICE_ORACLE_ADDRESS=$(grep "MockPriceOracle deployed at:" deploy.log | awk '{print $NF}')
```

If it's still empty, check the deployment script output format.

---

## Priority Order for Fixes

### 🔴 CRITICAL (Do First):
1. **Fix vault address** - Update `run.sh` to use `DeployComposableRWA.s.sol`
2. **Fix contract function calls** - Remove or update `lastRebalance()` calls

### 🟡 HIGH (Do Second):
3. **Add provider retry logic** - Prevent MetaMask circuit breaker
4. **Add auto-connect delay** - Let MetaMask initialize properly

### 🟢 MEDIUM (Do Third):
5. **Reduce polling frequency** - Decrease RPC call load
6. **Fix price oracle address** - Ensure all addresses are extracted

---

## Quick Test After Fixes

1. Stop any running instances
2. Kill Anvil: `pkill anvil`
3. Clear browser cache and localStorage
4. Run: `./run.sh`
5. Check that addresses.ts has valid addresses (not 0x0000...)
6. Open browser console and verify no errors on initial load

---

## Expected Outcome

After these fixes:
- ✅ Vault address will be valid
- ✅ Contract calls will succeed
- ✅ MetaMask circuit breaker won't trigger
- ✅ Auto-connect will work reliably
- ✅ No errors on initial page load

---

## Additional Notes

**Why the circuit breaker triggers:**
MetaMask has a built-in rate limiter that prevents too many RPC calls in a short time. This is a security feature to prevent DDoS attacks. The current frontend makes many simultaneous calls on load:
- VaultStats polling
- TestingTools balance loading
- CapitalAllocation data loading
- Contract initialization tests

**Long-term solution:**
Implement a request queue or use a caching layer to batch RPC calls and reduce the total number of requests.
