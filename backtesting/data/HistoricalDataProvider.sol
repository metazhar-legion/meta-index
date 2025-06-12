// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BacktestingFramework.sol";

/**
 * @title HistoricalDataProvider
 * @notice Implementation of IHistoricalDataProvider for historical price and yield data
 * @dev This contract provides historical data from various sources for backtesting
 */
contract HistoricalDataProvider is IHistoricalDataProvider {
    // Data storage
    mapping(address => mapping(uint256 => uint256)) private assetPrices;
    mapping(address => mapping(uint256 => uint256)) private strategyYieldRates;
    
    // Asset and strategy lists
    address[] public assets;
    address[] public strategies;
    
    // Data source information
    string public priceDataSource;
    string public yieldDataSource;
    
    /**
     * @notice Constructor
     * @param _priceDataSource Description of the price data source
     * @param _yieldDataSource Description of the yield data source
     */
    constructor(string memory _priceDataSource, string memory _yieldDataSource) {
        priceDataSource = _priceDataSource;
        yieldDataSource = _yieldDataSource;
    }
    
    /**
     * @notice Add an asset to track
     * @param asset The address of the asset to track
     */
    function addAsset(address asset) external {
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i] == asset) {
                return; // Asset already exists
            }
        }
        assets.push(asset);
    }
    
    /**
     * @notice Add a strategy to track
     * @param strategy The address of the strategy to track
     */
    function addStrategy(address strategy) external {
        for (uint i = 0; i < strategies.length; i++) {
            if (strategies[i] == strategy) {
                return; // Strategy already exists
            }
        }
        strategies.push(strategy);
    }
    
    /**
     * @notice Set historical price data for an asset
     * @param asset The address of the asset
     * @param timestamp The timestamp for the price data
     * @param price The price value (scaled by 1e18)
     */
    function setAssetPrice(address asset, uint256 timestamp, uint256 price) external {
        assetPrices[asset][timestamp] = price;
    }
    
    /**
     * @notice Set historical yield rate data for a strategy
     * @param strategy The address of the strategy
     * @param timestamp The timestamp for the yield rate data
     * @param yieldRate The annualized yield rate (scaled by 1e18)
     */
    function setYieldRate(address strategy, uint256 timestamp, uint256 yieldRate) external {
        strategyYieldRates[strategy][timestamp] = yieldRate;
    }
    
    /**
     * @notice Batch set historical price data for an asset
     * @param asset The address of the asset
     * @param timestamps Array of timestamps
     * @param prices Array of price values (scaled by 1e18)
     */
    function batchSetAssetPrices(
        address asset,
        uint256[] calldata timestamps,
        uint256[] calldata prices
    ) external {
        require(timestamps.length == prices.length, "Array lengths must match");
        
        for (uint256 i = 0; i < timestamps.length; i++) {
            assetPrices[asset][timestamps[i]] = prices[i];
        }
    }
    
    /**
     * @notice Batch set historical yield rate data for a strategy
     * @param strategy The address of the strategy
     * @param timestamps Array of timestamps
     * @param yieldRates Array of yield rates (scaled by 1e18)
     */
    function batchSetYieldRates(
        address strategy,
        uint256[] calldata timestamps,
        uint256[] calldata yieldRates
    ) external {
        require(timestamps.length == yieldRates.length, "Array lengths must match");
        
        for (uint256 i = 0; i < timestamps.length; i++) {
            strategyYieldRates[strategy][timestamps[i]] = yieldRates[i];
        }
    }
    
    /**
     * @notice Get the number of assets being tracked
     * @return count The number of assets
     */
    function getAssetCount() external view returns (uint256) {
        return assets.length;
    }
    
    /**
     * @notice Get the number of strategies being tracked
     * @return count The number of strategies
     */
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }
    
    /**
     * @notice Update prices for all assets at the given timestamp
     * @dev This function is a no-op in this implementation as prices are pre-loaded
     * @param timestamp The timestamp to fetch prices for
     */
    function updatePrices(uint256 timestamp) external override {
        // No-op in this implementation as prices are pre-loaded
        // In a real implementation, this might fetch prices from an external source
    }
    
    /**
     * @notice Get the price of an asset at a specific timestamp
     * @param asset The address of the asset
     * @param timestamp The timestamp to get the price for
     * @return price The price of the asset (scaled by 1e18)
     */
    function getAssetPrice(address asset, uint256 timestamp) external view override returns (uint256) {
        return assetPrices[asset][timestamp];
    }
    
    /**
     * @notice Get the yield rate for a strategy at a specific timestamp
     * @param strategy The address of the yield strategy
     * @param timestamp The timestamp to get the yield rate for
     * @return yieldRate The annualized yield rate (in basis points)
     */
    function getYieldRate(address strategy, uint256 timestamp) external view override returns (uint256) {
        uint256 yieldRate = strategyYieldRates[strategy][timestamp];
        if (yieldRate > 0) {
            return yieldRate;
        }
        
        // If no exact match, try to find the nearest yield rate within 90 days
        return getNearestYieldRate(strategy, timestamp, 90 days);
    }
    
    /**
     * @notice Get the nearest yield rate for a strategy within a time window
     * @param strategy The address of the yield strategy
     * @param timestamp The target timestamp
     * @param maxDelta The maximum allowed time difference (in seconds)
     * @return yieldRate The nearest yield rate (in basis points)
     */
    function getNearestYieldRate(address strategy, uint256 timestamp, uint256 maxDelta) public view returns (uint256) {
        // Start with the exact timestamp
        uint256 yieldRate = strategyYieldRates[strategy][timestamp];
        if (yieldRate > 0) {
            return yieldRate;
        }
        
        // Look for the nearest timestamp within maxDelta
        uint256 nearestDelta = maxDelta + 1; // Initialize to more than maxDelta
        
        // Check timestamps before the target
        for (uint256 delta = 1; delta <= maxDelta; delta++) {
            if (timestamp >= delta) {
                uint256 checkTime = timestamp - delta;
                uint256 checkYieldRate = strategyYieldRates[strategy][checkTime];
                if (checkYieldRate > 0 && delta < nearestDelta) {
                    yieldRate = checkYieldRate;
                    nearestDelta = delta;
                }
            }
        }
        
        // Check timestamps after the target
        for (uint256 delta = 1; delta <= maxDelta; delta++) {
            uint256 checkTime = timestamp + delta;
            uint256 checkYieldRate = strategyYieldRates[strategy][checkTime];
            if (checkYieldRate > 0 && delta < nearestDelta) {
                yieldRate = checkYieldRate;
                nearestDelta = delta;
            }
        }
        
        return yieldRate;
    }
    
    /**
     * @notice Get the price of an asset at the nearest available timestamp
     * @param asset The address of the asset
     * @param timestamp The target timestamp
     * @param maxDelta The maximum allowed time difference (in seconds)
     * @return price The price of the asset (scaled by 1e18)
     * @return actualTimestamp The actual timestamp of the returned price
     */
    function getNearestAssetPrice(
        address asset,
        uint256 timestamp,
        uint256 maxDelta
    ) external view returns (uint256 price, uint256 actualTimestamp) {
        // Start with the exact timestamp
        price = assetPrices[asset][timestamp];
        if (price > 0) {
            return (price, timestamp);
        }
        
        // Look for the nearest timestamp within maxDelta
        uint256 nearestDelta = maxDelta + 1; // Initialize to more than maxDelta
        actualTimestamp = timestamp;
        
        // Check timestamps before the target
        for (uint256 delta = 1; delta <= maxDelta; delta++) {
            if (timestamp >= delta) {
                uint256 checkTime = timestamp - delta;
                uint256 checkPrice = assetPrices[asset][checkTime];
                if (checkPrice > 0 && delta < nearestDelta) {
                    price = checkPrice;
                    actualTimestamp = checkTime;
                    nearestDelta = delta;
                }
            }
        }
        
        // Check timestamps after the target
        for (uint256 delta = 1; delta <= maxDelta; delta++) {
            uint256 checkTime = timestamp + delta;
            uint256 checkPrice = assetPrices[asset][checkTime];
            if (checkPrice > 0 && delta < nearestDelta) {
                price = checkPrice;
                actualTimestamp = checkTime;
                nearestDelta = delta;
            }
        }
        
        require(nearestDelta <= maxDelta, "No price data within acceptable range");
        return (price, actualTimestamp);
    }
}
