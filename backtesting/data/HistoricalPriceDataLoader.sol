// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HistoricalDataProvider.sol";
import "forge-std/console2.sol";
import "../../data/historical/HistoricalPriceData.sol";
import "../../data/historical/HistoricalPriceDataChecker.sol";

/**
 * @title HistoricalPriceDataLoader
 * @notice Helper contract to load real historical price data into the HistoricalDataProvider
 * @dev This contract will be used to load price data fetched from external APIs
 */
contract HistoricalPriceDataLoader {
    // Asset addresses (using placeholder addresses for demonstration)
    address constant SP500_TOKEN = address(0x2);
    address constant RWA_TOKEN = address(0x3);
    address constant RWA_WRAPPER = address(0x5);
    
    /**
     * @notice Load historical S&P 500 and RWA price data from 2020-2024
     * @param dataProvider The HistoricalDataProvider to load data into
     */
    function loadHistoricalPriceData(HistoricalDataProvider dataProvider) external {
        console2.log("Loading historical price data...");
        
        // Register assets
        dataProvider.addAsset(SP500_TOKEN);
        dataProvider.addAsset(RWA_TOKEN);
        dataProvider.addStrategy(RWA_WRAPPER);
        
        // Check if we should use real data or placeholder data
        bool useRealData = false;
        
        // Check if real data is available
        useRealData = HistoricalPriceDataChecker.checkForRealData();
        
        if (useRealData) {
            console2.log("Using real historical price data...");
            // Use the HistoricalPriceData library to load real data
            HistoricalPriceData.setupHistoricalPriceData(dataProvider);
            console2.log("Real historical price data loaded successfully.");
        } else {
            console2.log("Note: Using placeholder data. Run the fetch_historical_data.js script to generate real data.");
            
            // Sample data points (placeholder data)
            // Jan 1, 2020
            uint256 startTimestamp = 1577836800;
            uint256 sp500BasePrice = 3230 * 10**18;
            uint256 rwaBasePrice = 50 * 10**18;
            
            dataProvider.setAssetPrice(SP500_TOKEN, startTimestamp, sp500BasePrice);
            dataProvider.setAssetPrice(RWA_TOKEN, startTimestamp, rwaBasePrice);
            
            // Set up yield rates for RWA (assuming 4% annual yield)
            uint256 rwaYieldRate = 400; // 4% in basis points
            dataProvider.setYieldRate(RWA_WRAPPER, startTimestamp, rwaYieldRate);
            
            console2.log("Placeholder historical price data loaded.");
            console2.log("To load real data, run: node scripts/fetch_historical_data.js YOUR_API_KEY");
        }
    }
    
    /**
     * @notice Load historical yield data for RWA assets
     * @param dataProvider The HistoricalDataProvider to load data into
     */
    function loadHistoricalYieldData(HistoricalDataProvider dataProvider) external {
        // This function will be implemented when we have historical yield data
        // For now, we'll use a constant yield rate
        
        console2.log("Loading historical yield data...");
        
        // Set up yield rates for RWA (assuming 4% annual yield)
        uint256 rwaYieldRate = 400; // 4% in basis points
        
        // Start date: Jan 1, 2020
        uint256 startTimestamp = 1577836800;
        
        // Set yield rate for each quarter
        for (uint256 i = 0; i < 18; i++) { // 4.5 years, quarterly
            uint256 timestamp = startTimestamp + (i * 90 days);
            dataProvider.setYieldRate(RWA_WRAPPER, timestamp, rwaYieldRate);
        }
        
        console2.log("Historical yield data loaded.");
    }
}
