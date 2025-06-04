// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BacktestingFramework
 * @notice Main entry point for the backtesting framework
 * @dev This contract orchestrates the backtesting process by connecting data sources,
 *      simulation engines, and metrics calculation
 */
contract BacktestingFramework {
    // Dependencies
    IHistoricalDataProvider public dataProvider;
    ISimulationEngine public simulationEngine;
    IMetricsCalculator public metricsCalculator;
    
    // Configuration
    uint256 public startTimestamp;
    uint256 public endTimestamp;
    uint256 public timeStep;
    
    // Results
    BacktestResult[] public results;
    
    struct BacktestResult {
        uint256 timestamp;
        uint256 portfolioValue;
        uint256[] assetValues;
        uint256[] assetWeights;
        uint256 yieldHarvested;
        bool rebalanced;
        uint256 gasCost;
    }
    
    /**
     * @notice Constructor
     * @param _dataProvider Source of historical price and yield data
     * @param _simulationEngine Engine for simulating vault operations
     * @param _metricsCalculator Calculator for performance metrics
     */
    constructor(
        IHistoricalDataProvider _dataProvider,
        ISimulationEngine _simulationEngine,
        IMetricsCalculator _metricsCalculator
    ) {
        dataProvider = _dataProvider;
        simulationEngine = _simulationEngine;
        metricsCalculator = _metricsCalculator;
    }
    
    /**
     * @notice Configure the backtest parameters
     * @param _startTimestamp Start time for the backtest
     * @param _endTimestamp End time for the backtest
     * @param _timeStep Time between simulation steps (in seconds)
     */
    function configure(
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _timeStep
    ) external {
        require(_endTimestamp > _startTimestamp, "Invalid time range");
        require(_timeStep > 0, "Time step must be positive");
        
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        timeStep = _timeStep;
    }
    
    /**
     * @notice Run the backtest simulation
     * @return success Whether the backtest completed successfully
     */
    function runBacktest() external returns (bool) {
        require(startTimestamp > 0 && endTimestamp > 0, "Configure backtest first");
        
        // Clear previous results
        delete results;
        
        // Initialize the simulation
        simulationEngine.initialize(startTimestamp);
        
        // Run simulation steps
        for (uint256 timestamp = startTimestamp; timestamp <= endTimestamp; timestamp += timeStep) {
            // Update price data for current timestamp
            dataProvider.updatePrices(timestamp);
            
            // Run simulation step
            (
                uint256 portfolioValue,
                uint256[] memory assetValues,
                uint256[] memory assetWeights,
                uint256 yieldHarvested,
                bool rebalanced,
                uint256 gasCost
            ) = simulationEngine.runStep(timestamp);
            
            // Record results
            results.push(
                BacktestResult({
                    timestamp: timestamp,
                    portfolioValue: portfolioValue,
                    assetValues: assetValues,
                    assetWeights: assetWeights,
                    yieldHarvested: yieldHarvested,
                    rebalanced: rebalanced,
                    gasCost: gasCost
                })
            );
        }
        
        return true;
    }
    
    /**
     * @notice Calculate performance metrics based on backtest results
     * @return sharpeRatio The Sharpe ratio
     * @return maxDrawdown The maximum drawdown percentage (scaled by 1e18)
     * @return annualizedReturn The annualized return percentage (scaled by 1e18)
     * @return volatility The annualized volatility (scaled by 1e18)
     */
    function calculateMetrics() external view returns (
        int256 sharpeRatio,
        uint256 maxDrawdown,
        int256 annualizedReturn,
        uint256 volatility
    ) {
        require(results.length > 0, "No backtest results available");
        
        return metricsCalculator.calculateMetrics(results);
    }
    
    /**
     * @notice Get the number of result data points
     * @return count The number of result data points
     */
    function getResultCount() external view returns (uint256) {
        return results.length;
    }
    
    /**
     * @notice Get result at specific index
     * @param index The index of the result to retrieve
     * @return result The backtest result at the specified index
     */
    function getResult(uint256 index) external view returns (BacktestResult memory) {
        require(index < results.length, "Index out of bounds");
        return results[index];
    }
}

/**
 * @title IHistoricalDataProvider
 * @notice Interface for historical data providers
 */
interface IHistoricalDataProvider {
    /**
     * @notice Update prices for all assets at the given timestamp
     * @param timestamp The timestamp to fetch prices for
     */
    function updatePrices(uint256 timestamp) external;
    
    /**
     * @notice Get the price of an asset at a specific timestamp
     * @param asset The address of the asset
     * @param timestamp The timestamp to get the price for
     * @return price The price of the asset (scaled by 1e18)
     */
    function getAssetPrice(address asset, uint256 timestamp) external view returns (uint256);
    
    /**
     * @notice Get the yield rate for a strategy at a specific timestamp
     * @param strategy The address of the yield strategy
     * @param timestamp The timestamp to get the yield rate for
     * @return yieldRate The annualized yield rate (scaled by 1e18)
     */
    function getYieldRate(address strategy, uint256 timestamp) external view returns (uint256);
}

/**
 * @title ISimulationEngine
 * @notice Interface for simulation engines
 */
interface ISimulationEngine {
    /**
     * @notice Initialize the simulation
     * @param startTimestamp The starting timestamp for the simulation
     */
    function initialize(uint256 startTimestamp) external;
    
    /**
     * @notice Run a single simulation step
     * @param timestamp The current timestamp in the simulation
     * @return portfolioValue The total portfolio value
     * @return assetValues Array of individual asset values
     * @return assetWeights Array of asset weights (scaled by 10000, e.g. 5000 = 50%)
     * @return yieldHarvested Amount of yield harvested in this step
     * @return rebalanced Whether a rebalance occurred in this step
     * @return gasCost Estimated gas cost for operations in this step
     */
    function runStep(uint256 timestamp) external returns (
        uint256 portfolioValue,
        uint256[] memory assetValues,
        uint256[] memory assetWeights,
        uint256 yieldHarvested,
        bool rebalanced,
        uint256 gasCost
    );
}

/**
 * @title IMetricsCalculator
 * @notice Interface for performance metrics calculators
 */
interface IMetricsCalculator {
    /**
     * @notice Calculate performance metrics based on backtest results
     * @param results Array of backtest results
     * @return sharpeRatio The Sharpe ratio
     * @return maxDrawdown The maximum drawdown percentage (scaled by 1e18)
     * @return annualizedReturn The annualized return percentage (scaled by 1e18)
     * @return volatility The annualized volatility (scaled by 1e18)
     */
    function calculateMetrics(BacktestingFramework.BacktestResult[] memory results) external view returns (
        int256 sharpeRatio,
        uint256 maxDrawdown,
        int256 annualizedReturn,
        uint256 volatility
    );
}
