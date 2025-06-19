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
 * @title QuickDebugYield
 * @notice Simplified script to debug yield harvesting with fewer checkpoints
 */
contract QuickDebugYield is Script {
    // Constants for configuration
    uint256 constant START_TIMESTAMP = 1690848000; // Aug 1, 2023
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
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Quick Debug Yield Test ===");
        
        // Initialize data provider
        dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Load historical price data
        HistoricalPriceData.setupHistoricalPriceData(dataProvider);
        
        // Initialize simulation engine
        simulationEngine = new VaultSimulationEngine(
            dataProvider,
            USDC,              // Base asset
            INITIAL_DEPOSIT,   // Initial deposit
            500,               // Rebalance threshold (5%)
            90 days,           // Rebalance interval (quarterly)
            10,                // Management fee (0.1%)
            0                  // Performance fee (0%)
        );
        
        // Configure assets
        simulationEngine.addAsset(
            SP500_TOKEN,
            SP500_WRAPPER,
            6000,    // 60% target weight
            false    // Not yield generating
        );
        
        simulationEngine.addAsset(
            RWA_TOKEN,
            RWA_WRAPPER,
            4000,    // 40% target weight
            true     // Yield generating
        );
        
        // Initialize the simulation engine
        simulationEngine.initialize(START_TIMESTAMP);
        
        console2.log("\n=== Testing at Key Checkpoints ===");
        console2.log("Timestamp, Portfolio Value, RWA Value, SP500 Value, RWA Yield Rate, Yield Harvested");
        
        // Define a few key checkpoints (one per quarter)
        uint256[] memory checkpoints = new uint256[](5);
        checkpoints[0] = START_TIMESTAMP;                // Aug 1, 2023
        checkpoints[1] = START_TIMESTAMP + 90 days;      // Oct 30, 2023
        checkpoints[2] = START_TIMESTAMP + 180 days;     // Jan 28, 2024
        checkpoints[3] = START_TIMESTAMP + 270 days;     // Apr 27, 2024
        checkpoints[4] = START_TIMESTAMP + 360 days;     // Jul 26, 2024
        
        // Run simulation at each checkpoint
        for (uint256 i = 0; i < checkpoints.length; i++) {
            uint256 currentTimestamp = checkpoints[i];
            
            // Run a single step
            uint256 portfolioValue;
            uint256[] memory assetValues;
            uint256 yieldHarvested;
            uint256[] memory assetWeights;
            bool rebalanced;
            uint256 gasCost;
            
            (portfolioValue, assetValues, assetWeights, yieldHarvested, rebalanced, gasCost) = 
                simulationEngine.runStep(currentTimestamp);
            
            // Get yield rate
            uint256 rwaYieldRate = dataProvider.getYieldRate(RWA_WRAPPER, currentTimestamp);
            
            // Print results
            console2.log(string(abi.encodePacked(
                vm.toString(currentTimestamp), ", ",
                vm.toString(portfolioValue / 1e18), ", ",
                vm.toString(assetValues[1] / 1e18), ", ", // RWA value
                vm.toString(assetValues[0] / 1e18), ", ", // SP500 value
                vm.toString(rwaYieldRate), ", ",
                vm.toString(yieldHarvested / 1e18)
            )));
            
            // Debug yield calculation details
            console2.log("--- Yield Debug ---");
            if (i > 0) {
                uint256 timeElapsed = currentTimestamp - checkpoints[i-1];
                uint256 yearFraction = (timeElapsed * 1e18) / 365 days;
                uint256 expectedYield = (assetValues[1] * rwaYieldRate * yearFraction) / (10000 * 1e18);
                
                console2.log(string(abi.encodePacked(
                    "Time elapsed: ", vm.toString(timeElapsed / 1 days), " days, ",
                    "Year fraction: ", vm.toString(yearFraction / 1e16), "%, ",
                    "Expected quarterly yield: ~", vm.toString(expectedYield / 1e18)
                )));
            }
        }
        
        vm.stopBroadcast();
    }
}
