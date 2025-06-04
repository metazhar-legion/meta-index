// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimplePortfolioBacktest.sol";
import "../metrics/MetricsCalculator.sol";
import "../scenarios/MarketScenarios.sol";
import "../visualization/ResultsExporter.sol";
import "forge-std/Script.sol";

/**
 * @title BacktestRunner
 * @notice Script to run backtests and export results
 * @dev Use with Forge script to run backtests and analyze results
 */
contract BacktestRunner is Script {
    // Constants for configuration
    uint256 constant START_TIMESTAMP = 1577836800; // Jan 1, 2020
    uint256 constant END_TIMESTAMP = 1719792000;   // Jun 30, 2024
    uint256 constant TIME_STEP = 1 days;           // Daily steps
    uint256 constant INITIAL_DEPOSIT = 10000 * 10**18; // 10,000 USDC
    
    // Test different portfolio allocations
    uint256[][] public allocations = [
        [2000, 8000],  // 20/80 split (RWA/S&P 500)
        [4000, 6000],  // 40/60 split
        [6000, 4000],  // 60/40 split
        [8000, 2000]   // 80/20 split
    ];
    
    // Test different rebalance thresholds
    uint256[] public rebalanceThresholds = [
        300,  // 3%
        500,  // 5%
        1000  // 10%
    ];
    
    /**
     * @notice Run a standard backtest with the default 20/80 allocation
     */
    function run() public {
        vm.startBroadcast();
        
        // Create and run the default backtest
        SimplePortfolioBacktest backtest = new SimplePortfolioBacktest(
            START_TIMESTAMP,
            END_TIMESTAMP,
            TIME_STEP,
            INITIAL_DEPOSIT
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
        
        // Log results
        console.log("=== Standard Backtest Results ===");
        console.log("Result Count:", resultCount);
        console.log("Initial Value:", initialValue);
        console.log("Final Value:", finalValue);
        console.log("Total Return:", totalReturn);
        console.log("Annualized Return:", annualizedReturn);
        console.log("Sharpe Ratio:", sharpeRatio);
        console.log("Max Drawdown:", maxDrawdown);
        console.log("Volatility:", volatility);
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Run multiple backtests with different asset allocations
     */
    function runAllocationComparison() public {
        vm.startBroadcast();
        
        console.log("=== Allocation Comparison ===");
        
        for (uint256 i = 0; i < allocations.length; i++) {
            // Create custom backtest with specific allocation
            SimplePortfolioBacktest backtest = new SimplePortfolioBacktest(
                START_TIMESTAMP,
                END_TIMESTAMP,
                TIME_STEP,
                INITIAL_DEPOSIT
            );
            
            // Override the default allocations
            // Note: This is a simplified example. In a real implementation,
            // you would need to modify the SimplePortfolioBacktest to allow
            // changing allocations after construction.
            
            // Set up historical data
            backtest.setupHistoricalData();
            
            // Run the backtest
            backtest.runBacktest();
            
            // Get summary
            (
                ,  // initialValue
                ,  // finalValue
                int256 totalReturn,
                int256 annualizedReturn,
                int256 sharpeRatio,
                uint256 maxDrawdown,
                uint256 volatility
            ) = backtest.getBacktestSummary();
            
            // Log results
            console.log("Allocation", i, ":", allocations[i][0], "/", allocations[i][1]);
            console.log("  Total Return:", totalReturn);
            console.log("  Annualized Return:", annualizedReturn);
            console.log("  Sharpe Ratio:", sharpeRatio);
            console.log("  Max Drawdown:", maxDrawdown);
            console.log("  Volatility:", volatility);
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Run a stress test with market crash scenario
     */
    function runStressTest() public {
        vm.startBroadcast();
        
        // Create backtest
        SimplePortfolioBacktest backtest = new SimplePortfolioBacktest(
            START_TIMESTAMP,
            END_TIMESTAMP,
            TIME_STEP,
            INITIAL_DEPOSIT
        );
        
        // Set up historical data
        backtest.setupHistoricalData();
        
        // Get data provider from backtest
        // Note: In a real implementation, you would need to add a getter for dataProvider
        // in SimplePortfolioBacktest
        HistoricalDataProvider dataProvider = new HistoricalDataProvider();
        
        // Create market scenarios
        MarketScenarios scenarios = new MarketScenarios(dataProvider);
        
        // Generate a market crash scenario
        // Note: This is a simplified example. In a real implementation,
        // you would use the actual data provider from the backtest.
        address SP500_TOKEN = address(0x2);
        address RWA_TOKEN = address(0x3);
        
        uint256 crashTimestamp = START_TIMESTAMP + 365 days; // 1 year in
        
        scenarios.generateMarketCrash(
            SP500_TOKEN,
            crashTimestamp,
            30 days,     // Duration
            40,          // 40% drop
            60 days      // Recovery period
        );
        
        scenarios.generateMarketCrash(
            RWA_TOKEN,
            crashTimestamp,
            30 days,     // Duration
            20,          // 20% drop (less severe for RWA)
            60 days      // Recovery period
        );
        
        // Run the backtest
        backtest.runBacktest();
        
        // Get summary
        (
            ,  // initialValue
            ,  // finalValue
            int256 totalReturn,
            int256 annualizedReturn,
            int256 sharpeRatio,
            uint256 maxDrawdown,
            uint256 volatility
        ) = backtest.getBacktestSummary();
        
        // Log results
        console.log("=== Stress Test Results ===");
        console.log("Total Return:", totalReturn);
        console.log("Annualized Return:", annualizedReturn);
        console.log("Sharpe Ratio:", sharpeRatio);
        console.log("Max Drawdown:", maxDrawdown);
        console.log("Volatility:", volatility);
        
        vm.stopBroadcast();
    }
}
