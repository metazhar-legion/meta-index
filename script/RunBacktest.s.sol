// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../backtesting/BacktestingFramework.sol";
import "../backtesting/data/HistoricalDataProvider.sol";
import "../backtesting/simulation/VaultSimulationEngine.sol";
import "../backtesting/metrics/MetricsCalculator.sol";
import "../backtesting/visualization/ResultsExporter.sol";

/**
 * @title RunBacktest
 * @notice Script to run a simple backtest with a 20/80 allocation
 * @dev Use with Forge script to run the backtest and analyze results
 */
contract RunBacktest is Script {
    // Constants for configuration
    uint256 constant START_TIMESTAMP = 1577836800; // Jan 1, 2020
    uint256 constant END_TIMESTAMP = 1719792000;   // Jun 30, 2024
    uint256 constant TIME_STEP = 1 days;           // Daily steps
    uint256 constant INITIAL_DEPOSIT = 10000 * 10**18; // 10,000 USDC
    
    // Asset addresses (placeholders)
    address constant USDC = address(0x1);
    address constant SP500_TOKEN = address(0x2);
    address constant RWA_TOKEN = address(0x3);
    address constant SP500_WRAPPER = address(0x4);
    address constant RWA_WRAPPER = address(0x5);
    
    // Backtest components
    BacktestingFramework public backtestingFramework;
    HistoricalDataProvider public dataProvider;
    VaultSimulationEngine public simulationEngine;
    MetricsCalculator public metricsCalculator;
    ResultsExporter public resultsExporter;
    
    function setUp() public {
        // This function is called before the script runs
    }
    
    function run() public {
        vm.startBroadcast();
        
        console.log("=== Starting Backtest ===");
        
        // Initialize components
        dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Create simulation engine with configuration
        simulationEngine = new VaultSimulationEngine(
            dataProvider,
            USDC,              // Base asset
            INITIAL_DEPOSIT,   // Initial deposit
            500,               // Rebalance threshold (5%)
            30 days,           // Rebalance interval
            100,               // Management fee (1%)
            1000               // Performance fee (10%)
        );
        
        // Add assets to simulation engine (20/80 allocation)
        simulationEngine.addAsset(RWA_TOKEN, RWA_WRAPPER, 2000, true);    // 20% RWA with yield
        simulationEngine.addAsset(SP500_TOKEN, SP500_WRAPPER, 8000, false); // 80% S&P 500
        
        // Create metrics calculator with 2% risk-free rate
        metricsCalculator = new MetricsCalculator(200);
        
        // Create backtesting framework with all dependencies
        backtestingFramework = new BacktestingFramework(
            dataProvider,
            simulationEngine,
            metricsCalculator
        );
        
        // Create results exporter
        resultsExporter = new ResultsExporter(backtestingFramework);
        
        // Set up historical data
        setupHistoricalData();
        
        // Initialize the simulation engine
        simulationEngine.initialize(START_TIMESTAMP);
        
        // Configure and run the backtest
        backtestingFramework.configure(
            START_TIMESTAMP,
            END_TIMESTAMP,
            TIME_STEP
        );
        
        bool success = backtestingFramework.runBacktest();
        require(success, "Backtest failed to run");
        uint256 resultCount = backtestingFramework.getResultCount();
        
        console.log("Backtest completed with %d results", resultCount);
        
        // Calculate metrics
        (
            int256 sharpeRatio,
            uint256 maxDrawdown,
            int256 annualizedReturn,
            uint256 volatility
        ) = backtestingFramework.calculateMetrics();
        
        // Get initial and final values
        BacktestingFramework.BacktestResult memory firstResult = backtestingFramework.getResult(0);
        BacktestingFramework.BacktestResult memory lastResult = backtestingFramework.getResult(resultCount - 1);
        
        uint256 initialValue = firstResult.portfolioValue;
        uint256 finalValue = lastResult.portfolioValue;
        
        // Calculate total return
        int256 totalReturn = 0;
        if (initialValue > 0) {
            totalReturn = int256((finalValue * 1e18) / initialValue) - int256(1e18);
        }
        
        // Log results
        console.log("=== Backtest Results ===");
        console.log("Initial Value: %d", initialValue);
        console.log("Final Value: %d", finalValue);
        console.log("Total Return: %d", totalReturn);
        console.log("Annualized Return: %d", annualizedReturn);
        console.log("Sharpe Ratio: %d", sharpeRatio);
        console.log("Max Drawdown: %d", maxDrawdown);
        console.log("Volatility: %d", volatility);
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Set up historical price data for assets
     */
    function setupHistoricalData() internal {
        // Set up S&P 500 price data (simplified example with annual returns)
        // Using approximate S&P 500 yearly returns for 2020-2024
        uint256 sp500BasePrice = 100 * 10**18; // Starting price
        
        // 2020: ~16% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP, sp500BasePrice);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 90 days, sp500BasePrice * 85 / 100); // COVID crash
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 180 days, sp500BasePrice * 95 / 100); // Recovery
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days, sp500BasePrice * 116 / 100); // Year-end
        
        // 2021: ~27% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days + 90 days, sp500BasePrice * 125 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days + 180 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days + 270 days, sp500BasePrice * 140 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 2, sp500BasePrice * 147 / 100);
        
        // 2022: ~-19% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 2 + 90 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 2 + 180 days, sp500BasePrice * 125 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 2 + 270 days, sp500BasePrice * 120 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 3, sp500BasePrice * 119 / 100);
        
        // 2023: ~24% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 3 + 90 days, sp500BasePrice * 125 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 3 + 180 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 3 + 270 days, sp500BasePrice * 140 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 4, sp500BasePrice * 148 / 100);
        
        // 2024: ~12% return (partial year)
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 4 + 90 days, sp500BasePrice * 155 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 4 + 180 days, sp500BasePrice * 160 / 100);
        
        // Set up RWA price data (more stable with lower returns)
        uint256 rwaBasePrice = 100 * 10**18; // Starting price
        
        // 2020: ~5% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP, rwaBasePrice);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 90 days, rwaBasePrice * 98 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 180 days, rwaBasePrice * 101 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days, rwaBasePrice * 105 / 100);
        
        // 2021: ~7% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days + 180 days, rwaBasePrice * 108 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 2, rwaBasePrice * 112 / 100);
        
        // 2022: ~3% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 2 + 180 days, rwaBasePrice * 114 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 3, rwaBasePrice * 115 / 100);
        
        // 2023: ~6% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 3 + 180 days, rwaBasePrice * 118 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 4, rwaBasePrice * 122 / 100);
        
        // 2024: ~3% return (partial year)
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 4 + 180 days, rwaBasePrice * 125 / 100);
        
        // Set up yield rates for RWA (assuming 4% annual yield)
        uint256 rwaYieldRate = 400; // 4% in basis points
        dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP + 365 days, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP + 365 days * 2, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP + 365 days * 3, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP + 365 days * 4, rwaYieldRate);
    }
}
