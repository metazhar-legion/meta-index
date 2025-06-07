// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BacktestingFramework.sol";
import "../data/HistoricalDataProvider.sol";
import "../simulation/VaultSimulationEngine.sol";
import "../metrics/MetricsCalculator.sol";
import "../scenarios/MarketScenarios.sol";
import "../visualization/ResultsExporter.sol";
import "../interfaces/IERC20.sol";

/**
 * @title MonthlyRebalanceBacktest
 * @notice Sample backtest for a 20/80 allocation between RWA and S&P 500 with monthly rebalancing
 * @dev Demonstrates how to set up and run a backtest with the framework
 */
contract MonthlyRebalanceBacktest {
    // Addresses (using placeholder addresses for demonstration)
    address constant USDC = address(0x1);
    address constant SP500_TOKEN = address(0x2);
    address constant RWA_TOKEN = address(0x3);
    address constant SP500_WRAPPER = address(0x4);
    address constant RWA_WRAPPER = address(0x5);
    
    // Backtest components
    BacktestingFramework public backtestingFramework;
    HistoricalDataProvider public dataProvider;
    VaultSimulationEngine public simulationEngine;
    MetricsCalculator public metricsCalculator;
    ResultsExporter public resultsExporter;
    
    /**
     * @notice Get the data provider instance
     * @return The HistoricalDataProvider instance
     */
    function getDataProvider() external view returns (HistoricalDataProvider) {
        return dataProvider;
    }
    
    // Backtest configuration
    uint256 public startTimestamp;
    uint256 public endTimestamp;
    uint256 public timeStep;
    uint256 public initialDeposit;
    
    // Events
    event BacktestCompleted(
        uint256 resultCount,
        uint256 finalPortfolioValue,
        int256 annualizedReturn,
        uint256 maxDrawdown
    );
    
    /**
     * @notice Constructor
     * @param _startTimestamp Start timestamp for the backtest (Unix timestamp)
     * @param _endTimestamp End timestamp for the backtest (Unix timestamp)
     * @param _timeStep Time step in seconds (e.g., 86400 for daily)
     * @param _initialDeposit Initial deposit amount in base asset units
     */
    constructor(
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _timeStep,
        uint256 _initialDeposit
    ) {
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
        timeStep = _timeStep;
        initialDeposit = _initialDeposit;
        
        // Initialize components
        _initializeComponents();
    }
    
    /**
     * @notice Initialize all backtest components
     */
    function _initializeComponents() internal {
        // Create data provider with data source information
        dataProvider = new HistoricalDataProvider(
            "Historical S&P 500 and RWA price data 2020-2024",
            "Historical yield rates for RWA strategies 2020-2024"
        );
        
        // Create simulation engine with configuration
        simulationEngine = new VaultSimulationEngine(
            dataProvider,
            USDC,              // Base asset
            initialDeposit,    // Initial deposit
            500,               // Rebalance threshold (5%)
            30 days,           // Rebalance interval - MONTHLY
            10,                // Management fee (0.1%)
            0                  // Performance fee (0%)
        );
        
        // Add assets to simulation engine (20/80 allocation)
        simulationEngine.addAsset(RWA_TOKEN, RWA_WRAPPER, 2000, true);    // 20% RWA with yield
        simulationEngine.addAsset(SP500_TOKEN, SP500_WRAPPER, 8000, false); // 80% S&P 500
        
        // Create metrics calculator with 2% risk-free rate
        metricsCalculator = new MetricsCalculator(200);
        
        // Create backtesting framework with all dependencies
        backtestingFramework = new BacktestingFramework(
            dataProvider,
            simulationEngine,
            metricsCalculator
        );
    }
    
    /**
     * @notice Set up historical price and yield data
     * @dev This is a simplified example with quarterly price points
     * TODO: Replace with higher quality data source with more frequent price points
     */
    function setupHistoricalData() external {
        // Set up S&P 500 price data (simplified example with annual returns)
        // Using approximate S&P 500 yearly returns for 2020-2024
        uint256 sp500BasePrice = 100 * 10**18; // Starting price
        
        // 2020: ~16% return
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp, sp500BasePrice);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 90 days, sp500BasePrice * 85 / 100); // COVID crash
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 180 days, sp500BasePrice * 95 / 100); // Recovery
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days, sp500BasePrice * 116 / 100); // Year-end
        
        // 2021: ~27% return
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days + 90 days, sp500BasePrice * 125 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days + 180 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days + 270 days, sp500BasePrice * 140 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 2, sp500BasePrice * 147 / 100);
        
        // 2022: ~-19% return
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 2 + 90 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 2 + 180 days, sp500BasePrice * 125 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 2 + 270 days, sp500BasePrice * 120 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 3, sp500BasePrice * 119 / 100);
        
        // 2023: ~24% return
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 3 + 90 days, sp500BasePrice * 125 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 3 + 180 days, sp500BasePrice * 135 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 3 + 270 days, sp500BasePrice * 140 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 4, sp500BasePrice * 148 / 100);
        
        // 2024: ~12% return (partial year)
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 4 + 90 days, sp500BasePrice * 155 / 100);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 365 days * 4 + 180 days, sp500BasePrice * 160 / 100);
        
        // Set up RWA price data (more stable with lower returns)
        uint256 rwaBasePrice = 100 * 10**18; // Starting price
        
        // 2020: ~5% return
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp, rwaBasePrice);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 90 days, rwaBasePrice * 98 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 180 days, rwaBasePrice * 101 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days, rwaBasePrice * 105 / 100);
        
        // 2021: ~7% return
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days + 180 days, rwaBasePrice * 108 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days * 2, rwaBasePrice * 112 / 100);
        
        // 2022: ~3% return
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days * 2 + 180 days, rwaBasePrice * 114 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days * 3, rwaBasePrice * 115 / 100);
        
        // 2023: ~6% return
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days * 3 + 180 days, rwaBasePrice * 118 / 100);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days * 4, rwaBasePrice * 122 / 100);
        
        // 2024: ~3% return (partial year)
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 365 days * 4 + 180 days, rwaBasePrice * 125 / 100);
        
        // Set up yield rates for RWA (assuming 4% annual yield)
        // TODO: Update with historical yield data when available
        uint256 rwaYieldRate = 400; // 4% in basis points
        dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp + 365 days, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp + 365 days * 2, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp + 365 days * 3, rwaYieldRate);
        dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp + 365 days * 4, rwaYieldRate);
    }
    
    /**
     * @notice Run the backtest
     * @return resultCount Number of backtest results
     */
    function runBacktest() external returns (uint256 resultCount) {
        // Initialize the simulation engine
        simulationEngine.initialize(startTimestamp);
        
        // Configure and run the backtest
        backtestingFramework.configure(
            startTimestamp,
            endTimestamp,
            timeStep
        );
        
        bool success = backtestingFramework.runBacktest();
        require(success, "Backtest failed to run");
        
        // Get the number of results
        resultCount = backtestingFramework.getResultCount();
        
        // Calculate metrics
        (
            int256 sharpeRatio /* unused */,
            uint256 maxDrawdown,
            int256 annualizedReturn,
            uint256 volatility /* unused */
        ) = backtestingFramework.calculateMetrics();
        
        // Get final portfolio value
        BacktestingFramework.BacktestResult memory finalResult = backtestingFramework.getResult(resultCount - 1);
        
        emit BacktestCompleted(
            resultCount,
            finalResult.portfolioValue,
            annualizedReturn,
            maxDrawdown
        );
        
        return resultCount;
    }
    
    /**
     * @notice Get summary of backtest results
     * @return initialValue Initial portfolio value
     * @return finalValue Final portfolio value
     * @return totalReturn Total return percentage (scaled by 1e18)
     * @return annualizedReturn Annualized return percentage (scaled by 1e18)
     * @return sharpeRatio Sharpe ratio (scaled by 1e18)
     * @return maxDrawdown Maximum drawdown percentage (scaled by 1e18)
     * @return volatility Annualized volatility (scaled by 1e18)
     */
    function getBacktestSummary() external view returns (
        uint256 initialValue,
        uint256 finalValue,
        int256 totalReturn,
        int256 annualizedReturn,
        int256 sharpeRatio,
        uint256 maxDrawdown,
        uint256 volatility
    ) {
        uint256 resultCount = backtestingFramework.getResultCount();
        require(resultCount > 0, "No backtest results available");
        
        // Get initial and final values
        BacktestingFramework.BacktestResult memory firstResult = backtestingFramework.getResult(0);
        BacktestingFramework.BacktestResult memory lastResult = backtestingFramework.getResult(resultCount - 1);
        
        initialValue = firstResult.portfolioValue;
        finalValue = lastResult.portfolioValue;
        
        // Calculate total return
        if (initialValue > 0) {
            totalReturn = int256((finalValue * 1e18) / initialValue) - int256(1e18);
        }
        
        // Calculate metrics
        (
            sharpeRatio,
            maxDrawdown,
            annualizedReturn,
            volatility
        ) = backtestingFramework.calculateMetrics();
        
        return (
            initialValue,
            finalValue,
            totalReturn,
            annualizedReturn,
            sharpeRatio,
            maxDrawdown,
            volatility
        );
    }
}
