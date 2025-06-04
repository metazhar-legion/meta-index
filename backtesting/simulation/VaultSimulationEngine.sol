// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BacktestingFramework.sol";
import "../../src/interfaces/IAssetWrapper.sol";
import "../../src/interfaces/IYieldStrategy.sol";
import "../../src/interfaces/IPriceOracle.sol";
import "../../src/interfaces/IFeeManager.sol";

/**
 * @title VaultSimulationEngine
 * @notice Simulation engine that mimics the behavior of IndexFundVaultV2
 * @dev This contract simulates vault operations without actually executing them
 */
contract VaultSimulationEngine is ISimulationEngine {
    // Dependencies
    IHistoricalDataProvider public dataProvider;
    
    // Vault configuration
    address public baseAsset;
    uint256 public initialDeposit;
    uint256 public rebalanceThreshold; // in basis points (e.g., 500 = 5%)
    uint256 public rebalanceInterval; // in seconds
    uint256 public managementFeeRate; // in basis points per year
    uint256 public performanceFeeRate; // in basis points
    
    // Asset configuration
    struct AssetConfig {
        address assetAddress;
        address wrapperAddress;
        uint256 targetWeight; // in basis points (e.g., 5000 = 50%)
        bool isYieldGenerating;
    }
    AssetConfig[] public assets;
    
    // Simulation state
    uint256 public lastRebalanceTimestamp;
    uint256 public totalPortfolioValue;
    uint256 public highWaterMark;
    mapping(address => uint256) public assetValues;
    mapping(address => uint256) public assetBaseValues;
    
    // Events
    event Rebalanced(uint256 timestamp, uint256 portfolioValue);
    event YieldHarvested(uint256 timestamp, uint256 yieldAmount);
    
    /**
     * @notice Constructor
     * @param _dataProvider Source of historical price and yield data
     * @param _baseAsset Address of the base asset (e.g., USDC)
     * @param _initialDeposit Initial deposit amount
     * @param _rebalanceThreshold Threshold for triggering rebalance (in basis points)
     * @param _rebalanceInterval Minimum time between rebalances (in seconds)
     * @param _managementFeeRate Annual management fee rate (in basis points)
     * @param _performanceFeeRate Performance fee rate (in basis points)
     */
    constructor(
        IHistoricalDataProvider _dataProvider,
        address _baseAsset,
        uint256 _initialDeposit,
        uint256 _rebalanceThreshold,
        uint256 _rebalanceInterval,
        uint256 _managementFeeRate,
        uint256 _performanceFeeRate
    ) {
        dataProvider = _dataProvider;
        baseAsset = _baseAsset;
        initialDeposit = _initialDeposit;
        rebalanceThreshold = _rebalanceThreshold;
        rebalanceInterval = _rebalanceInterval;
        managementFeeRate = _managementFeeRate;
        performanceFeeRate = _performanceFeeRate;
    }
    
    /**
     * @notice Add an asset to the simulation
     * @param assetAddress Address of the asset
     * @param wrapperAddress Address of the asset wrapper
     * @param targetWeight Target weight for the asset (in basis points)
     * @param isYieldGenerating Whether the asset generates yield
     */
    function addAsset(
        address assetAddress,
        address wrapperAddress,
        uint256 targetWeight,
        bool isYieldGenerating
    ) external {
        // Ensure total weights don't exceed 10000 (100%)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            totalWeight += assets[i].targetWeight;
        }
        require(totalWeight + targetWeight <= 10000, "Total weight exceeds 100%");
        
        assets.push(
            AssetConfig({
                assetAddress: assetAddress,
                wrapperAddress: wrapperAddress,
                targetWeight: targetWeight,
                isYieldGenerating: isYieldGenerating
            })
        );
    }
    
    /**
     * @notice Initialize the simulation
     * @param startTimestamp The starting timestamp for the simulation
     */
    function initialize(uint256 startTimestamp) external override {
        require(assets.length > 0, "No assets configured");
        
        // Reset simulation state
        totalPortfolioValue = initialDeposit;
        highWaterMark = initialDeposit;
        lastRebalanceTimestamp = startTimestamp;
        
        // Initialize asset values based on target weights
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 assetValue = (initialDeposit * asset.targetWeight) / 10000;
            assetValues[asset.wrapperAddress] = assetValue;
            assetBaseValues[asset.wrapperAddress] = assetValue;
        }
    }
    
    /**
     * @notice Run a single simulation step
     * @param timestamp The current timestamp in the simulation
     * @return portfolioValue The total portfolio value
     * @return assetValuesArray Array of individual asset values
     * @return assetWeightsArray Array of asset weights (scaled by 10000)
     * @return yieldHarvested Amount of yield harvested in this step
     * @return rebalanced Whether a rebalance occurred in this step
     * @return gasCost Estimated gas cost for operations in this step
     */
    function runStep(uint256 timestamp) external override returns (
        uint256 portfolioValue,
        uint256[] memory assetValuesArray,
        uint256[] memory assetWeightsArray,
        uint256 yieldHarvested,
        bool rebalanced,
        uint256 gasCost
    ) {
        // Initialize return arrays
        assetValuesArray = new uint256[](assets.length);
        assetWeightsArray = new uint256[](assets.length);
        
        // Update asset values based on price changes
        _updateAssetValues(timestamp);
        
        // Check if rebalance is needed
        rebalanced = _isRebalanceNeeded(timestamp);
        
        // Harvest yield if available
        yieldHarvested = _harvestYield(timestamp);
        
        // Perform rebalance if needed
        if (rebalanced) {
            _rebalance(timestamp);
            gasCost = 500000; // Estimated gas cost for rebalance
        } else {
            gasCost = yieldHarvested > 0 ? 200000 : 50000; // Estimated gas costs
        }
        
        // Calculate current portfolio value
        portfolioValue = _calculateTotalPortfolioValue();
        
        // Update high water mark if needed
        if (portfolioValue > highWaterMark) {
            highWaterMark = portfolioValue;
        }
        
        // Collect management fee (pro-rated for the time step)
        uint256 timeElapsed = timestamp - lastRebalanceTimestamp;
        if (timeElapsed > 0) {
            uint256 annualFee = (portfolioValue * managementFeeRate) / 10000;
            uint256 feeForPeriod = (annualFee * timeElapsed) / (365 days);
            portfolioValue -= feeForPeriod;
        }
        
        // Populate return arrays with current values
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 value = assetValues[asset.wrapperAddress];
            assetValuesArray[i] = value;
            assetWeightsArray[i] = portfolioValue > 0 ? (value * 10000) / portfolioValue : 0;
        }
        
        return (portfolioValue, assetValuesArray, assetWeightsArray, yieldHarvested, rebalanced, gasCost);
    }
    
    /**
     * @notice Update asset values based on price changes
     * @param timestamp Current timestamp
     */
    function _updateAssetValues(uint256 timestamp) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            
            // Get current price from data provider
            uint256 price = dataProvider.getAssetPrice(asset.assetAddress, timestamp);
            if (price == 0) continue; // Skip if no price data available
            
            // Calculate new asset value based on price change
            uint256 previousPrice = dataProvider.getAssetPrice(asset.assetAddress, lastRebalanceTimestamp);
            if (previousPrice > 0) {
                uint256 baseValue = assetBaseValues[asset.wrapperAddress];
                uint256 newValue = (baseValue * price) / previousPrice;
                assetValues[asset.wrapperAddress] = newValue;
            }
        }
    }
    
    /**
     * @notice Check if rebalance is needed
     * @param timestamp Current timestamp
     * @return isNeeded Whether rebalance is needed
     */
    function _isRebalanceNeeded(uint256 timestamp) internal view returns (bool) {
        // Check time-based rebalance condition
        if (timestamp >= lastRebalanceTimestamp + rebalanceInterval) {
            return true;
        }
        
        // Check threshold-based rebalance condition
        uint256 totalValue = _calculateTotalPortfolioValue();
        if (totalValue == 0) return false;
        
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 currentValue = assetValues[asset.wrapperAddress];
            uint256 currentWeight = (currentValue * 10000) / totalValue;
            uint256 targetWeight = asset.targetWeight;
            
            // If any asset's weight deviates by more than the threshold, rebalance is needed
            if (currentWeight > targetWeight) {
                if (currentWeight - targetWeight > rebalanceThreshold) {
                    return true;
                }
            } else {
                if (targetWeight - currentWeight > rebalanceThreshold) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /**
     * @notice Harvest yield from yield-generating assets
     * @param timestamp Current timestamp
     * @return totalYield Total yield harvested
     */
    function _harvestYield(uint256 timestamp) internal returns (uint256 totalYield) {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            if (asset.isYieldGenerating) {
                // Get yield rate from data provider
                uint256 yieldRate = dataProvider.getYieldRate(asset.wrapperAddress, timestamp);
                if (yieldRate == 0) continue;
                
                // Calculate yield for the period since last update
                uint256 timeElapsed = timestamp - lastRebalanceTimestamp;
                uint256 assetValue = assetValues[asset.wrapperAddress];
                uint256 yieldAmount = (assetValue * yieldRate * timeElapsed) / (10000 * 365 days);
                
                // Add yield to asset value
                assetValues[asset.wrapperAddress] += yieldAmount;
                totalYield += yieldAmount;
            }
        }
        
        if (totalYield > 0) {
            emit YieldHarvested(timestamp, totalYield);
        }
        
        return totalYield;
    }
    
    /**
     * @notice Perform rebalancing of assets
     * @param timestamp Current timestamp
     */
    function _rebalance(uint256 timestamp) internal {
        uint256 totalValue = _calculateTotalPortfolioValue();
        if (totalValue == 0) return;
        
        // Calculate target values for each asset
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 targetValue = (totalValue * asset.targetWeight) / 10000;
            uint256 currentValue = assetValues[asset.wrapperAddress];
            
            // Update asset values to match targets
            assetValues[asset.wrapperAddress] = targetValue;
            assetBaseValues[asset.wrapperAddress] = targetValue;
        }
        
        lastRebalanceTimestamp = timestamp;
        emit Rebalanced(timestamp, totalValue);
    }
    
    /**
     * @notice Calculate total portfolio value
     * @return totalValue Sum of all asset values
     */
    function _calculateTotalPortfolioValue() internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            totalValue += assetValues[asset.wrapperAddress];
        }
        return totalValue;
    }
    
    /**
     * @notice Get the number of assets in the simulation
     * @return count The number of assets
     */
    function getAssetCount() external view returns (uint256) {
        return assets.length;
    }
    
    /**
     * @notice Get asset configuration by index
     * @param index The index of the asset
     * @return assetConfig The asset configuration
     */
    function getAssetConfig(uint256 index) external view returns (AssetConfig memory) {
        require(index < assets.length, "Index out of bounds");
        return assets[index];
    }
}
