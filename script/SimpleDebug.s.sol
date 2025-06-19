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
 * @title SimpleDebug
 * @notice Simple script to debug the exponential growth issue in portfolio values
 */
contract SimpleDebug is Script {
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
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Simple Debug (Aug 2023 - Jun 2024) ===");
        
        // Initialize data provider
        HistoricalDataProvider dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Load real historical data
        console2.log("Loading historical price data...");
        HistoricalPriceData.setupHistoricalPriceData(dataProvider);
        console2.log("Real historical price data loaded successfully.");
        
        // Create simulation engine with configuration
        VaultSimulationEngine simulationEngine = new VaultSimulationEngine(
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
        MetricsCalculator metricsCalculator = new MetricsCalculator(200); // 200 basis points = 2%
        
        // Create backtesting framework
        BacktestingFramework backtestingFramework = new BacktestingFramework(
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
        
        // Run the backtest
        bool success = backtestingFramework.runBacktest();
        require(success, "Backtest failed to run");
        uint256 resultCount = backtestingFramework.getResultCount();
        
        console2.log("Backtest completed with", resultCount, "results");
        
        // Debug portfolio values
        console2.log("\n=== Portfolio Value Analysis ===");
        console2.log("Date, Portfolio Value, RWA Value, SP500 Value, RWA Yield Rate, Yield Harvested");
        
        uint256 prevPortfolioValue = INITIAL_DEPOSIT;
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            
            // Calculate growth percentage from previous step if not the first step
            if (i > 0) {
                BacktestingFramework.BacktestResult memory prevResult = backtestingFramework.getResult(i-1);
                int256 growthPercent = int256((result.portfolioValue * 10000) / prevResult.portfolioValue) - 10000;
                if (growthPercent != 0) {
                    console2.log("Growth since last step: %d basis points", growthPercent);
                }
            }
            prevPortfolioValue = result.portfolioValue;
            
            // Get yield rate
            uint256 rwaYieldRate = dataProvider.getYieldRate(RWA_WRAPPER, result.timestamp);
            
            // Print detailed information using string concatenation for console2.log
            string memory dateStr = vm.toString(result.timestamp);
            string memory portfolioValueStr = vm.toString(result.portfolioValue / 1e18);
            string memory rwaValueStr = vm.toString(result.assetValues.length > 0 ? result.assetValues[0] / 1e18 : 0);
            string memory sp500ValueStr = vm.toString(result.assetValues.length > 1 ? result.assetValues[1] / 1e18 : 0);
            string memory rwaYieldRateStr = vm.toString(rwaYieldRate);
            string memory yieldHarvestedStr = vm.toString(result.yieldHarvested / 1e18);
            
            console2.log(string(abi.encodePacked(
                dateStr, ", ", portfolioValueStr, ", ", rwaValueStr, ", ", 
                sp500ValueStr, ", ", rwaYieldRateStr, ", ", yieldHarvestedStr
            )));
            
            // If we see a large jump in portfolio value, print more details
            if (i > 0 && result.portfolioValue > prevPortfolioValue * 2) {
                console2.log(string(abi.encodePacked(
                    "LARGE JUMP DETECTED at timestamp ", vm.toString(result.timestamp)
                )));
                console2.log(string(abi.encodePacked(
                    "Previous value: ", vm.toString(prevPortfolioValue / 1e18),
                    ", New value: ", vm.toString(result.portfolioValue / 1e18)
                )));
                console2.log(string(abi.encodePacked(
                    "Yield harvested: ", vm.toString(result.yieldHarvested / 1e18)
                )));
                console2.log(string(abi.encodePacked(
                    "Rebalanced: ", result.rebalanced ? "Yes" : "No"
                )));
                
                // Print asset values
                console2.log("Asset values:");
                for (uint256 j = 0; j < result.assetValues.length; j++) {
                    console2.log(string(abi.encodePacked(
                        "Asset ", vm.toString(j), ": ", vm.toString(result.assetValues[j] / 1e18)
                    )));
                }
            }
            
            prevPortfolioValue = result.portfolioValue;
        }
        
        vm.stopBroadcast();
    }
}
