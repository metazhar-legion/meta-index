// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../backtesting/data/HistoricalDataProvider.sol";
import "../backtesting/simulation/VaultSimulationEngine.sol";

/**
 * @title TestYieldHarvesting
 * @notice Simple script to test yield harvesting functionality
 */
contract TestYieldHarvesting is Script {
    // Asset addresses (placeholders)
    address constant USDC = address(0x1);
    address constant RWA_TOKEN = address(0x3);
    address constant RWA_WRAPPER = address(0x5);
    
    // Test timestamps
    uint256 constant START_TIMESTAMP = 1690848000; // Aug 1, 2023
    uint256 constant TEST_TIMESTAMP_1 = START_TIMESTAMP + 30 days;
    uint256 constant TEST_TIMESTAMP_2 = START_TIMESTAMP + 60 days;
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Testing Yield Harvesting ===");
        
        // Initialize data provider
        HistoricalDataProvider dataProvider = new HistoricalDataProvider(
            "Test Data Provider",
            "Test Yield Rates"
        );
        
        // Set up a test yield rate
        uint256 yieldRate = 400; // 4% annual yield in basis points
        dataProvider.setYieldRate(RWA_WRAPPER, START_TIMESTAMP, yieldRate);
        
        // Initialize simulation engine
        VaultSimulationEngine simulationEngine = new VaultSimulationEngine(
            dataProvider,
            USDC,
            10000 * 10**18, // Initial deposit
            500,           // Rebalance threshold (5%)
            90 days,       // Rebalance interval
            0,             // No management fee
            0              // No performance fee
        );
        
        // Add a yield-generating asset
        simulationEngine.addAsset(
            RWA_TOKEN,
            RWA_WRAPPER,
            10000,  // 100% weight
            true    // Yield generating
        );
        
        // Initialize the simulation engine
        simulationEngine.initialize(START_TIMESTAMP);
        
        console2.log("Initial setup complete");
        console2.log("Timestamp, Portfolio Value, Yield Harvested");
        
        // Run first step (initialization)
        uint256 portfolioValue1;
        uint256 yieldHarvested1;
        {
            uint256[] memory assetWeights;
            bool rebalanced;
            uint256 gasCost;
            uint256[] memory assetValues;
            (portfolioValue1, assetValues, assetWeights, yieldHarvested1, rebalanced, gasCost) = simulationEngine.runStep(START_TIMESTAMP);
        }
        
        printStepResult(START_TIMESTAMP, portfolioValue1, yieldHarvested1);
        
        // Run second step (after 30 days)
        uint256 portfolioValue2;
        uint256 yieldHarvested2;
        {
            uint256[] memory assetWeights;
            bool rebalanced;
            uint256 gasCost;
            uint256[] memory assetValues;
            (portfolioValue2, assetValues, assetWeights, yieldHarvested2, rebalanced, gasCost) = simulationEngine.runStep(TEST_TIMESTAMP_1);
        }
        
        printStepResult(TEST_TIMESTAMP_1, portfolioValue2, yieldHarvested2);
        
        // Debug yield calculation
        console2.log("--- Yield Calculation Debug ---");
        uint256 timeElapsed = TEST_TIMESTAMP_1 - START_TIMESTAMP;
        uint256 yearFraction = (timeElapsed * 1e18) / 365 days;
        uint256 expectedYield = (portfolioValue1 * 400 * yearFraction) / (10000 * 1e18);
        
        console2.log(string(abi.encodePacked("Time elapsed: ", vm.toString(timeElapsed / 1 days), " days")));
        console2.log(string(abi.encodePacked("Year fraction: ", vm.toString(yearFraction))));
        console2.log(string(abi.encodePacked("Expected yield: ", vm.toString(expectedYield / 1e18))));
        console2.log(string(abi.encodePacked("Actual yield: ", vm.toString(yieldHarvested2 / 1e18))));
        
        // Run third step (after 60 days)
        uint256 portfolioValue3;
        uint256 yieldHarvested3;
        {
            uint256[] memory assetWeights;
            bool rebalanced;
            uint256 gasCost;
            uint256[] memory assetValues;
            (portfolioValue3, assetValues, assetWeights, yieldHarvested3, rebalanced, gasCost) = simulationEngine.runStep(TEST_TIMESTAMP_2);
        }
        
        printStepResult(TEST_TIMESTAMP_2, portfolioValue3, yieldHarvested3);
        
        vm.stopBroadcast();
    }
    
    function printStepResult(uint256 timestamp, uint256 portfolioValue, uint256 yieldHarvested) internal pure {
        console2.log(string(abi.encodePacked(
            vm.toString(timestamp), ", ",
            vm.toString(portfolioValue / 1e18), ", ",
            vm.toString(yieldHarvested / 1e18)
        )));
    }
}
