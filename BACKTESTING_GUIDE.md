# Web3 Index Fund Backtesting Guide

This guide explains how to update historical data and run backtests for the Web3 Index Fund.

## Overview

The backtesting framework simulates the performance of different asset allocation strategies and rebalancing frequencies using historical price data. It consists of:

- **Data Providers**: Supply historical price and yield data
- **Simulation Engine**: Simulates portfolio operations including rebalancing
- **Metrics Calculator**: Computes performance metrics like Sharpe ratio and max drawdown
- **Backtest Runners**: Orchestrate the backtesting process with different parameters

## Updating Historical Price Data

### Prerequisites

- Node.js installed
- Alpha Vantage API key (free tier works for basic usage)

### Steps to Update Data

1. **Run the data fetching script**:

```bash
cd /Users/azhar/CascadeProjects/web3-index-fund
node scripts/fetch_historical_data.js YOUR_ALPHA_VANTAGE_API_KEY
```

2. **Data Sources**:
   - S&P 500: Using SPY (SPDR S&P 500 ETF Trust) as a proxy
   - RWA: Using VTIP (Vanguard Short-Term Inflation-Protected Securities ETF) as a proxy

3. **Generated Files**:
   - JSON data: `/data/historical/SP500_daily.json` and `/data/historical/RWA_daily.json`
   - Solidity library: `/data/historical/HistoricalPriceData.sol`
   - Checker library: `/data/historical/HistoricalPriceDataChecker.sol`

## Running Backtests

### Basic Backtest

```bash
# Compile contracts
forge build

# Run a simple backtest
forge script script/RunSimpleBacktest.s.sol -vvv
```

### Rebalancing Comparison

```bash
# Compare monthly vs quarterly rebalancing
forge script script/RunRebalanceComparison.s.sol -vvv
```

### Asset Allocation Comparison

```bash
# Compare different asset allocations
forge script script/RunAllocationComparison.s.sol -vvv
```

## Customizing Backtests

### Modifying Asset Allocations

Edit the asset allocation in the backtest contract constructor:

```solidity
// Example: Change from 20/80 to 30/70 allocation
simulationEngine.addAsset(RWA_TOKEN, RWA_WRAPPER, 3000, true);    // 30% RWA with yield
simulationEngine.addAsset(SP500_TOKEN, SP500_WRAPPER, 7000, false); // 70% S&P 500
```

### Changing Rebalancing Parameters

Modify the rebalance threshold and interval in the VaultSimulationEngine constructor:

```solidity
simulationEngine = new VaultSimulationEngine(
    dataProvider,
    USDC,              // Base asset
    initialDeposit,    // Initial deposit
    500,               // Rebalance threshold (5%)
    90 days,           // Rebalance interval (quarterly)
    10,                // Management fee (0.1%)
    0                  // Performance fee (0%)
);
```

### Adjusting Time Periods

Change the start and end timestamps in the backtest script:

```solidity
// Example: Run backtest for 2022-2023
uint256 startTimestamp = 1640995200; // 2022-01-01
uint256 endTimestamp = 1703980800;   // 2023-12-31
```

## Interpreting Results

The backtest outputs include:

- **Result Count**: Number of data points in the simulation
- **Initial/Final Value**: Starting and ending portfolio values
- **Total Return**: Overall return percentage
- **Annualized Return**: Return normalized to annual basis
- **Sharpe Ratio**: Risk-adjusted return metric (higher is better)
- **Max Drawdown**: Largest peak-to-trough decline (lower is better)
- **Volatility**: Standard deviation of returns

## Monthly vs Quarterly Rebalancing

Our backtests show that quarterly rebalancing provides similar performance to monthly rebalancing while reducing costs:

### Cost Comparison

1. **Transaction Costs**:
   - Monthly: ~12 transactions per year
   - Quarterly: ~4 transactions per year (67% reduction)

2. **Gas Fees**:
   - Each rebalance requires multiple on-chain transactions
   - Quarterly rebalancing reduces gas costs by approximately 67%

3. **Management Overhead**:
   - Less frequent rebalancing reduces operational complexity
   - Fewer opportunities for errors or missed rebalances

### Performance Impact

Our backtests with real historical data show negligible performance differences between monthly and quarterly rebalancing for our current asset allocation.

## Troubleshooting

### Common Issues

1. **Missing Historical Data**:
   - Check that `HistoricalPriceData.sol` and `HistoricalPriceDataChecker.sol` are properly generated
   - Verify API key and network connectivity when fetching data

2. **Zero Max Drawdown**:
   - If max drawdown shows as zero, check that price data has sufficient volatility
   - Verify the max drawdown calculation in `MetricsCalculator.sol`

3. **Compiler Warnings**:
   - Address unused variables and parameters
   - Check for visibility issues in function declarations
