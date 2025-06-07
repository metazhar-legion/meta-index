// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../backtesting/BacktestingFramework.sol";
import "../backtesting/data/HistoricalDataProvider.sol";
import "../backtesting/simulation/VaultSimulationEngine.sol";
import "../backtesting/metrics/MetricsCalculator.sol";
import "../data/historical/HistoricalPriceData.sol";

// No need for additional interface imports

/**
 * @title DebugEndPeriod
 * @notice Script to debug portfolio values during the last few months of the backtest
 */
contract DebugEndPeriod is Script {
    // Constants for configuration
    uint256 constant START_TIMESTAMP = 1690848000; // Aug 1, 2023
    uint256 constant END_TIMESTAMP = 1719360000;   // Jun 26, 2024
    uint256 constant TIME_STEP = 1 days;           // Daily steps
    uint256 constant INITIAL_DEPOSIT = 10000 * 10**18; // 10,000 USDC
    
    // Asset addresses (placeholders)
    address constant USDC = address(0x1);
    address constant SP500_TOKEN = address(0x2);
    address constant RWA_TOKEN = address(0x3);
    address constant SP500_WRAPPER = address(0x4);
    address constant RWA_WRAPPER = address(0x5);
    
    // Backtest components
    HistoricalDataProvider public dataProvider;
    VaultSimulationEngine public simulationEngine;
    MetricsCalculator public metricsCalculator;
    BacktestingFramework public backtestingFramework;
    
    function setUp() public {
        // This function is called before the script runs
    }
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Debugging End Period (Aug 2023 - Jun 2024) ===");
        
        // Initialize data provider
        dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Load real historical data
        console2.log("Loading historical price data...");
        HistoricalPriceData.setupHistoricalPriceData(dataProvider);
        console2.log("Real historical price data loaded successfully.");
        
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
        
        // Create metrics calculator
        metricsCalculator = new MetricsCalculator();
        
        // Create backtesting framework
        backtestingFramework = new BacktestingFramework(
            dataProvider,
            simulationEngine,
            metricsCalculator
        );
        
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
        
        // Debug portfolio values
        console2.log("\n=== Portfolio Value Analysis ===");
        console2.log("Date, Portfolio Value, S&P 500 Price, RWA Price, RWA Yield Rate, Asset Values, Yield Harvested");
        
        for (uint256 i = 0; i < resultCount; i += 7) { // Sample weekly
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            
            // Get asset prices for this timestamp
            uint256 sp500Price = dataProvider.getAssetPrice(SP500_TOKEN, result.timestamp);
            uint256 rwaPrice = dataProvider.getAssetPrice(RWA_TOKEN, result.timestamp);
            uint256 rwaYieldRate = dataProvider.getYieldRate(RWA_WRAPPER, result.timestamp);
            
            // Print detailed information
            string memory output = string(abi.encodePacked(
                vm.toString(result.timestamp), ", ",
                vm.toString(result.portfolioValue / 1e18), ", ",
                vm.toString(sp500Price / 1e18), ", ",
                vm.toString(rwaPrice / 1e18), ", ",
                vm.toString(rwaYieldRate), ", ",
                vm.toString(result.assetValues.length > 0 ? result.assetValues[0] / 1e18 : 0), "/",
                vm.toString(result.assetValues.length > 1 ? result.assetValues[1] / 1e18 : 0), ", ",
                vm.toString(result.yieldHarvested / 1e18)
            ));
            console2.log(output);
            
            // If we see a large jump in portfolio value, print more details
            if (i > 0) {
                BacktestingFramework.BacktestResult memory prevResult = backtestingFramework.getResult(i-1);
                if (result.portfolioValue > prevResult.portfolioValue * 2) {
                    console2.log(string(abi.encodePacked(
                        "LARGE JUMP DETECTED at timestamp ", vm.toString(result.timestamp)
                    )));
                    console2.log(string(abi.encodePacked(
                        "Previous value: ", vm.toString(prevResult.portfolioValue / 1e18),
                        ", New value: ", vm.toString(result.portfolioValue / 1e18)
                    )));
                    console2.log(string(abi.encodePacked(
                        "Yield harvested: ", vm.toString(result.yieldHarvested / 1e18)
                    )));
                    console2.log(string(abi.encodePacked(
                        "Rebalanced: ", result.rebalanced ? "Yes" : "No"
                    )));
                }
            }
        }
        
        vm.stopBroadcast();
    }
}
