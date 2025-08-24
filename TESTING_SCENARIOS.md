# ComposableRWA Testing Scenarios

This document provides comprehensive testing scenarios for the ComposableRWA system, covering both smart contract functionality and frontend integration.

## Prerequisites

Before running these scenarios, ensure you have:

1. **Environment Setup**:
   ```bash
   ./deploy-and-test.sh
   ```
   This script will:
   - Start local blockchain (Anvil)
   - Deploy all contracts
   - Start frontend development server
   - Configure test accounts

2. **Browser Setup**:
   - MetaMask installed and configured
   - Connected to `http://localhost:8545` (Chain ID: 31337)
   - Test account imported with private key from Anvil

3. **Frontend Access**:
   - Navigate to `http://localhost:3000`
   - Select "Composable RWA" role

## Core Testing Scenarios

### 1. Basic System Integration Test

**Objective**: Verify the complete ComposableRWA system works end-to-end

**Steps**:
1. **Connect Wallet**
   - Open frontend at `http://localhost:3000`
   - Click "Connect Wallet" button
   - Connect MetaMask to local network
   - Switch to "Composable RWA" user role

2. **Verify Initial State**
   - Check Strategy Dashboard shows 3 configured strategies:
     - TRS Exposure Strategy (40% target allocation)
     - Enhanced Perpetual Strategy (35% target allocation)
     - Direct Token Strategy (25% target allocation)
   - Verify total portfolio value is $0.00
   - Confirm user USDC balance shows ~1,000,000 USDC

3. **Allocate Capital**
   - Navigate to "Capital Allocation" tab
   - Enter allocation amount: `10000` (for $10,000 USDC)
   - Click "Allocate Capital"
   - Approve USDC spending in MetaMask
   - Confirm allocation transaction
   - Wait for transaction confirmation

4. **Verify Results**
   - Portfolio value should increase to ~$10,000
   - Strategy Dashboard should show active allocations
   - Capital efficiency should be > 90%
   - All strategies should show "Active" status

### 2. Multi-Strategy Allocation Test

**Objective**: Test capital distribution across multiple strategies

**Steps**:
1. **Large Allocation**
   - Allocate $50,000 USDC using allocation interface
   - Verify funds are distributed according to target allocations:
     - TRS Strategy: ~$20,000 (40%)
     - Perpetual Strategy: ~$17,500 (35%) 
     - Direct Token Strategy: ~$12,500 (25%)

2. **Monitor Distribution**
   - Check Strategy Dashboard pie chart
   - Verify each strategy shows correct allocation percentage
   - Confirm portfolio health remains "Healthy"

3. **Additional Allocation**
   - Add another $25,000 USDC
   - Verify proportional distribution is maintained
   - Check that total portfolio value reaches ~$75,000

### 3. Strategy Optimization Test

**Objective**: Test the automatic optimization functionality

**Steps**:
1. **Setup Initial State**
   - Ensure portfolio has at least $50,000 allocated
   - Note current allocation percentages

2. **Trigger Optimization**
   - Click "Optimize" button in Strategy Dashboard
   - Wait for optimization transaction to complete
   - Observe any changes in allocation percentages

3. **Verify Optimization Results**
   - Check if allocations adjusted based on cost analysis
   - Verify transaction completed successfully
   - Monitor any improvement in capital efficiency

### 4. Rebalancing Test

**Objective**: Test manual rebalancing functionality

**Steps**:
1. **Check Rebalance Eligibility**
   - Ensure at least 6 hours have passed since last rebalance
   - Or wait 6 hours after initial allocation

2. **Perform Rebalancing**
   - Click "Rebalance" button in Strategy Dashboard
   - Confirm rebalancing transaction in MetaMask
   - Wait for transaction completion

3. **Verify Results**
   - Confirm allocations return to target percentages
   - Check that all strategies remain active
   - Verify portfolio health is maintained

### 5. Capital Withdrawal Test

**Objective**: Test capital withdrawal functionality

**Steps**:
1. **Partial Withdrawal**
   - Navigate to "Capital Allocation" tab
   - Enter withdrawal amount: `5000` (for $5,000)
   - Click "Withdraw Capital"
   - Confirm transaction in MetaMask

2. **Verify Results**
   - USDC balance should increase by ~$5,000
   - Portfolio value should decrease proportionally
   - All strategies should remain active with reduced positions

3. **Full Withdrawal**
   - Click "Max" button in withdrawal section
   - Withdraw entire portfolio value
   - Confirm all positions are closed
   - Verify strategies show "Inactive" status

### 6. Yield Harvesting Test

**Objective**: Test yield collection from strategies

**Steps**:
1. **Setup Position**
   - Allocate at least $30,000 to generate meaningful yield
   - Wait a few minutes for yield to accumulate

2. **Harvest Yield**
   - Click "Harvest Yield" button in portfolio overview
   - Confirm transaction in MetaMask
   - Wait for completion

3. **Verify Results**
   - Check if additional USDC was added to portfolio
   - Verify yield amount is reflected in performance metrics
   - Confirm transaction completed successfully

### 7. Error Handling Test

**Objective**: Verify proper error handling and user feedback

**Steps**:
1. **Insufficient Balance Test**
   - Try to allocate more USDC than available balance
   - Verify appropriate error message is displayed
   - Confirm transaction is prevented

2. **Network Issues Test**
   - Disconnect MetaMask temporarily
   - Try to perform transactions
   - Verify connection errors are handled gracefully
   - Reconnect and verify functionality resumes

3. **Transaction Failure Test**
   - Set very low gas limit in MetaMask
   - Attempt a transaction
   - Verify failure is handled with clear error message

**⚠️ Known Issues**: Currently some error states may cause UI freezing or unclear messaging. These are being addressed in the frontend revamp.

## Advanced Testing Scenarios

### 8. Strategy-Specific Testing

#### TRS Strategy Test
1. **Monitor Counterparty Distribution**
   - Allocate large amount ($100,000+)
   - Verify TRS contracts are distributed across counterparties
   - Check concentration limits are respected

2. **Risk Management**
   - Monitor counterparty exposure limits
   - Verify no single counterparty exceeds 40% of TRS allocation

#### Perpetual Strategy Test
1. **Leverage Monitoring**
   - Check current leverage displayed in dashboard
   - Verify leverage stays within configured limits
   - Monitor PnL changes over time

#### Direct Token Strategy Test
1. **Token Purchase Verification**
   - Monitor RWA token balance increases with allocations
   - Verify DEX exchange rates are working correctly
   - Check yield strategy integration

### 9. Performance Monitoring Test

**Objective**: Test performance tracking and metrics

**Steps**:
1. **Baseline Metrics**
   - Record initial performance metrics
   - Note capital efficiency, leverage, and health status

2. **Time-Based Monitoring**
   - Monitor changes over 30+ minutes
   - Track yield accumulation
   - Observe any performance metric changes

3. **Comparison Analysis**
   - Compare performance across different strategies
   - Analyze cost effectiveness
   - Monitor risk-adjusted returns

### 10. Load Testing

**Objective**: Test system under heavy usage

**Steps**:
1. **Rapid Transactions**
   - Perform multiple quick allocations/withdrawals
   - Test transaction queue handling
   - Verify UI remains responsive

2. **Large Amounts**
   - Test with maximum USDC amounts
   - Verify system handles large numbers correctly
   - Check for any overflow/underflow issues

## Troubleshooting Guide

### Common Issues and Solutions

1. **MetaMask Connection Issues**
   - Solution: Reset MetaMask account, re-import private key
   - Check network is set to `http://localhost:8545`

2. **Transaction Failures**
   - Solution: Increase gas limit, check account balance
   - Verify contract addresses are correctly configured

3. **Frontend Not Loading Data**
   - Solution: Check browser console for errors
   - Verify contract addresses in `addresses.ts` are correct
   - Refresh page and reconnect wallet
   - **Known Issue**: Data loading inconsistencies may require page refresh

4. **Anvil Stopped Working**
   - Solution: Restart with `./deploy-and-test.sh`
   - Check anvil.log for error details

5. **Frontend Performance Issues**
   - **Known Issue**: Excessive re-renders and redundant contract calls
   - **Temporary Solution**: Refresh page periodically if UI becomes sluggish
   - **Permanent Fix**: Frontend optimization in progress

6. **Error State Recovery**
   - **Known Issue**: Some error states don't properly reset UI
   - **Temporary Solution**: Refresh page and reconnect wallet after errors
   - **Permanent Fix**: Comprehensive error boundaries being implemented

### Debug Commands

```bash
# View Anvil logs
tail -f anvil.log

# View Frontend logs  
tail -f frontend.log

# Run specific contract tests
forge test --match-contract ComposableRWABundle -v

# Check account balances
cast balance <address> --rpc-url http://localhost:8545

# View transaction details
cast tx <tx-hash> --rpc-url http://localhost:8545
```

## Testing Checklist

Use this checklist to ensure comprehensive testing:

- [ ] Basic wallet connection and role selection
- [ ] Initial capital allocation (small amount)
- [ ] Strategy dashboard data display
- [ ] Capital allocation interface functionality
- [ ] Portfolio value updates correctly
- [ ] Multi-strategy distribution works
- [ ] Strategy optimization executes
- [ ] Rebalancing functionality works
- [ ] Capital withdrawal (partial and full)
- [ ] Yield harvesting functionality
- [ ] Error handling for edge cases
- [ ] Performance metrics tracking
- [ ] Real-time UI updates
- [ ] Transaction confirmation flows
- [ ] Large amount handling
- [ ] Rapid transaction processing

## Success Criteria

A successful test run should demonstrate:

1. **Functional Integration**: All components work together seamlessly
2. **Accurate Calculations**: Portfolio values and allocations are correct
3. **Proper Risk Management**: Concentration limits and health checks work
4. **User Experience**: Clear feedback and smooth transaction flows
5. **Error Resilience**: Graceful handling of failures and edge cases
6. **Performance**: Responsive UI and efficient contract interactions

## Reporting Issues

When reporting issues, include:

1. **Environment Details**: Browser, MetaMask version, OS
2. **Steps to Reproduce**: Detailed step-by-step instructions
3. **Expected vs Actual**: What should happen vs what actually happened
4. **Screenshots**: Visual evidence of the issue
5. **Console Logs**: Browser console and network tab information
6. **Transaction Hashes**: For failed transactions

This comprehensive testing approach ensures the ComposableRWA system is production-ready and provides excellent user experience.