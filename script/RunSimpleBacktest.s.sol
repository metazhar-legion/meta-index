// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../backtesting/samples/SimplePortfolioBacktest.sol";

/**
 * @title RunSimpleBacktest
 * @notice Script to run the SimplePortfolioBacktest
 * @dev Use with Forge script to run the backtest and analyze results
 */
contract RunSimpleBacktest is Script {
    // Constants for configuration
    uint256 constant START_TIMESTAMP = 1577836800; // Jan 1, 2020
    uint256 constant END_TIMESTAMP = 1719792000;   // Jun 30, 2024
    uint256 constant TIME_STEP = 1 days;           // Daily steps
    uint256 constant INITIAL_DEPOSIT = 10000 * 10**18; // 10,000 USDC
    
    function setUp() public {
        // This function is called before the script runs
    }
    
    function run() public {
        vm.startBroadcast();
        
        console.log("=== Starting Simple Portfolio Backtest ===");
        
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
        console.log("=== Backtest Results ===");
        console.log("Result Count: %d", resultCount);
        console.log("Initial Value: %d", initialValue);
        console.log("Final Value: %d", finalValue);
        console.log("Total Return: %d", totalReturn);
        console.log("Annualized Return: %d", annualizedReturn);
        console.log("Sharpe Ratio: %d", sharpeRatio);
        console.log("Max Drawdown: %d", maxDrawdown);
        console.log("Volatility: %d", volatility);
        
        vm.stopBroadcast();
    }
}
