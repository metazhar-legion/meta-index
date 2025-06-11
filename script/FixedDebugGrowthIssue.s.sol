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
 * @title FixedDebugGrowthIssue
 * @notice Script to debug the exponential growth issue in portfolio values
 */
contract FixedDebugGrowthIssue is Script {
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
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Debugging Growth Issue (Aug 2023 - Jun 2024) ===");
        
        // Initialize data provider
        dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Load historical price data
        HistoricalPriceData.setupHistoricalPriceData(dataProvider);
        
        // Initialize simulation engine
        simulationEngine = new VaultSimulationEngine(dataProvider);
        
        // Initialize metrics calculator
        metricsCalculator = new MetricsCalculator();
        
        // Initialize backtesting framework
        backtestingFramework = new BacktestingFramework(
            dataProvider,
            simulationEngine,
            metricsCalculator
        );
        
        // Configure assets
        simulationEngine.addAsset(
            SP500_TOKEN,
            SP500_WRAPPER,
            "S&P 500 Index",
            false,  // Not yield generating
            6000    // 60% target weight
        );
        
        simulationEngine.addAsset(
            RWA_TOKEN,
            RWA_WRAPPER,
            "Real World Asset",
            true,   // Yield generating
            4000    // 40% target weight
        );
        
        // Set initial deposit
        simulationEngine.deposit(INITIAL_DEPOSIT);
        
        // Initialize the simulation engine
        simulationEngine.initialize(START_TIMESTAMP);
        
        console2.log("\n=== Manual Step-by-Step Execution ===");
        console2.log("Date, Portfolio Value, RWA Value, SP500 Value, RWA Yield Rate, Yield Harvested");
        
        // Loop through each day
        for (uint256 i = 0; i <= (END_TIMESTAMP - START_TIMESTAMP) / TIME_STEP; i++) {
            uint256 currentTimestamp = START_TIMESTAMP + (i * TIME_STEP);
            
            // Run a single step
            (
                uint256 portfolioValue,
                uint256[] memory assetValues,
                uint256[] memory assetWeights,
                uint256 yieldHarvested,
                bool rebalanced,
                uint256 gasCost
            ) = simulationEngine.runStep(currentTimestamp);
            
            // Get asset prices and yield rate
            uint256 rwaPrice = dataProvider.getAssetPrice(RWA_TOKEN, currentTimestamp);
            uint256 sp500Price = dataProvider.getAssetPrice(SP500_TOKEN, currentTimestamp);
            uint256 rwaYieldRate = dataProvider.getYieldRate(RWA_WRAPPER, currentTimestamp);
            
            // Print results
            console2.log(
                vm.toString(currentTimestamp), 
                vm.toString(portfolioValue / 1e18),
                vm.toString(assetValues[0] / 1e18),
                vm.toString(assetValues[1] / 1e18),
                vm.toString(rwaYieldRate),
                vm.toString(yieldHarvested / 1e18)
            );
        }
        
        vm.stopBroadcast();
    }
}
