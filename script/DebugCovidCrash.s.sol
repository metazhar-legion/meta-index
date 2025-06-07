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
 * @title DebugCovidCrash
 * @notice Script to debug portfolio values during the COVID crash period
 */
contract DebugCovidCrash is Script {
    // Constants for configuration
    uint256 constant START_TIMESTAMP = 1580688000; // Feb 3, 2020 (pre-crash)
    uint256 constant END_TIMESTAMP = 1585785600;   // Apr 2, 2020 (post-crash)
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
    
    function setUp() public {
        // This function is called before the script runs
    }
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Debugging COVID Crash Period ===");
        console2.log("Start: Feb 3, 2020 - End: Apr 2, 2020");
        
        // Initialize data provider
        dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Load real historical data
        console2.log("Loading historical price data...");
        HistoricalPriceData.setupHistoricalPriceData(dataProvider);
        console2.log("Real historical price data loaded successfully.");
        
        // Print raw price data for the COVID crash period
        console2.log("\n=== Raw S&P 500 Price Data ===");
        console2.log("Date, Price");
        
        // Key dates during COVID crash
        uint256[] memory dates = new uint256[](6);
        dates[0] = 1580688000; // Feb 3, 2020
        dates[1] = 1581465600; // Feb 12, 2020 (peak)
        dates[2] = 1582502400; // Feb 24, 2020
        dates[3] = 1583280000; // Mar 4, 2020
        dates[4] = 1584057600; // Mar 13, 2020
        dates[5] = 1585008000; // Mar 24, 2020 (bottom)
        
        uint256 peakPrice = 0;
        uint256 bottomPrice = type(uint256).max;
        
        for (uint256 i = 0; i < dates.length; i++) {
            uint256 price = dataProvider.getAssetPrice(SP500_TOKEN, dates[i]);
            console2.log("%d, %d", dates[i], price / 1e18);
            
            if (price > peakPrice) {
                peakPrice = price;
            }
            if (price < bottomPrice) {
                bottomPrice = price;
            }
        }
        
        uint256 drawdown = ((peakPrice - bottomPrice) * 1e18) / peakPrice;
        console2.log("Peak Price: %d", peakPrice / 1e18);
        console2.log("Bottom Price: %d", bottomPrice / 1e18);
        console2.log("Raw Price Drawdown: %d%%", drawdown / 1e16);
        
        // Now run a simulation with this data
        console2.log("\n=== Running Simulation ===");
        
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
        
        // Initialize the simulation engine
        simulationEngine.initialize(START_TIMESTAMP);
        
        // Run simulation steps manually and track portfolio values
        console2.log("\n=== Portfolio Values During COVID Crash ===");
        console2.log("Date, Portfolio Value, S&P 500 Price");
        
        uint256 timestamp = START_TIMESTAMP;
        uint256 peakValue = 0;
        uint256 bottomValue = type(uint256).max;
        
        while (timestamp <= END_TIMESTAMP) {
            // Run simulation step
            (
                uint256 portfolioValue,
                uint256[] memory assetValues,
                uint256[] memory assetWeights,
                uint256 yieldHarvested,
                bool rebalanced,
                uint256 gasCost
            ) = simulationEngine.runStep(timestamp);
            
            // Get S&P 500 price for this timestamp
            uint256 sp500Price = dataProvider.getAssetPrice(SP500_TOKEN, timestamp);
            
            // Print values
            console2.log("%d, %d, %d", timestamp, portfolioValue / 1e18, sp500Price / 1e18);
            
            // Track peak and bottom values
            if (portfolioValue > peakValue) {
                peakValue = portfolioValue;
            }
            if (portfolioValue < bottomValue) {
                bottomValue = portfolioValue;
            }
            
            // Move to next day
            timestamp += TIME_STEP;
        }
        
        // Calculate portfolio drawdown
        uint256 portfolioDrawdown = ((peakValue - bottomValue) * 1e18) / peakValue;
        console2.log("\n=== Portfolio Drawdown Analysis ===");
        console2.log("Peak Portfolio Value: %d", peakValue / 1e18);
        console2.log("Bottom Portfolio Value: %d", bottomValue / 1e18);
        console2.log("Portfolio Drawdown: %d%%", portfolioDrawdown / 1e16);
        console2.log("S&P 500 Price Drawdown: %d%%", drawdown / 1e16);
        
        vm.stopBroadcast();
    }
}
