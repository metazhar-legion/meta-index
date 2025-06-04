// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BacktestingFramework.sol";

/**
 * @title ResultsExporter
 * @notice Exports backtest results in formats suitable for visualization
 * @dev Generates CSV-like data structures for external visualization tools
 */
contract ResultsExporter {
    // Constants
    uint256 constant SCALE = 1e18;
    
    // Backtest framework reference
    BacktestingFramework public backtestingFramework;
    
    /**
     * @notice Constructor
     * @param _backtestingFramework Reference to the backtesting framework
     */
    constructor(BacktestingFramework _backtestingFramework) {
        backtestingFramework = _backtestingFramework;
    }
    
    /**
     * @notice Generate portfolio value time series data
     * @return timestamps Array of timestamps
     * @return values Array of portfolio values
     */
    function getPortfolioValueTimeSeries() external view returns (
        uint256[] memory timestamps,
        uint256[] memory values
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        
        timestamps = new uint256[](resultCount);
        values = new uint256[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            timestamps[i] = result.timestamp;
            values[i] = result.portfolioValue;
        }
        
        return (timestamps, values);
    }
    
    /**
     * @notice Generate asset allocation time series data
     * @return timestamps Array of timestamps
     * @return assetWeights 2D array of asset weights over time
     */
    function getAssetAllocationTimeSeries() external view returns (
        uint256[] memory timestamps,
        uint256[][] memory assetWeights
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        
        // Get the first result to determine the number of assets
        BacktestingFramework.BacktestResult memory firstResult = backtestingFramework.getResult(0);
        uint256 assetCount = firstResult.assetWeights.length;
        
        timestamps = new uint256[](resultCount);
        
        // Initialize the 2D array for asset weights
        // Note: Solidity doesn't support true 2D arrays in memory, so we create an array of arrays
        assetWeights = new uint256[][](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            timestamps[i] = result.timestamp;
            
            assetWeights[i] = new uint256[](assetCount);
            for (uint256 j = 0; j < assetCount; j++) {
                assetWeights[i][j] = result.assetWeights[j];
            }
        }
        
        return (timestamps, assetWeights);
    }
    
    /**
     * @notice Generate yield harvested time series data
     * @return timestamps Array of timestamps
     * @return yieldValues Array of yield values harvested at each timestamp
     * @return cumulativeYield Array of cumulative yield values
     */
    function getYieldTimeSeries() external view returns (
        uint256[] memory timestamps,
        uint256[] memory yieldValues,
        uint256[] memory cumulativeYield
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        
        timestamps = new uint256[](resultCount);
        yieldValues = new uint256[](resultCount);
        cumulativeYield = new uint256[](resultCount);
        
        uint256 runningTotal = 0;
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            timestamps[i] = result.timestamp;
            yieldValues[i] = result.yieldHarvested;
            
            runningTotal += result.yieldHarvested;
            cumulativeYield[i] = runningTotal;
        }
        
        return (timestamps, yieldValues, cumulativeYield);
    }
    
    /**
     * @notice Generate rebalance events time series data
     * @return timestamps Array of timestamps
     * @return rebalanceEvents Array of boolean flags indicating rebalance events
     * @return gasCosts Array of gas costs for each timestamp
     */
    function getRebalanceTimeSeries() external view returns (
        uint256[] memory timestamps,
        bool[] memory rebalanceEvents,
        uint256[] memory gasCosts
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        
        timestamps = new uint256[](resultCount);
        rebalanceEvents = new bool[](resultCount);
        gasCosts = new uint256[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            timestamps[i] = result.timestamp;
            rebalanceEvents[i] = result.rebalanced;
            gasCosts[i] = result.gasCost;
        }
        
        return (timestamps, rebalanceEvents, gasCosts);
    }
    
    /**
     * @notice Calculate and return period returns
     * @return timestamps Array of timestamps
     * @return periodReturns Array of period returns (scaled by 1e18)
     * @return cumulativeReturns Array of cumulative returns (scaled by 1e18)
     */
    function getReturnsTimeSeries() external view returns (
        uint256[] memory timestamps,
        int256[] memory periodReturns,
        int256[] memory cumulativeReturns
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 1, "Insufficient backtest results");
        
        // We have resultCount-1 period returns (between resultCount data points)
        timestamps = new uint256[](resultCount - 1);
        periodReturns = new int256[](resultCount - 1);
        cumulativeReturns = new int256[](resultCount - 1);
        
        // Get initial portfolio value
        BacktestingFramework.BacktestResult memory initialResult = backtestingFramework.getResult(0);
        uint256 initialValue = initialResult.portfolioValue;
        require(initialValue > 0, "Initial portfolio value must be positive");
        
        int256 cumulativeReturn = 0;
        
        for (uint256 i = 1; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory currentResult = backtestingFramework.getResult(i);
            BacktestingFramework.BacktestResult memory previousResult = backtestingFramework.getResult(i - 1);
            
            timestamps[i - 1] = currentResult.timestamp;
            
            // Calculate period return
            if (previousResult.portfolioValue > 0) {
                periodReturns[i - 1] = int256((currentResult.portfolioValue * SCALE) / previousResult.portfolioValue) - int256(SCALE);
            } else {
                periodReturns[i - 1] = 0;
            }
            
            // Calculate cumulative return
            if (initialValue > 0) {
                cumulativeReturns[i - 1] = int256((currentResult.portfolioValue * SCALE) / initialValue) - int256(SCALE);
            } else {
                cumulativeReturns[i - 1] = 0;
            }
        }
        
        return (timestamps, periodReturns, cumulativeReturns);
    }
    
    /**
     * @notice Calculate drawdown time series
     * @return timestamps Array of timestamps
     * @return drawdowns Array of drawdown values (scaled by 1e18)
     * @return maxDrawdown Maximum drawdown value (scaled by 1e18)
     */
    function getDrawdownTimeSeries() external view returns (
        uint256[] memory timestamps,
        uint256[] memory drawdowns,
        uint256 maxDrawdown
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        
        timestamps = new uint256[](resultCount);
        drawdowns = new uint256[](resultCount);
        
        uint256 peakValue = 0;
        maxDrawdown = 0;
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory result = backtestingFramework.getResult(i);
            timestamps[i] = result.timestamp;
            
            uint256 currentValue = result.portfolioValue;
            
            // Update peak if current value is higher
            if (currentValue > peakValue) {
                peakValue = currentValue;
                drawdowns[i] = 0; // No drawdown at peak
            } 
            // Calculate drawdown if current value is lower than peak
            else if (peakValue > 0) {
                uint256 drawdown = ((peakValue - currentValue) * SCALE) / peakValue;
                drawdowns[i] = drawdown;
                
                // Update maximum drawdown if current drawdown is larger
                if (drawdown > maxDrawdown) {
                    maxDrawdown = drawdown;
                }
            }
        }
        
        return (timestamps, drawdowns, maxDrawdown);
    }
    
    /**
     * @notice Generate comparison data between portfolio and benchmark
     * @param benchmarkResults Array of benchmark backtest results
     * @return timestamps Array of timestamps
     * @return portfolioValues Array of portfolio values
     * @return benchmarkValues Array of benchmark values
     * @return relativePerformance Array of relative performance values (scaled by 1e18)
     */
    function getComparisonData(
        BacktestingFramework.BacktestResult[] memory benchmarkResults
    ) external view returns (
        uint256[] memory timestamps,
        uint256[] memory portfolioValues,
        uint256[] memory benchmarkValues,
        int256[] memory relativePerformance
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        require(benchmarkResults.length == resultCount, "Benchmark data length mismatch");
        
        timestamps = new uint256[](resultCount);
        portfolioValues = new uint256[](resultCount);
        benchmarkValues = new uint256[](resultCount);
        relativePerformance = new int256[](resultCount);
        
        // Normalize both series to start at the same value (100) for fair comparison
        BacktestingFramework.BacktestResult memory initialPortfolio = backtestingFramework.getResult(0);
        uint256 initialPortfolioValue = initialPortfolio.portfolioValue;
        
        uint256 initialBenchmarkValue = benchmarkResults[0].portfolioValue;
        
        require(initialPortfolioValue > 0 && initialBenchmarkValue > 0, "Initial values must be positive");
        
        for (uint256 i = 0; i < resultCount; i++) {
            BacktestingFramework.BacktestResult memory portfolioResult = backtestingFramework.getResult(i);
            BacktestingFramework.BacktestResult memory benchmarkResult = benchmarkResults[i];
            
            timestamps[i] = portfolioResult.timestamp;
            
            // Normalize values to start at 100
            portfolioValues[i] = (portfolioResult.portfolioValue * 100 * SCALE) / initialPortfolioValue;
            benchmarkValues[i] = (benchmarkResult.portfolioValue * 100 * SCALE) / initialBenchmarkValue;
            
            // Calculate relative performance (portfolio vs benchmark)
            relativePerformance[i] = int256(portfolioValues[i]) - int256(benchmarkValues[i]);
        }
        
        return (timestamps, portfolioValues, benchmarkValues, relativePerformance);
    }
}
