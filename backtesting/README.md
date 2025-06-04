# Web3 Index Fund Backtesting Framework

This document provides a comprehensive guide to the backtesting framework for the Web3 Index Fund project. The framework allows you to simulate and analyze the performance of different portfolio configurations under various market conditions.

## Table of Contents

1. [Framework Overview](#framework-overview)
2. [Getting Started](#getting-started)
3. [Components](#components)
4. [Setting Up a Backtest](#setting-up-a-backtest)
5. [Customizing Backtests](#customizing-backtests)
6. [Running Backtests](#running-backtests)
7. [Analyzing Results](#analyzing-results)
8. [Advanced Features](#advanced-features)
9. [Best Practices](#best-practices)

## Framework Overview

The backtesting framework is designed to simulate the behavior of the IndexFundVaultV2 contract over historical time periods. It allows you to:

- Test different asset allocations and rebalancing strategies
- Evaluate performance under various market conditions
- Calculate key performance metrics like Sharpe ratio and maximum drawdown
- Visualize results for analysis

The framework is modular and extensible, allowing you to add new components or modify existing ones to suit your specific needs.

## Getting Started

### Prerequisites

- Foundry installed (for running tests and scripts)
- Access to historical price data (can be simulated or imported from external sources)

### Directory Structure

```
backtesting/
├── BacktestingFramework.sol       # Core orchestration contract
├── data/
│   └── HistoricalDataProvider.sol # Historical price and yield data
├── metrics/
│   └── MetricsCalculator.sol      # Performance metrics calculations
├── samples/
│   └── SimplePortfolioBacktest.sol # Sample backtest implementation
├── scenarios/
│   └── MarketScenarios.sol        # Market scenario generators
├── simulation/
│   └── VaultSimulationEngine.sol  # Vault behavior simulation
└── visualization/
    └── ResultsExporter.sol        # Data export for visualization
```

## Components

### BacktestingFramework

The central orchestration contract that coordinates the simulation process. It:
- Manages the simulation timeline
- Collects and stores results
- Provides interfaces for other components

### HistoricalDataProvider

Stores and provides historical price and yield data for assets. You can:
- Set price data points manually
- Import data from external sources
- Implement interpolation for missing data points

### VaultSimulationEngine

Simulates the behavior of the IndexFundVaultV2 contract, including:
- Asset price changes
- Yield harvesting
- Rebalancing operations
- Fee calculations

### MetricsCalculator

Calculates performance metrics from backtest results:
- Sharpe ratio and Sortino ratio
- Maximum drawdown
- Annualized returns
- Volatility
- Correlation with benchmarks

### MarketScenarios

Generates different market scenarios for stress testing:
- Market crashes
- High volatility periods
- Yield strategy failures
- Liquidity crunches
- Correlation breakdowns
- Historical event replays

### ResultsExporter

Exports backtest results in formats suitable for visualization:
- Portfolio value time series
- Asset allocation over time
- Yield harvesting metrics
- Rebalance events
- Returns and drawdowns
- Benchmark comparisons

## Setting Up a Backtest

### 1. Create a Backtest Contract

Create a new contract that extends or uses the backtesting framework components:

```solidity
// MyBacktest.sol
import "../BacktestingFramework.sol";
import "../data/HistoricalDataProvider.sol";
import "../simulation/VaultSimulationEngine.sol";
import "../metrics/MetricsCalculator.sol";

contract MyBacktest {
    BacktestingFramework public backtestingFramework;
    HistoricalDataProvider public dataProvider;
    VaultSimulationEngine public simulationEngine;
    MetricsCalculator public metricsCalculator;
    
    constructor() {
        // Initialize components
        dataProvider = new HistoricalDataProvider();
        simulationEngine = new VaultSimulationEngine(
            dataProvider,
            baseAsset,
            initialDeposit,
            rebalanceThreshold,
            rebalanceInterval,
            managementFeeRate,
            performanceFeeRate
        );
        
        metricsCalculator = new MetricsCalculator(riskFreeRate);
        
        backtestingFramework = new BacktestingFramework();
        backtestingFramework.setDataProvider(dataProvider);
        backtestingFramework.setSimulationEngine(simulationEngine);
        backtestingFramework.setMetricsCalculator(metricsCalculator);
    }
    
    // Additional functions...
}
```

### 2. Configure Assets

Add assets to the simulation engine with their target weights:

```solidity
simulationEngine.addAsset(
    assetAddress,
    wrapperAddress,
    targetWeight,  // in basis points (e.g., 2000 = 20%)
    isYieldGenerating
);
```

### 3. Set Up Historical Data

Provide historical price and yield data:

```solidity
// Set price data points
dataProvider.setAssetPrice(assetAddress, timestamp, price);

// Set yield rates for yield-generating assets
dataProvider.setYieldRate(strategyAddress, timestamp, yieldRate);

// Or use batch methods for efficiency
dataProvider.setBatchAssetPrices(assetAddress, timestamps, prices);
```

## Customizing Backtests

### Asset Allocation

Modify asset weights to test different allocation strategies:

```solidity
// Conservative allocation (60% S&P 500, 40% bonds)
simulationEngine.addAsset(SP500_TOKEN, SP500_WRAPPER, 6000, false);
simulationEngine.addAsset(BOND_TOKEN, BOND_WRAPPER, 4000, true);

// Aggressive allocation (90% S&P 500, 10% bonds)
simulationEngine.addAsset(SP500_TOKEN, SP500_WRAPPER, 9000, false);
simulationEngine.addAsset(BOND_TOKEN, BOND_WRAPPER, 1000, true);
```

### Rebalancing Strategy

Adjust rebalancing parameters:

```solidity
// Frequent rebalancing with tight thresholds
simulationEngine = new VaultSimulationEngine(
    dataProvider,
    baseAsset,
    initialDeposit,
    200,        // 2% threshold
    7 days,     // Weekly rebalancing
    managementFeeRate,
    performanceFeeRate
);

// Less frequent rebalancing with wider thresholds
simulationEngine = new VaultSimulationEngine(
    dataProvider,
    baseAsset,
    initialDeposit,
    1000,       // 10% threshold
    90 days,    // Quarterly rebalancing
    managementFeeRate,
    performanceFeeRate
);
```

### Fee Structure

Test different fee structures:

```solidity
// Low-fee structure
simulationEngine = new VaultSimulationEngine(
    dataProvider,
    baseAsset,
    initialDeposit,
    rebalanceThreshold,
    rebalanceInterval,
    50,         // 0.5% management fee
    500         // 5% performance fee
);

// High-fee structure
simulationEngine = new VaultSimulationEngine(
    dataProvider,
    baseAsset,
    initialDeposit,
    rebalanceThreshold,
    rebalanceInterval,
    200,        // 2% management fee
    2000        // 20% performance fee
);
```

### Market Scenarios

Use the MarketScenarios contract to test performance under different conditions:

```solidity
MarketScenarios scenarios = new MarketScenarios(dataProvider);

// Test a market crash
scenarios.generateMarketCrash(
    assetAddress,
    startTimestamp,
    30 days,     // Duration
    40,          // 40% drop
    60 days      // Recovery period
);

// Test high volatility
scenarios.generateHighVolatility(
    assetAddress,
    startTimestamp,
    90 days,     // Duration
    20,          // 20% volatility
    12           // 12 price swings
);
```

## Running Backtests

### 1. Configure the Backtest

Set the time parameters for the backtest:

```solidity
backtestingFramework.configureBacktest(
    startTimestamp,
    endTimestamp,
    timeStep        // e.g., 1 day (86400 seconds)
);
```

### 2. Initialize the Simulation

Initialize the simulation engine with the starting state:

```solidity
simulationEngine.initialize(startTimestamp);
```

### 3. Run the Backtest

Execute the backtest and get the number of results:

```solidity
uint256 resultCount = backtestingFramework.runBacktest();
```

### 4. Calculate Metrics

Calculate performance metrics from the results:

```solidity
(
    int256 sharpeRatio,
    uint256 maxDrawdown,
    int256 annualizedReturn,
    uint256 volatility
) = metricsCalculator.calculateMetrics(backtestingFramework.getAllResults());
```

## Analyzing Results

### Basic Metrics

Get a summary of the backtest results:

```solidity
function getBacktestSummary() external view returns (
    uint256 initialValue,
    uint256 finalValue,
    int256 totalReturn,
    int256 annualizedReturn,
    int256 sharpeRatio,
    uint256 maxDrawdown,
    uint256 volatility
) {
    // Implementation...
}
```

### Time Series Data

Use the ResultsExporter to get time series data for visualization:

```solidity
ResultsExporter exporter = new ResultsExporter(backtestingFramework);

// Get portfolio value over time
(uint256[] memory timestamps, uint256[] memory values) = exporter.getPortfolioValueTimeSeries();

// Get asset allocation over time
(timestamps, uint256[][] memory assetWeights) = exporter.getAssetAllocationTimeSeries();

// Get drawdown analysis
(timestamps, uint256[] memory drawdowns, uint256 maxDrawdown) = exporter.getDrawdownTimeSeries();
```

### Benchmark Comparison

Compare performance against a benchmark:

```solidity
(
    uint256[] memory timestamps,
    uint256[] memory portfolioValues,
    uint256[] memory benchmarkValues,
    int256[] memory relativePerformance
) = exporter.getComparisonData(benchmarkResults);
```

## Advanced Features

### Monte Carlo Simulation

Run multiple backtests with randomized parameters to analyze the distribution of outcomes:

```solidity
function runMonteCarloSimulation(uint256 iterations) external returns (uint256[] memory returns) {
    returns = new uint256[](iterations);
    
    for (uint256 i = 0; i < iterations; i++) {
        // Randomize parameters
        // ...
        
        // Run backtest
        backtestingFramework.runBacktest();
        
        // Store result
        returns[i] = backtestingFramework.getResult(backtestingFramework.getResultCount() - 1).portfolioValue;
    }
    
    return returns;
}
```

### Optimization

Find optimal asset weights by running multiple backtests with different allocations:

```solidity
function findOptimalAllocation() external returns (uint256[] memory optimalWeights) {
    uint256 bestSharpeRatio = 0;
    optimalWeights = new uint256[](assetCount);
    
    // Test different weight combinations
    // ...
    
    return optimalWeights;
}
```

## Best Practices

1. **Data Quality**: Ensure historical data is accurate and has sufficient granularity.
2. **Time Period Selection**: Test over multiple time periods to avoid period-specific biases.
3. **Transaction Costs**: Include realistic gas costs and slippage in simulations.
4. **Stress Testing**: Always test portfolios under extreme market conditions.
5. **Benchmark Comparison**: Compare results against relevant benchmarks.
6. **Sensitivity Analysis**: Test how sensitive results are to small changes in parameters.
7. **Validation**: Validate simulation results against actual historical performance when possible.

## Example Usage

See the `samples/SimplePortfolioBacktest.sol` file for a complete example of setting up and running a backtest with a 20/80 allocation between RWA and S&P 500.

To run the sample backtest:

```solidity
// Deploy the backtest contract
SimplePortfolioBacktest backtest = new SimplePortfolioBacktest(
    1577836800,  // Jan 1, 2020
    1719792000,  // Jun 30, 2024
    86400,       // Daily steps
    10000 * 10**18  // 10,000 USDC initial deposit
);

// Set up historical data
backtest.setupHistoricalData();

// Run the backtest
uint256 resultCount = backtest.runBacktest();

// Get summary
(
    uint256 initialValue,
    uint256 finalValue,
    int256 totalReturn,
    int256 annualizedReturn,
    int256 sharpeRatio,
    uint256 maxDrawdown,
    uint256 volatility
) = backtest.getBacktestSummary();
```
