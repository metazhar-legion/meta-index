// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../backtesting/samples/MonthlyRebalanceBacktest.sol";
import "../backtesting/samples/QuarterlyRebalanceBacktest.sol";
import "../backtesting/data/HistoricalPriceDataLoader.sol";

/**
 * @title RunRebalanceComparison
 * @notice Script to run and compare monthly vs quarterly rebalancing backtests
 */
contract RunRebalanceComparison is Script {
    // Test parameters
    uint256 constant START_TIMESTAMP = 1577836800; // Jan 1, 2020
    uint256 constant END_TIMESTAMP = 1719792000;   // Jun 30, 2024
    uint256 constant TIME_STEP = 86400;            // Daily steps
    uint256 constant INITIAL_DEPOSIT = 9000 * 10**18; // 9,000 tokens
    
    // Backtest contracts
    MonthlyRebalanceBacktest public monthlyBacktest;
    QuarterlyRebalanceBacktest public quarterlyBacktest;
    HistoricalPriceDataLoader public dataLoader;
    
    function run() public {
        vm.startBroadcast();
        
        // Create data loader
        dataLoader = new HistoricalPriceDataLoader();
        
        // Create and run monthly rebalance backtest
        console.log("=== Starting Monthly Rebalance Backtest ===");
        monthlyBacktest = new MonthlyRebalanceBacktest(
            START_TIMESTAMP,
            END_TIMESTAMP,
            TIME_STEP,
            INITIAL_DEPOSIT
        );
        
        // Load historical data using the data loader instead of inline setup
        console.log("Loading historical price data for monthly backtest...");
        dataLoader.loadHistoricalPriceData(monthlyBacktest.getDataProvider());
        dataLoader.loadHistoricalYieldData(monthlyBacktest.getDataProvider());
        
        // Run backtest
        uint256 monthlyResultCount = monthlyBacktest.runBacktest();
        
        // Get and display results
        (
            uint256 monthlyInitialValue,
            uint256 monthlyFinalValue,
            int256 monthlyTotalReturn,
            int256 monthlyAnnualizedReturn,
            int256 monthlySharpeRatio,
            uint256 monthlyMaxDrawdown,
            uint256 monthlyVolatility
        ) = monthlyBacktest.getBacktestSummary();
        
        console.log("=== Monthly Rebalance Backtest Results ===");
        console.log("Result Count:", monthlyResultCount);
        console.log("Initial Value:", monthlyInitialValue);
        console.log("Final Value:", monthlyFinalValue);
        console.log("Total Return:", uint256(monthlyTotalReturn));
        console.log("Annualized Return:", uint256(monthlyAnnualizedReturn));
        console.log("Sharpe Ratio:", uint256(monthlySharpeRatio));
        console.log("Max Drawdown:", monthlyMaxDrawdown);
        console.log("Volatility:", monthlyVolatility);
        
        // Create and run quarterly rebalance backtest
        console.log("\n=== Starting Quarterly Rebalance Backtest ===");
        quarterlyBacktest = new QuarterlyRebalanceBacktest(
            START_TIMESTAMP,
            END_TIMESTAMP,
            TIME_STEP,
            INITIAL_DEPOSIT
        );
        
        // Load historical data using the data loader instead of inline setup
        console.log("Loading historical price data for quarterly backtest...");
        dataLoader.loadHistoricalPriceData(quarterlyBacktest.getDataProvider());
        dataLoader.loadHistoricalYieldData(quarterlyBacktest.getDataProvider());
        
        // Run backtest
        uint256 quarterlyResultCount = quarterlyBacktest.runBacktest();
        
        // Get and display results
        (
            uint256 quarterlyInitialValue,
            uint256 quarterlyFinalValue,
            int256 quarterlyTotalReturn,
            int256 quarterlyAnnualizedReturn,
            int256 quarterlySharpeRatio,
            uint256 quarterlyMaxDrawdown,
            uint256 quarterlyVolatility
        ) = quarterlyBacktest.getBacktestSummary();
        
        console.log("=== Quarterly Rebalance Backtest Results ===");
        console.log("Result Count:", quarterlyResultCount);
        console.log("Initial Value:", quarterlyInitialValue);
        console.log("Final Value:", quarterlyFinalValue);
        console.log("Total Return:", uint256(quarterlyTotalReturn));
        console.log("Annualized Return:", uint256(quarterlyAnnualizedReturn));
        console.log("Sharpe Ratio:", uint256(quarterlySharpeRatio));
        console.log("Max Drawdown:", quarterlyMaxDrawdown);
        console.log("Volatility:", quarterlyVolatility);
        
        // Compare results
        console.log("\n=== Rebalancing Strategy Comparison ===");
        console.log("Monthly vs Quarterly Performance Difference:");
        
        int256 finalValueDiff;
        if (monthlyFinalValue > quarterlyFinalValue) {
            finalValueDiff = int256(monthlyFinalValue - quarterlyFinalValue);
            console.log("Final Value: Monthly outperforms by", uint256(finalValueDiff));
        } else {
            finalValueDiff = int256(quarterlyFinalValue - monthlyFinalValue);
            console.log("Final Value: Quarterly outperforms by", uint256(finalValueDiff));
        }
        
        int256 returnDiff = monthlyAnnualizedReturn - quarterlyAnnualizedReturn;
        if (returnDiff > 0) {
            console.log("Annualized Return: Monthly outperforms by", uint256(returnDiff));
        } else {
            console.log("Annualized Return: Quarterly outperforms by", uint256(-returnDiff));
        }
        
        int256 sharpeDiff = monthlySharpeRatio - quarterlySharpeRatio;
        if (sharpeDiff > 0) {
            console.log("Sharpe Ratio: Monthly outperforms by", uint256(sharpeDiff));
        } else {
            console.log("Sharpe Ratio: Quarterly outperforms by", uint256(-sharpeDiff));
        }
        
        vm.stopBroadcast();
    }
}
