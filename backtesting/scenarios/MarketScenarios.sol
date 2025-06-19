// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../data/HistoricalDataProvider.sol";

/**
 * @title MarketScenarios
 * @notice Generates market scenarios for backtesting
 * @dev Creates various market conditions to stress test the vault
 */
contract MarketScenarios {
    // Base data provider
    HistoricalDataProvider public dataProvider;
    
    // Constants
    uint256 constant SCALE = 1e18;
    
    /**
     * @notice Constructor
     * @param _dataProvider The historical data provider to extend with scenarios
     */
    constructor(HistoricalDataProvider _dataProvider) {
        dataProvider = _dataProvider;
    }
    
    /**
     * @notice Generate a market crash scenario
     * @param asset The asset address to apply the scenario to
     * @param startTimestamp Start timestamp of the scenario
     * @param duration Duration of the crash in seconds
     * @param severity Crash severity (percentage drop, e.g. 50 = 50%)
     * @param recoveryDuration Duration of recovery period after crash (0 for no recovery)
     */
    function generateMarketCrash(
        address asset,
        uint256 startTimestamp,
        uint256 duration,
        uint256 severity,
        uint256 recoveryDuration
    ) external {
        require(severity <= 100, "Severity cannot exceed 100%");
        
        // Get the starting price
        uint256 startPrice = dataProvider.getAssetPrice(asset, startTimestamp);
        require(startPrice > 0, "No starting price available");
        
        // Calculate the crash bottom price
        uint256 bottomPrice = startPrice * (100 - severity) / 100;
        
        // Generate timestamps and prices for the crash period
        uint256 timeStep = duration / 10; // 10 steps during crash
        for (uint256 i = 1; i <= 10; i++) {
            uint256 timestamp = startTimestamp + (i * timeStep);
            
            // Linear price decline during crash
            uint256 price = startPrice - ((startPrice - bottomPrice) * i / 10);
            
            // Set the price in the data provider
            dataProvider.setAssetPrice(asset, timestamp, price);
        }
        
        // Generate recovery period if specified
        if (recoveryDuration > 0) {
            uint256 recoveryStart = startTimestamp + duration;
            uint256 recoveryTimeStep = recoveryDuration / 10; // 10 steps during recovery
            
            for (uint256 i = 1; i <= 10; i++) {
                uint256 timestamp = recoveryStart + (i * recoveryTimeStep);
                
                // Linear price recovery
                uint256 price = bottomPrice + ((startPrice - bottomPrice) * i / 10);
                
                // Set the price in the data provider
                dataProvider.setAssetPrice(asset, timestamp, price);
            }
        }
    }
    
    /**
     * @notice Generate a high volatility scenario
     * @param asset The asset address to apply the scenario to
     * @param startTimestamp Start timestamp of the scenario
     * @param duration Duration of the volatility in seconds
     * @param volatilityPercentage Volatility as percentage of price (e.g. 20 = 20%)
     * @param frequency Number of price swings during the period
     */
    function generateHighVolatility(
        address asset,
        uint256 startTimestamp,
        uint256 duration,
        uint256 volatilityPercentage,
        uint256 frequency
    ) external {
        // Get the starting price
        uint256 basePrice = dataProvider.getAssetPrice(asset, startTimestamp);
        require(basePrice > 0, "No starting price available");
        
        // Calculate maximum price deviation
        uint256 maxDeviation = basePrice * volatilityPercentage / 100;
        
        // Generate timestamps and prices for the volatile period
        uint256 timeStep = duration / (frequency * 2); // Each cycle has 2 steps (up and down)
        
        for (uint256 i = 0; i < frequency; i++) {
            // Up cycle
            uint256 upTimestamp = startTimestamp + (i * 2 * timeStep);
            uint256 upPrice = basePrice + maxDeviation;
            dataProvider.setAssetPrice(asset, upTimestamp, upPrice);
            
            // Down cycle
            uint256 downTimestamp = startTimestamp + ((i * 2 + 1) * timeStep);
            uint256 downPrice = basePrice - maxDeviation;
            dataProvider.setAssetPrice(asset, downTimestamp, downPrice);
        }
        
        // Set final price back to base price
        dataProvider.setAssetPrice(asset, startTimestamp + duration, basePrice);
    }
    
    /**
     * @notice Generate a yield strategy failure scenario
     * @param strategy The strategy address to apply the scenario to
     * @param startTimestamp Start timestamp of the scenario
     * @param duration Duration of the failure in seconds
     * @param recoveryDuration Duration of recovery period after failure (0 for no recovery)
     */
    function generateYieldFailure(
        address strategy,
        uint256 startTimestamp,
        uint256 duration,
        uint256 recoveryDuration
    ) external {
        // Get the starting yield rate
        uint256 startYieldRate = dataProvider.getYieldRate(strategy, startTimestamp);
        require(startYieldRate > 0, "No starting yield rate available");
        
        // Set yield to zero during failure period
        for (uint256 i = 0; i < 10; i++) {
            uint256 timestamp = startTimestamp + (i * duration / 10);
            dataProvider.setYieldRate(strategy, timestamp, 0);
        }
        
        // Generate recovery period if specified
        if (recoveryDuration > 0) {
            uint256 recoveryStart = startTimestamp + duration;
            uint256 recoveryTimeStep = recoveryDuration / 10;
            
            for (uint256 i = 1; i <= 10; i++) {
                uint256 timestamp = recoveryStart + (i * recoveryTimeStep);
                
                // Linear yield recovery
                uint256 yieldRate = (startYieldRate * i) / 10;
                
                // Set the yield rate in the data provider
                dataProvider.setYieldRate(strategy, timestamp, yieldRate);
            }
        }
    }
    
    /**
     * @notice Generate a liquidity crunch scenario
     * @param assets Array of asset addresses to apply the scenario to
     * @param startTimestamp Start timestamp of the scenario
     * @param duration Duration of the crunch in seconds
     * @param priceImpactPercentage Price impact percentage (e.g. 30 = 30%)
     */
    function generateLiquidityCrunch(
        address[] calldata assets,
        uint256 startTimestamp,
        uint256 duration,
        uint256 priceImpactPercentage
        /* uint256 spreadIncrease */
    ) external {
        for (uint256 a = 0; a < assets.length; a++) {
            address asset = assets[a];
            
            // Get the starting price
            uint256 startPrice = dataProvider.getAssetPrice(asset, startTimestamp);
            require(startPrice > 0, "No starting price available");
            
            // Calculate the impacted price
            uint256 impactedPrice = startPrice * (100 - priceImpactPercentage) / 100;
            
            // Generate timestamps and prices for the liquidity crunch period
            uint256 timeStep = duration / 10; // 10 steps during crunch
            for (uint256 i = 1; i <= 10; i++) {
                uint256 timestamp = startTimestamp + (i * timeStep);
                
                // Exponential price decline during liquidity crunch
                // More severe in the beginning, then stabilizing
                uint256 factor = 10 - i;
                uint256 price = startPrice - ((startPrice - impactedPrice) * factor * factor / 100);
                
                // Set the price in the data provider
                dataProvider.setAssetPrice(asset, timestamp, price);
            }
            
            // Return to normal after the crunch
            dataProvider.setAssetPrice(asset, startTimestamp + duration, startPrice);
        }
    }
    
    /**
     * @notice Generate a correlation breakdown scenario
     * @param assets Array of asset addresses to apply the scenario to
     * @param startTimestamp Start timestamp of the scenario
     * @param duration Duration of the correlation breakdown in seconds
     * @param divergencePercentage Maximum divergence percentage (e.g. 50 = 50%)
     */
    function generateCorrelationBreakdown(
        address[] calldata assets,
        uint256 startTimestamp,
        uint256 duration,
        uint256 divergencePercentage
    ) external {
        require(assets.length >= 2, "Need at least two assets");
        
        // Get starting prices
        uint256[] memory startPrices = new uint256[](assets.length);
        for (uint256 a = 0; a < assets.length; a++) {
            startPrices[a] = dataProvider.getAssetPrice(assets[a], startTimestamp);
            require(startPrices[a] > 0, "No starting price available");
        }
        
        // Generate timestamps and prices for the correlation breakdown period
        uint256 timeStep = duration / 10; // 10 steps during breakdown
        
        for (uint256 i = 1; i <= 10; i++) {
            uint256 timestamp = startTimestamp + (i * timeStep);
            
            // For each asset, generate a divergent price movement
            for (uint256 a = 0; a < assets.length; a++) {
                // Alternate between positive and negative divergence based on asset index
                int256 direction = a % 2 == 0 ? int256(1) : int256(-1);
                
                // Calculate divergence factor (increases over time)
                uint256 divergenceFactor = (divergencePercentage * i) / 10;
                
                // Apply divergence to price
                uint256 price;
                if (direction > 0) {
                    price = startPrices[a] * (100 + divergenceFactor) / 100;
                } else {
                    price = startPrices[a] * (100 - divergenceFactor) / 100;
                }
                
                // Set the price in the data provider
                dataProvider.setAssetPrice(assets[a], timestamp, price);
            }
        }
        
        // Return to normal after the breakdown
        for (uint256 a = 0; a < assets.length; a++) {
            dataProvider.setAssetPrice(assets[a], startTimestamp + duration, startPrices[a]);
        }
    }
    
    /**
     * @notice Generate a historical replay scenario based on a specific market event
     * @param asset The asset address to apply the scenario to
     * @param startTimestamp Start timestamp of the scenario
     * @param eventType The type of historical event to replay (1=2008 crash, 2=2017 crypto boom, 3=2020 COVID crash)
     */
    function generateHistoricalReplay(
        address asset,
        uint256 startTimestamp,
        uint8 eventType
    ) external {
        // Get the starting price
        uint256 startPrice = dataProvider.getAssetPrice(asset, startTimestamp);
        require(startPrice > 0, "No starting price available");
        
        // Define price movements based on historical events
        int256[] memory priceMovements;
        uint256 duration;
        
        if (eventType == 1) {
            // 2008 Financial Crisis - 12 months of data with monthly steps
            priceMovements = new int256[](12);
            priceMovements[0] = -5;  // Sep 2008
            priceMovements[1] = -15; // Oct 2008
            priceMovements[2] = -10; // Nov 2008
            priceMovements[3] = -5;  // Dec 2008
            priceMovements[4] = -8;  // Jan 2009
            priceMovements[5] = -12; // Feb 2009
            priceMovements[6] = 5;   // Mar 2009
            priceMovements[7] = 8;   // Apr 2009
            priceMovements[8] = 6;   // May 2009
            priceMovements[9] = 4;   // Jun 2009
            priceMovements[10] = 7;  // Jul 2009
            priceMovements[11] = 3;  // Aug 2009
            duration = 365 days;
        } 
        else if (eventType == 2) {
            // 2017 Crypto Boom - 12 months of data with monthly steps
            priceMovements = new int256[](12);
            priceMovements[0] = 10;  // Jan 2017
            priceMovements[1] = 15;  // Feb 2017
            priceMovements[2] = 20;  // Mar 2017
            priceMovements[3] = 25;  // Apr 2017
            priceMovements[4] = 30;  // May 2017
            priceMovements[5] = 40;  // Jun 2017
            priceMovements[6] = 35;  // Jul 2017
            priceMovements[7] = 45;  // Aug 2017
            priceMovements[8] = 50;  // Sep 2017
            priceMovements[9] = 80;  // Oct 2017
            priceMovements[10] = 120; // Nov 2017
            priceMovements[11] = -30; // Dec 2017
            duration = 365 days;
        }
        else if (eventType == 3) {
            // 2020 COVID Crash - 6 months of data with monthly steps
            priceMovements = new int256[](6);
            priceMovements[0] = -5;   // Feb 2020
            priceMovements[1] = -30;  // Mar 2020
            priceMovements[2] = 15;   // Apr 2020
            priceMovements[3] = 10;   // May 2020
            priceMovements[4] = 8;    // Jun 2020
            priceMovements[5] = 6;    // Jul 2020
            duration = 180 days;
        }
        else {
            revert("Invalid event type");
        }
        
        // Apply price movements
        uint256 timeStep = duration / priceMovements.length;
        uint256 currentPrice = startPrice;
        
        for (uint256 i = 0; i < priceMovements.length; i++) {
            uint256 timestamp = startTimestamp + (i * timeStep);
            
            // Calculate new price based on percentage movement
            if (priceMovements[i] >= 0) {
                currentPrice = currentPrice * (100 + uint256(priceMovements[i])) / 100;
            } else {
                currentPrice = currentPrice * (100 - uint256(-priceMovements[i])) / 100;
            }
            
            // Set the price in the data provider
            dataProvider.setAssetPrice(asset, timestamp, currentPrice);
        }
    }
}
