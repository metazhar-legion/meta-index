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
 * @title DebugGrowthIssue
 * @notice Script to debug the exponential growth issue in portfolio values
 */
contract DebugGrowthIssue is Script {
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
        
        console2.log("=== Debugging Growth Issue (Aug 2023 - Jun 2024) ===");
        
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
        
        // Create metrics calculator with 2% risk-free rate
        metricsCalculator = new MetricsCalculator(200); // 200 basis points = 2%
        
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
        
        // Run the backtest manually step by step to debug
        console2.log("\n=== Manual Step-by-Step Execution ===");
        console2.log("Date, Portfolio Value, RWA Value, SP500 Value, RWA Yield Rate, Yield Harvested, Time Elapsed, Year Fraction");
        
        uint256 currentTimestamp = START_TIMESTAMP;
        uint256 lastYieldTimestamp = START_TIMESTAMP;
        uint256 prevPortfolioValue = INITIAL_DEPOSIT;
        
        while (currentTimestamp <= END_TIMESTAMP) {
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
            
            // Calculate time elapsed and year fraction for yield
            uint256 timeElapsed = currentTimestamp - lastYieldTimestamp;
            uint256 yearFraction = (timeElapsed * 1e18) / 365 days;
            
            // Print detailed information
            string memory output = string(abi.encodePacked(
                vm.toString(currentTimestamp), ", ",
                vm.toString(portfolioValue / 1e18), ", ",
                vm.toString(assetValues.length > 0 ? assetValues[0] / 1e18 : 0), ", ",
                vm.toString(assetValues.length > 1 ? assetValues[1] / 1e18 : 0), ", ",
                vm.toString(rwaYieldRate), ", ",
                vm.toString(yieldHarvested / 1e18), ", ",
                vm.toString(timeElapsed), ", ",
                vm.toString(yearFraction / 1e18)
            ));
            console2.log(output);
            
            // If yield was harvested, update lastYieldTimestamp
            if (yieldHarvested > 0) {
                lastYieldTimestamp = currentTimestamp;
            }
            
            // If we see a large jump in portfolio value, print more details
            if (currentTimestamp > START_TIMESTAMP && portfolioValue > prevPortfolioValue * 2) {
                console2.log(string(abi.encodePacked(
                    "LARGE JUMP DETECTED at timestamp ", vm.toString(currentTimestamp)
                )));
                console2.log(string(abi.encodePacked(
                    "Previous value: ", vm.toString(prevPortfolioValue / 1e18),
                    ", New value: ", vm.toString(portfolioValue / 1e18)
                )));
                console2.log(string(abi.encodePacked(
                    "Yield harvested: ", vm.toString(yieldHarvested / 1e18)
                )));
                console2.log(string(abi.encodePacked(
                    "Rebalanced: ", rebalanced ? "Yes" : "No"
                )));
            }
            
            // Store current portfolio value for next iteration
            prevPortfolioValue = portfolioValue;
                    console2.log(string(abi.encodePacked(
                        "Yield harvested: ", vm.toString(yieldHarvested / 1e18)
                    )));
                    console2.log(string(abi.encodePacked(
                        "Rebalanced: ", rebalanced ? "Yes" : "No"
                    )));
                }
            }
            
            // Move to next day
            currentTimestamp += TIME_STEP;
        }
        
        vm.stopBroadcast();
    }
}
