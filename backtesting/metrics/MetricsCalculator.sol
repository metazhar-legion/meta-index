// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BacktestingFramework.sol";

/**
 * @title MetricsCalculator
 * @notice Calculator for performance metrics from backtest results
 * @dev Implements various financial metrics for portfolio performance analysis
 */
contract MetricsCalculator is IMetricsCalculator {
    // Constants
    uint256 constant SCALE = 1e18;
    uint256 constant DAYS_PER_YEAR = 365;
    uint256 constant SECONDS_PER_DAY = 86400;
    
    // Risk-free rate (in basis points, e.g. 200 = 2%)
    uint256 public riskFreeRate;
    
    /**
     * @notice Constructor
     * @param _riskFreeRate Annual risk-free rate in basis points (e.g., 200 = 2%)
     */
    constructor(uint256 _riskFreeRate) {
        riskFreeRate = _riskFreeRate;
    }
    
    /**
     * @notice Set the risk-free rate used in calculations
     * @param _riskFreeRate Annual risk-free rate in basis points
     */
    function setRiskFreeRate(uint256 _riskFreeRate) external {
        riskFreeRate = _riskFreeRate;
    }
    
    /**
     * @notice Calculate performance metrics based on backtest results
     * @param results Array of backtest results
     * @return sharpeRatio The Sharpe ratio (scaled by 1e18)
     * @return maxDrawdown The maximum drawdown percentage (scaled by 1e18)
     * @return annualizedReturn The annualized return percentage (scaled by 1e18)
     * @return volatility The annualized volatility (scaled by 1e18)
     */
    function calculateMetrics(
        BacktestingFramework.BacktestResult[] memory results
    ) external view override returns (
        int256 sharpeRatio,
        uint256 maxDrawdown,
        int256 annualizedReturn,
        uint256 volatility
    ) {
        require(results.length >= 2, "Insufficient data points");
        
        // Calculate returns for each period
        int256[] memory returns = new int256[](results.length - 1);
        for (uint256 i = 1; i < results.length; i++) {
            uint256 currentValue = results[i].portfolioValue;
            uint256 previousValue = results[i-1].portfolioValue;
            
            if (previousValue > 0) {
                // Calculate return as percentage (scaled by 1e18)
                returns[i-1] = int256((currentValue * SCALE) / previousValue) - int256(SCALE);
            } else {
                returns[i-1] = 0;
            }
        }
        
        // Calculate annualized return
        uint256 firstTimestamp = results[0].timestamp;
        uint256 lastTimestamp = results[results.length - 1].timestamp;
        uint256 totalDays = (lastTimestamp - firstTimestamp) / SECONDS_PER_DAY;
        
        if (totalDays > 0) {
            uint256 firstValue = results[0].portfolioValue;
            uint256 lastValue = results[results.length - 1].portfolioValue;
            
            if (firstValue > 0) {
                // Calculate total return
                int256 totalReturn = int256((lastValue * SCALE) / firstValue) - int256(SCALE);
                
                // Annualize the return: (1 + totalReturn)^(365/totalDays) - 1
                // For simplicity, we use a linear approximation for short periods
                annualizedReturn = (totalReturn * int256(DAYS_PER_YEAR)) / int256(totalDays);
            }
        }
        
        // Calculate volatility (standard deviation of returns)
        volatility = _calculateVolatility(returns, totalDays);
        
        // Calculate Sharpe ratio
        int256 riskFreeRateScaled = int256((riskFreeRate * SCALE) / 10000); // Convert from basis points
        if (volatility > 0) {
            sharpeRatio = (annualizedReturn - riskFreeRateScaled) * int256(SCALE) / int256(volatility);
        }
        
        // Calculate maximum drawdown
        maxDrawdown = _calculateMaxDrawdown(results);
        
        return (sharpeRatio, maxDrawdown, annualizedReturn, volatility);
    }
    
    /**
     * @notice Calculate the volatility (standard deviation) of returns
     * @param returns Array of period returns
     * @param totalDays Total number of days in the backtest period
     * @return volatility The annualized volatility (scaled by 1e18)
     */
    function _calculateVolatility(
        int256[] memory returns,
        uint256 totalDays
    ) internal pure returns (uint256) {
        if (returns.length <= 1) return 0;
        
        // Calculate mean return
        int256 sum = 0;
        for (uint256 i = 0; i < returns.length; i++) {
            sum += returns[i];
        }
        int256 mean = sum / int256(returns.length);
        
        // Calculate sum of squared deviations
        uint256 sumSquaredDeviations = 0;
        for (uint256 i = 0; i < returns.length; i++) {
            int256 deviation = returns[i] - mean;
            // Square the deviation (convert to positive first to avoid issues with negative numbers)
            if (deviation < 0) {
                sumSquaredDeviations += uint256(-deviation * -deviation) / SCALE;
            } else {
                sumSquaredDeviations += uint256(deviation * deviation) / SCALE;
            }
        }
        
        // Calculate variance
        uint256 variance = (sumSquaredDeviations * SCALE) / (returns.length - 1);
        
        // Calculate standard deviation (volatility)
        uint256 stdDev = _sqrt(variance);
        
        // Annualize volatility based on the period frequency
        uint256 periodsPerYear = totalDays > 0 ? (DAYS_PER_YEAR * returns.length) / totalDays : 0;
        if (periodsPerYear > 0) {
            return (stdDev * _sqrt(periodsPerYear)) / _sqrt(SCALE);
        }
        
        return stdDev;
    }
    
    /**
     * @notice Calculate the maximum drawdown from a series of portfolio values
     * @param results Array of backtest results
     * @return maxDrawdown The maximum drawdown percentage (scaled by 1e18)
     */
    function _calculateMaxDrawdown(
        BacktestingFramework.BacktestResult[] memory results
    ) internal pure returns (uint256) {
        if (results.length <= 1) return 0;
        
        uint256 maxValue = results[0].portfolioValue;
        uint256 maxDrawdown = 0;
        
        for (uint256 i = 1; i < results.length; i++) {
            uint256 currentValue = results[i].portfolioValue;
            
            // Update maximum value if current value is higher
            if (currentValue > maxValue) {
                maxValue = currentValue;
            } 
            // Calculate drawdown if current value is lower than maximum
            else if (maxValue > 0) {
                uint256 drawdown = ((maxValue - currentValue) * SCALE) / maxValue;
                if (drawdown > maxDrawdown) {
                    maxDrawdown = drawdown;
                }
            }
        }
        
        return maxDrawdown;
    }
    
    /**
     * @notice Calculate square root using Babylonian method
     * @param x The number to calculate the square root of
     * @return y The square root of x
     */
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        // Initial estimate
        uint256 z = (x + 1) / 2;
        y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    /**
     * @notice Calculate the Sortino ratio (similar to Sharpe but only considers downside volatility)
     * @param results Array of backtest results
     * @return sortinoRatio The Sortino ratio (scaled by 1e18)
     */
    function calculateSortinoRatio(
        BacktestingFramework.BacktestResult[] memory results
    ) external view returns (int256 sortinoRatio) {
        require(results.length >= 2, "Insufficient data points");
        
        // Calculate returns for each period
        int256[] memory returns = new int256[](results.length - 1);
        for (uint256 i = 1; i < results.length; i++) {
            uint256 currentValue = results[i].portfolioValue;
            uint256 previousValue = results[i-1].portfolioValue;
            
            if (previousValue > 0) {
                returns[i-1] = int256((currentValue * SCALE) / previousValue) - int256(SCALE);
            } else {
                returns[i-1] = 0;
            }
        }
        
        // Calculate annualized return
        uint256 firstTimestamp = results[0].timestamp;
        uint256 lastTimestamp = results[results.length - 1].timestamp;
        uint256 totalDays = (lastTimestamp - firstTimestamp) / SECONDS_PER_DAY;
        
        int256 annualizedReturn = 0;
        if (totalDays > 0) {
            uint256 firstValue = results[0].portfolioValue;
            uint256 lastValue = results[results.length - 1].portfolioValue;
            
            if (firstValue > 0) {
                int256 totalReturn = int256((lastValue * SCALE) / firstValue) - int256(SCALE);
                annualizedReturn = (totalReturn * int256(DAYS_PER_YEAR)) / int256(totalDays);
            }
        }
        
        // Calculate downside deviation (only negative returns)
        uint256 sumSquaredNegativeDeviations = 0;
        uint256 negativeReturnCount = 0;
        
        for (uint256 i = 0; i < returns.length; i++) {
            if (returns[i] < 0) {
                sumSquaredNegativeDeviations += uint256(returns[i] * returns[i]) / SCALE;
                negativeReturnCount++;
            }
        }
        
        // Calculate downside deviation
        uint256 downsideDeviation = 0;
        if (negativeReturnCount > 0) {
            uint256 downsideVariance = (sumSquaredNegativeDeviations * SCALE) / negativeReturnCount;
            downsideDeviation = _sqrt(downsideVariance);
            
            // Annualize downside deviation
            uint256 periodsPerYear = totalDays > 0 ? (DAYS_PER_YEAR * returns.length) / totalDays : 0;
            if (periodsPerYear > 0) {
                downsideDeviation = (downsideDeviation * _sqrt(periodsPerYear)) / _sqrt(SCALE);
            }
        }
        
        // Calculate Sortino ratio
        int256 riskFreeRateScaled = int256((riskFreeRate * SCALE) / 10000); // Convert from basis points
        if (downsideDeviation > 0) {
            sortinoRatio = (annualizedReturn - riskFreeRateScaled) * int256(SCALE) / int256(downsideDeviation);
        }
        
        return sortinoRatio;
    }
    
    /**
     * @notice Calculate correlation between portfolio returns and a benchmark
     * @param portfolioResults Array of portfolio backtest results
     * @param benchmarkResults Array of benchmark backtest results
     * @return correlation The correlation coefficient (scaled by 1e18)
     */
    function calculateCorrelation(
        BacktestingFramework.BacktestResult[] memory portfolioResults,
        BacktestingFramework.BacktestResult[] memory benchmarkResults
    ) external pure returns (int256 correlation) {
        require(portfolioResults.length == benchmarkResults.length, "Data length mismatch");
        require(portfolioResults.length >= 2, "Insufficient data points");
        
        // Calculate returns for each period
        int256[] memory portfolioReturns = new int256[](portfolioResults.length - 1);
        int256[] memory benchmarkReturns = new int256[](benchmarkResults.length - 1);
        
        for (uint256 i = 1; i < portfolioResults.length; i++) {
            uint256 currentPortfolioValue = portfolioResults[i].portfolioValue;
            uint256 previousPortfolioValue = portfolioResults[i-1].portfolioValue;
            
            uint256 currentBenchmarkValue = benchmarkResults[i].portfolioValue;
            uint256 previousBenchmarkValue = benchmarkResults[i-1].portfolioValue;
            
            if (previousPortfolioValue > 0 && previousBenchmarkValue > 0) {
                portfolioReturns[i-1] = int256((currentPortfolioValue * SCALE) / previousPortfolioValue) - int256(SCALE);
                benchmarkReturns[i-1] = int256((currentBenchmarkValue * SCALE) / previousBenchmarkValue) - int256(SCALE);
            } else {
                portfolioReturns[i-1] = 0;
                benchmarkReturns[i-1] = 0;
            }
        }
        
        // Calculate mean returns
        int256 sumPortfolio = 0;
        int256 sumBenchmark = 0;
        
        for (uint256 i = 0; i < portfolioReturns.length; i++) {
            sumPortfolio += portfolioReturns[i];
            sumBenchmark += benchmarkReturns[i];
        }
        
        int256 meanPortfolio = sumPortfolio / int256(portfolioReturns.length);
        int256 meanBenchmark = sumBenchmark / int256(benchmarkReturns.length);
        
        // Calculate covariance and variances
        int256 covariance = 0;
        int256 variancePortfolio = 0;
        int256 varianceBenchmark = 0;
        
        for (uint256 i = 0; i < portfolioReturns.length; i++) {
            int256 diffPortfolio = portfolioReturns[i] - meanPortfolio;
            int256 diffBenchmark = benchmarkReturns[i] - meanBenchmark;
            
            covariance += (diffPortfolio * diffBenchmark) / int256(SCALE);
            variancePortfolio += (diffPortfolio * diffPortfolio) / int256(SCALE);
            varianceBenchmark += (diffBenchmark * diffBenchmark) / int256(SCALE);
        }
        
        covariance = (covariance * int256(SCALE)) / int256(portfolioReturns.length);
        variancePortfolio = (variancePortfolio * int256(SCALE)) / int256(portfolioReturns.length);
        varianceBenchmark = (varianceBenchmark * int256(SCALE)) / int256(portfolioReturns.length);
        
        // Calculate correlation coefficient
        if (variancePortfolio > 0 && varianceBenchmark > 0) {
            uint256 stdDevPortfolio = _sqrt(uint256(variancePortfolio));
            uint256 stdDevBenchmark = _sqrt(uint256(varianceBenchmark));
            
            correlation = (covariance * int256(SCALE)) / int256(stdDevPortfolio * stdDevBenchmark / SCALE);
        }
        
        return correlation;
    }
}
