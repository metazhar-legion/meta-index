# Root Cause Analysis - Frontend Errors

## 🎯 The Core Problem

**The frontend and backend are using completely different contract architectures.**

### What's Deployed (Backend):
```
ComposableRWABundle implements IAssetWrapper
├── getValueInBaseAsset()
├── allocateCapital(amount)
├── withdrawCapital(amount)
├── getUnderlyingTokens()
├── getName()
├── harvestYield()
└── getBaseAsset()
```

### What Frontend Expects:
```
ERC4626 Vault (IndexFundVaultV2)
├── totalSupply()      ← ❌ NOT in ComposableRWABundle
├── totalAssets()      ← ❌ NOT in ComposableRWABundle  
├── balanceOf(address) ← ❌ NOT in ComposableRWABundle
├── deposit(amount)    ← ❌ NOT in ComposableRWABundle
├── withdraw(amount)   ← ❌ NOT in ComposableRWABundle
└── ... (other ERC4626 methods)
```

---

## 🔍 Evidence from Logs

### Error Pattern:
```
Error: missing revert data (action="call", data=null, reason=null, 
transaction={ "data": "0x18160ddd", "to": "0x610178dA211FEF7D417bC0e6FeD39F05609AD788" }
```

**Decoded:**
- `0x18160ddd` = `totalSupply()` function selector
- `0x610178dA211FEF7D417bC0e6FeD39F05609AD788` = ComposableRWABundle address
- "missing revert data" = function doesn't exist on this contract

### Other Failed Calls:
```
0x01e1d114 = totalAssets()
0x70a08231 = balanceOf(address)
```

All of these are ERC4626 methods that don't exist on ComposableRWABundle.

---

## 🤔 Why This Happened

### The Architecture Evolution:

**Old System (what frontend was built for):**
```
IndexFundVaultV2 (ERC4626)
└── RWAAssetWrapper (IAssetWrapper)
    └── Yield Strategies
```

**New System (what's deployed):**
```
ComposableRWABundle (IAssetWrapper) ← This is NOT a vault!
├── TRS Exposure Strategy
├── Enhanced Perpetual Strategy
└── Direct Token Strategy
```

**The Mismatch:**
- The `run.sh` script sets `VAULT: $BUNDLE_ADDRESS`
- This maps ComposableRWABundle to the VAULT field
- Frontend tries to use it as an ERC4626 vault
- **But ComposableRWABundle is an asset wrapper, not a vault!**

---

## 📋 Complete Error Breakdown

### 1. Provider Creation Errors
```
Error: Failed to create provider after connection
```
**Cause:** Secondary issue - happens because the app is in a bad state from contract errors.

### 2. Circuit Breaker Errors
```
MetaMask - RPC Error: Execution prevented because the circuit breaker is open
```
**Cause:** App makes many rapid calls trying to load data, all of which fail, triggering rate limit.

### 3. Contract Call Errors (The Real Problem)
```
Error: missing revert data ... transaction={ "data": "0x18160ddd" }
```
**Cause:** Calling ERC4626 methods on a contract that doesn't implement ERC4626.

---

## 🛠️ Solution Options

### Option 1: Deploy the Missing Vault (Recommended)

**What's needed:**
The system should have BOTH:
1. An ERC4626 vault (IndexFundVaultV2) - for user deposits/withdrawals
2. ComposableRWABundle - as an asset wrapper inside the vault

**Architecture should be:**
```
IndexFundVaultV2 (ERC4626) ← Users interact with this
└── ComposableRWABundle (IAssetWrapper) ← Vault uses this internally
    ├── TRS Strategy
    ├── Perpetual Strategy
    └── Direct Token Strategy
```

**Implementation:**
1. Update `DeployComposableRWA.s.sol` to also deploy IndexFundVaultV2
2. Set the ComposableRWABundle as an asset wrapper in the vault
3. Update `run.sh` to use the vault address (not bundle address) for VAULT

---

### Option 2: Update Frontend to Use ComposableRWABundle Directly

**What's needed:**
Rewrite frontend to work with IAssetWrapper interface instead of ERC4626.

**Changes required:**
- Replace all `totalSupply()` calls with appropriate IAssetWrapper methods
- Replace `totalAssets()` with `getValueInBaseAsset()`
- Replace `deposit()` with `allocateCapital()`
- Replace `withdraw()` with `withdrawCapital()`
- Remove all ERC4626-specific features (shares, balanceOf, etc.)

**Pros:** Uses the new architecture
**Cons:** Major frontend rewrite, loses ERC4626 composability

---

### Option 3: Make ComposableRWABundle Implement ERC4626

**What's needed:**
Add ERC4626 interface to ComposableRWABundle.

**Changes required:**
```solidity
contract ComposableRWABundle is IAssetWrapper, ERC4626, Ownable, ReentrancyGuard, Pausable {
    // Add ERC4626 methods:
    // - totalSupply()
    // - totalAssets()
    // - deposit()
    // - withdraw()
    // - balanceOf()
    // etc.
}
```

**Pros:** Frontend works without changes
**Cons:** Mixing concerns - bundle becomes both a wrapper AND a vault

---

## ✅ Recommended Fix (Option 1)

### Step 1: Check if IndexFundVaultV2 exists

```bash
ls src/IndexFundVaultV2.sol
```

### Step 2: Update Deployment Script

Edit `script/DeployComposableRWA.s.sol` to deploy the vault:

```solidity
// After deploying ComposableRWABundle:
IndexFundVaultV2 vault = new IndexFundVaultV2(
    address(usdc),
    address(priceOracle),
    address(feeManager)
);

// Add the bundle as an asset wrapper
vault.addAssetWrapper(address(bundle), weight, true);

console.log("IndexFundVaultV2 deployed at:", address(vault));
```

### Step 3: Update run.sh

The script already looks for IndexFundVaultV2:
```bash
VAULT_ADDRESS=$(grep "IndexFundVaultV2 deployed at:" deploy.log | awk '{print $NF}' | tail -1)
```

This should work once the deployment script outputs it.

### Step 4: Test

```bash
./run.sh
# Check that VAULT address is different from BUNDLE address
cat frontend/src/contracts/addresses.ts
```

---

## 🎯 Why This is the Right Fix

1. **Maintains Architecture:** Vault manages user funds, bundle manages RWA exposure
2. **Frontend Compatible:** No frontend changes needed
3. **ERC4626 Compliant:** Maintains composability with DeFi ecosystem
4. **Separation of Concerns:** Vault handles deposits/withdrawals, bundle handles strategies

---

## 📊 Expected Outcome After Fix

### Before (Current State):
```
VAULT: 0x6101...D788 (ComposableRWABundle) ← Wrong!
Frontend calls: totalSupply() → ❌ Error: missing revert data
```

### After (Fixed):
```
VAULT: 0xABCD...1234 (IndexFundVaultV2) ← Correct!
BUNDLE: 0x6101...D788 (ComposableRWABundle) ← Used internally by vault
Frontend calls: totalSupply() → ✅ Returns actual supply
```

---

## 🚀 Quick Verification

To confirm this is the issue, try this in the browser console:

```javascript
// Current (fails):
await vaultContract.totalSupply()
// Error: missing revert data

// What should work (if vault was deployed):
await bundleContract.getValueInBaseAsset()
// Should return a value
```

If `getValueInBaseAsset()` works but `totalSupply()` doesn't, it confirms the ABI mismatch.

---

## Summary

**The Problem:** Frontend expects an ERC4626 vault, but got an IAssetWrapper bundle.

**The Solution:** Deploy the actual vault (IndexFundVaultV2) and use the bundle as an asset wrapper inside it.

**The Fix:** Update `DeployComposableRWA.s.sol` to deploy both contracts with proper relationships.

This is an architectural issue, not a bug. The new system is missing the vault layer that the frontend expects.
