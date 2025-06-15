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
        simulationEngine = new VaultSimulationEngine(
            dataProvider,
            USDC,              // Base asset
            INITIAL_DEPOSIT,   // Initial deposit
            500,               // Rebalance threshold (5%)
            90 days,           // Rebalance interval (quarterly)
            10,                // Management fee (0.1%)
            0                  // Performance fee (0%)
        );
        
        // Initialize metrics calculator with 2% risk-free rate
        metricsCalculator = new MetricsCalculator(200); // 200 basis points = 2%
        
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
            6000,    // 60% target weight
            false    // Not yield generating
        );
        
        simulationEngine.addAsset(
            RWA_TOKEN,
            RWA_WRAPPER,
            4000,    // 40% target weight
            true     // Yield generating
        );
        
        // Initial deposit is already set in the constructor
        
        // Initialize the simulation engine
        simulationEngine.initialize(START_TIMESTAMP);
        
        console2.log("\n=== Manual Step-by-Step Execution ===");
        console2.log("Date, Portfolio Value, RWA Value, SP500 Value, RWA Yield Rate, Yield Harvested");
        
        // Run simulation at key points (monthly) instead of daily to reduce output
        uint256[] memory checkpoints = new uint256[](12);
        for (uint256 i = 0; i < 12; i++) {
            checkpoints[i] = START_TIMESTAMP + (i * 30 days);
        }
        
        // Run simulation at each checkpoint
        for (uint256 i = 0; i < checkpoints.length; i++) {
            uint256 currentTimestamp = checkpoints[i];
            
            // Run a single step
            uint256 portfolioValue;
            uint256[] memory assetValues;
            uint256 yieldHarvested;
            {
                uint256[] memory assetWeights;
                bool rebalanced;
                uint256 gasCost;
                (portfolioValue, assetValues, assetWeights, yieldHarvested, rebalanced, gasCost) = 
                    simulationEngine.runStep(currentTimestamp);
            }
            
            // Get yield rate
            uint256 rwaYieldRate = dataProvider.getYieldRate(RWA_WRAPPER, currentTimestamp);
            
            // Print results in CSV format
            string memory date = timestampToDate(currentTimestamp);
            console2.log(string(abi.encodePacked(
                date, ", ",
                vm.toString(portfolioValue / 1e18), ", ",
                vm.toString(assetValues[1] / 1e18), ", ", // RWA value
                vm.toString(assetValues[0] / 1e18), ", ", // SP500 value
                vm.toString(rwaYieldRate), ", ",
                vm.toString(yieldHarvested / 1e18)
            )));
            
            // Debug yield calculation for quarterly checkpoints
            if (i % 3 == 0) {
                console2.log("--- Quarterly Yield Debug ---");
                console2.log(string(abi.encodePacked(
                    "Date: ", date,
                    ", Portfolio: ", vm.toString(portfolioValue / 1e18),
                    ", RWA Value: ", vm.toString(assetValues[1] / 1e18),
                    ", Yield Rate: ", vm.toString(rwaYieldRate),
                    ", Yield Harvested: ", vm.toString(yieldHarvested / 1e18)
                )));
            }
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Convert a Unix timestamp to a readable date string (YYYY-MM-DD)
     * @param timestamp The Unix timestamp to convert
     * @return A string representation of the date
     */
    function timestampToDate(uint256 timestamp) internal pure returns (string memory) {
        // Convert timestamp to days since Unix epoch
        uint256 daysSinceEpoch = timestamp / 86400;
        
        // Use a simplified algorithm to calculate year, month, day
        // This is an approximation and doesn't account for leap years perfectly
        uint256 year = 1970;
        uint256 daysInYear = 365;
        
        // Find the year
        while (daysSinceEpoch >= daysInYear) {
            daysSinceEpoch -= daysInYear;
            year++;
            // Simplified leap year calculation
            daysInYear = ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) ? 366 : 365;
        }
        
        // Array of days in each month (non-leap year)
        uint8[12] memory daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        
        // Adjust February for leap years
        if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
            daysInMonth[1] = 29;
        }
        
        // Find the month and day
        uint256 month = 0;
        while (month < 12 && daysSinceEpoch >= daysInMonth[month]) {
            daysSinceEpoch -= daysInMonth[month];
            month++;
        }
        
        // Add 1 to month (1-indexed) and day (1-indexed)
        month += 1;
        uint256 day = daysSinceEpoch + 1;
        
        // Format the date as YYYY-MM-DD
        return string(abi.encodePacked(
            vm.toString(year), "-",
            month < 10 ? string(abi.encodePacked("0", vm.toString(month))) : vm.toString(month), "-",
            day < 10 ? string(abi.encodePacked("0", vm.toString(day))) : vm.toString(day)
        ));
    }
}
