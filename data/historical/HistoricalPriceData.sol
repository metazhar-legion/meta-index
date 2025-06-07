// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../backtesting/data/HistoricalDataProvider.sol";

/**
 * @title HistoricalPriceData
 * @notice Contains real historical price data for S&P 500 and RWA assets
 * @dev This is a template file that will be replaced by the output of fetch_historical_data.js
 */
library HistoricalPriceData {
    // Asset addresses (using placeholder addresses for demonstration)
    address constant SP500_TOKEN = address(0x2);
    address constant RWA_TOKEN = address(0x3);
    address constant RWA_WRAPPER = address(0x5);
    
    /**
     * @notice Set up historical price data in the HistoricalDataProvider
     * @param dataProvider The HistoricalDataProvider to populate with data
     */
    function setupHistoricalPriceData(HistoricalDataProvider dataProvider) internal {
        // This is a placeholder function that will be replaced by the generated code
        // from fetch_historical_data.js with real historical price data
        
        // Sample data points (these will be replaced with real data)
        // Jan 1, 2020
        uint256 startTimestamp = 1577836800;
        
        // S&P 500 data
        uint256 sp500BasePrice = 3230 * 10**18; // Starting price on Jan 1, 2020
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp, sp500BasePrice);
        
        // Example of additional data points (will be replaced with real data)
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 1 days, 3258 * 10**18);
        dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp + 2 days, 3265 * 10**18);
        
        // RWA data
        uint256 rwaBasePrice = 50 * 10**18; // Starting price
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp, rwaBasePrice);
        
        // Example of additional data points (will be replaced with real data)
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 1 days, 50.2 * 10**18);
        dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp + 2 days, 50.5 * 10**18);
        
        // Set up yield rates for RWA (assuming 4% annual yield)
        uint256 rwaYieldRate = 400; // 4% in basis points
        dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp, rwaYieldRate);
        
        // Additional yield data points can be added here
    }
}
