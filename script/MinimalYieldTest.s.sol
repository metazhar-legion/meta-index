// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../backtesting/data/HistoricalDataProvider.sol";
import "../backtesting/simulation/VaultSimulationEngine.sol";

/**
 * @title MinimalYieldTest
 * @notice Minimal script to test yield harvesting functionality
 */
contract MinimalYieldTest is Script {
    // Asset addresses (placeholders)
    address constant USDC = address(0x1);
    address constant RWA_TOKEN = address(0x3);
    address constant RWA_WRAPPER = address(0x5);
    
    // Test timestamps - using specific dates to avoid any date conversion
    uint256 constant START_DATE = 1690848000; // Aug 1, 2023
    uint256 constant NEXT_DATE = 1698624000;  // Oct 30, 2023 (90 days later)
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Minimal Yield Test ===");
        
        // Initialize data provider
        HistoricalDataProvider dataProvider = new HistoricalDataProvider(
            "Test Provider",
            "Test Yield Data"
        );
        
        // Set up a test yield rate
        uint256 yieldRate = 400; // 4% annual yield in basis points
        dataProvider.setYieldRate(RWA_WRAPPER, START_DATE, yieldRate);
        
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
        simulationEngine.initialize(START_DATE);
        
        console2.log("Initial setup complete");
        console2.log("Step 1: Running first step (initialization)");
        
        // Run first step
        uint256 portfolioValue1;
        uint256 yieldHarvested1;
        {
            (portfolioValue1, , , yieldHarvested1, ,) = simulationEngine.runStep(START_DATE);
        }
        
        console2.log(string(abi.encodePacked(
            "Initial portfolio value: ", vm.toString(portfolioValue1 / 1e18),
            ", Yield harvested: ", vm.toString(yieldHarvested1 / 1e18)
        )));
        
        console2.log("Step 2: Running second step (90 days later)");
        
        // Run second step
        uint256 portfolioValue2;
        uint256 yieldHarvested2;
        {
            (portfolioValue2, , , yieldHarvested2, ,) = simulationEngine.runStep(NEXT_DATE);
        }
        
        console2.log(string(abi.encodePacked(
            "Portfolio value after 90 days: ", vm.toString(portfolioValue2 / 1e18),
            ", Yield harvested: ", vm.toString(yieldHarvested2 / 1e18)
        )));
        
        // Calculate expected yield
        uint256 timeElapsed = NEXT_DATE - START_DATE;
        uint256 yearFraction = (timeElapsed * 1e18) / 365 days;
        uint256 expectedYield = (portfolioValue1 * yieldRate * yearFraction) / (10000 * 1e18);
        
        console2.log("--- Yield Calculation Verification ---");
        console2.log(string(abi.encodePacked(
            "Time elapsed: ", vm.toString(timeElapsed / 1 days), " days"
        )));
        console2.log(string(abi.encodePacked(
            "Year fraction: ", vm.toString(yearFraction / 1e16), "%"
        )));
        console2.log(string(abi.encodePacked(
            "Expected yield: ", vm.toString(expectedYield / 1e18)
        )));
        console2.log(string(abi.encodePacked(
            "Actual yield: ", vm.toString(yieldHarvested2 / 1e18)
        )));
        console2.log(string(abi.encodePacked(
            "Verification: ", 
            yieldHarvested2 == expectedYield ? "PASSED (OK)" : "FAILED (ERROR)"
        )));
        
        vm.stopBroadcast();
    }
}
