// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../backtesting/BacktestingFramework.sol";
import "../backtesting/metrics/MetricsCalculator.sol";

/**
 * @title TestMaxDrawdown
 * @notice Script to test the max drawdown calculation
 */
contract TestMaxDrawdown is Script {
    MetricsCalculator public metricsCalculator;
    
    function setUp() public {
        // This function is called before the script runs
    }
    
    function run() public {
        vm.startBroadcast();
        
        console2.log("=== Testing Max Drawdown Calculation ===");
        
        // Create metrics calculator with 2% risk-free rate
        metricsCalculator = new MetricsCalculator(200);
        
        // Create test data with a clear drawdown pattern
        BacktestingFramework.BacktestResult[] memory results = new BacktestingFramework.BacktestResult[](10);
        
        // Starting at 100, going up to 120, then dropping to 80 (33% drawdown from peak)
        results[0] = BacktestingFramework.BacktestResult({
            timestamp: 1000,
            portfolioValue: 100 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[1] = BacktestingFramework.BacktestResult({
            timestamp: 2000,
            portfolioValue: 110 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[2] = BacktestingFramework.BacktestResult({
            timestamp: 3000,
            portfolioValue: 120 * 10**18, // Peak
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[3] = BacktestingFramework.BacktestResult({
            timestamp: 4000,
            portfolioValue: 110 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[4] = BacktestingFramework.BacktestResult({
            timestamp: 5000,
            portfolioValue: 100 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[5] = BacktestingFramework.BacktestResult({
            timestamp: 6000,
            portfolioValue: 90 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[6] = BacktestingFramework.BacktestResult({
            timestamp: 7000,
            portfolioValue: 80 * 10**18, // Bottom
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[7] = BacktestingFramework.BacktestResult({
            timestamp: 8000,
            portfolioValue: 90 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[8] = BacktestingFramework.BacktestResult({
            timestamp: 9000,
            portfolioValue: 100 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        results[9] = BacktestingFramework.BacktestResult({
            timestamp: 10000,
            portfolioValue: 110 * 10**18,
            assetValues: new uint256[](0),
            assetWeights: new uint256[](0),
            yieldHarvested: 0,
            rebalanced: false,
            gasCost: 0
        });
        
        // Calculate max drawdown
        uint256 maxDrawdown = metricsCalculator.calculateMaxDrawdown(results);
        
        // Expected max drawdown: (120 - 80) / 120 = 0.333... = 33.33%
        // Scaled by 1e18, so expected value is 0.333... * 1e18
        uint256 expectedDrawdown = 333333333333333333; // 33.33% with 18 decimals
        
        console2.log("Max Drawdown (raw):", maxDrawdown);
        console2.log("Max Drawdown (%):", maxDrawdown / 1e16, "%");
        console2.log("Expected Drawdown (%):", expectedDrawdown / 1e16, "%");
        
        if (maxDrawdown > 0) {
            console2.log("SUCCESS: Max drawdown calculation is working");
        } else {
            console2.log("ERROR: Max drawdown calculation returned 0");
        }
        
        vm.stopBroadcast();
    }
}
