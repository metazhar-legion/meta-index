// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../backtesting/BacktestingFramework.sol";
import "../backtesting/data/HistoricalDataProvider.sol";
import "../backtesting/simulation/VaultSimulationEngine.sol";
import "../backtesting/metrics/MetricsCalculator.sol";
import "../data/historical/HistoricalPriceData.sol";

/**
 * @title DebugPortfolioValues
 * @notice Script to debug portfolio values and identify drawdown issues
 */
contract DebugPortfolioValues is Script {
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
    
    function setUp() public {
        // This function is called before the script runs
    }
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Debugging Portfolio Values ===");
        
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
            90 days,           // Rebalance interval (quarterly)
            10,                // Management fee (0.1%)
            0                  // Performance fee (0%)
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
        
        // Load real historical data
        console2.log("Loading historical price data...");
        // Always use real historical data since we know it exists
        console2.log("Using real historical price data...");
        HistoricalPriceData.setupHistoricalPriceData(dataProvider);
        console2.log("Real historical price data loaded successfully.");
        
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
        
        console2.log("Backtest completed with %d results", resultCount);
        
        // Calculate metrics
        (
            int256 sharpeRatio,
            uint256 maxDrawdown,
            int256 annualizedReturn,
            uint256 volatility
        ) = backtestingFramework.calculateMetrics();
        
        console2.log("Max Drawdown: %d", maxDrawdown / 1e16);
        
        // Debug portfolio values
        console2.log("\n=== Portfolio Value Analysis ===");
        console2.log("Timestamp, Portfolio Value, % Change");
        
        uint256 maxValue = 0;
        uint256 minValue = type(uint256).max;
        uint256 maxDrawdownFound = 0;
        uint256 peakValue = 0;
        
        // Print portfolio values and track max/min
        for (uint256 i = 0; i < resultCount; i += 30) { // Sample every ~month
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            
            if (result.portfolioValue > maxValue) {
                maxValue = result.portfolioValue;
            }
            if (result.portfolioValue < minValue) {
                minValue = result.portfolioValue;
            }
            
            // Track drawdown manually
            if (result.portfolioValue > peakValue) {
                peakValue = result.portfolioValue;
            } else if (peakValue > 0) {
                uint256 drawdown = ((peakValue - result.portfolioValue) * 1e18) / peakValue;
                if (drawdown > maxDrawdownFound) {
                    maxDrawdownFound = drawdown;
                }
            }
            
            // Print timestamp and value
            console2.log("%d, %d", result.timestamp, result.portfolioValue / 1e18);
        }
        
        console2.log("\n=== Summary ===");
        console2.log("Initial Value: %d", backtestingFramework.getResult(0).portfolioValue / 1e18);
        console2.log("Final Value: %d", backtestingFramework.getResult(resultCount - 1).portfolioValue / 1e18);
        console2.log("Max Value: %d", maxValue / 1e18);
        console2.log("Min Value: %d", minValue / 1e18);
        console2.log("Max-Min Range: %d", (maxValue - minValue) / 1e18);
        console2.log("Max Drawdown Found: %d%%", maxDrawdownFound / 1e16);
        console2.log("Max Drawdown Reported: %d%%", maxDrawdown / 1e16);
        
        vm.stopBroadcast();
    }
    
    function setupSampleData() internal {
        // Set up S&P 500 price data (simplified example with annual returns)
        uint256 sp500BasePrice = 100 * 10**18; // Starting price
        
        // 2020: ~16% return with COVID crash
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP, sp500BasePrice);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 90 days, sp500BasePrice * 70 / 100); // COVID crash
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 180 days, sp500BasePrice * 90 / 100); // Recovery
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days, sp500BasePrice * 116 / 100); // Year-end
        
        // 2021: ~27% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days + 180 days, sp500BasePrice * 130 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 2, sp500BasePrice * 147 / 100);
        
        // 2022: ~-19% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 2 + 180 days, sp500BasePrice * 120 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 3, sp500BasePrice * 119 / 100);
        
        // 2023: ~24% return
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 3 + 180 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 4, sp500BasePrice * 148 / 100);
        
        // 2024: ~12% return (partial year)
        dataProvider.setAssetPrice(SP500_TOKEN, START_TIMESTAMP + 365 days * 4 + 180 days, sp500BasePrice * 160 / 100);
        
        // Set up RWA price data (more stable with lower returns)
        uint256 rwaBasePrice = 100 * 10**18; // Starting price
        
        // 2020: ~5% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP, rwaBasePrice);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 90 days, rwaBasePrice * 98 / 100); // Small dip
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 180 days, rwaBasePrice * 102 / 100); // Recovery
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days, rwaBasePrice * 105 / 100); // Year-end
        
        // 2021: ~3% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days + 180 days, rwaBasePrice * 107 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 2, rwaBasePrice * 108 / 100);
        
        // 2022: ~-2% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 2 + 180 days, rwaBasePrice * 107 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 3, rwaBasePrice * 106 / 100);
        
        // 2023: ~4% return
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 3 + 180 days, rwaBasePrice * 108 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 4, rwaBasePrice * 110 / 100);
        
        // 2024: ~2% return (partial year)
        dataProvider.setAssetPrice(RWA_TOKEN, START_TIMESTAMP + 365 days * 4 + 180 days, rwaBasePrice * 112 / 100);
        
        // Set up RWA yield rates (4% annual yield)
        uint256 annualYieldRate = 400; // 4% in basis points
        uint256 dailyYieldRate = annualYieldRate / 365;
        
        for (uint256 year = 0; year < 5; year++) {
            dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP + (365 days * year), dailyYieldRate);
        }
    }
}
