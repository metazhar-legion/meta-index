// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BacktestingFramework.sol";
import "../../src/interfaces/IAssetWrapper.sol";

/**
 * @title VaultSimulationEngine
 * @notice Simulation engine for vault operations
 * @dev This contract simulates the operations of an investment vault
 */
contract VaultSimulationEngine is ISimulationEngine {
    // Dependencies
    IHistoricalDataProvider public dataProvider;
    
    // Vault configuration
    address public baseAsset;
    uint256 public initialDeposit;
    uint256 public rebalanceThreshold; // In basis points (e.g. 500 = 5%)
    uint256 public rebalanceInterval; // In seconds
    uint256 public managementFeeRate; // In basis points per year (e.g. 100 = 1%)
    uint256 public performanceFeeRate; // In basis points (e.g. 1000 = 10%)
    
    // Vault state
    uint256 public lastRebalanceTimestamp;
    uint256 public highWaterMark; // For performance fee calculation
    mapping(address => uint256) public assetValues; // Current value in base asset
    mapping(address => uint256) public assetBaseValues; // Original value in base asset (for yield calculation)
    
    // Asset configuration
    AssetConfig[] public assets;
    
    struct AssetConfig {
        address tokenAddress;
        address wrapperAddress;
        uint256 targetWeight; // In basis points (e.g. 5000 = 50%)
        bool isYieldGenerating;
    }
    
    // Events
    event AssetAdded(address indexed token, address indexed wrapper, uint256 weight, bool isYieldGenerating);
    event Rebalanced(uint256 timestamp, uint256 totalValue);
    event YieldHarvested(uint256 timestamp, address indexed strategy, uint256 amount);
    event FeeCharged(uint256 timestamp, string feeType, uint256 amount);
    
    /**
     * @notice Constructor
     * @param _dataProvider Source of historical price and yield data
     * @param _baseAsset Base asset address (e.g. USDC)
     * @param _initialDeposit Initial deposit amount
     * @param _rebalanceThreshold Threshold for rebalancing (basis points)
     * @param _rebalanceInterval Minimum time between rebalances (seconds)
     * @param _managementFeeRate Annual management fee rate (basis points)
     * @param _performanceFeeRate Performance fee rate (basis points)
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
     * @notice Add an asset to the portfolio
     * @param tokenAddress Address of the token
     * @param wrapperAddress Address of the asset wrapper
     * @param targetWeight Target weight in basis points (e.g. 5000 = 50%)
     * @param isYieldGenerating Whether the asset generates yield
     */
    function addAsset(
        address tokenAddress,
        address wrapperAddress,
        uint256 targetWeight,
        bool isYieldGenerating
    ) external {
        require(tokenAddress != address(0), "Invalid token address");
        require(wrapperAddress != address(0), "Invalid wrapper address");
        
        // Add to assets array
        assets.push(AssetConfig({
            tokenAddress: tokenAddress,
            wrapperAddress: wrapperAddress,
            targetWeight: targetWeight,
            isYieldGenerating: isYieldGenerating
        }));
        
        emit AssetAdded(tokenAddress, wrapperAddress, targetWeight, isYieldGenerating);
    }
    
    /**
     * @notice Initialize the simulation engine
     * @param timestamp The timestamp to initialize at
     */
    function initialize(uint256 timestamp) external override {
        require(assets.length > 0, "No assets configured");
        
        // Check that weights sum to 10000 (100%)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            totalWeight += assets[i].targetWeight;
        }
        require(totalWeight == 10000, "Weights must sum to 100%");
        
        // Set initial allocation based on target weights
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
        
        // Update asset prices
        _updateAssetPrices(timestamp);
        
        // Calculate total portfolio value before fees
        portfolioValue = _calculateTotalPortfolioValue();
        
        // Charge management fee
        uint256 managementFee = _chargeManagementFee(timestamp, portfolioValue);
        portfolioValue -= managementFee;
        
        // Harvest yield if any
        yieldHarvested = _harvestYield(timestamp);
        
        // Check if rebalancing is needed
        rebalanced = _shouldRebalance(timestamp);
        if (rebalanced) {
            _rebalance(timestamp);
            gasCost += 10000; // Estimated gas cost for rebalancing on L2
        }
        
        // Charge performance fee if applicable
        uint256 performanceFee = _chargePerformanceFee(timestamp, portfolioValue);
        portfolioValue -= performanceFee;
        
        // Update return arrays with current values
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 currentValue = assetValues[asset.wrapperAddress];
            uint256 currentWeight = (currentValue * 10000) / portfolioValue;
            
            assetValuesArray[i] = currentValue;
            assetWeightsArray[i] = currentWeight;
        }
        
        // Add base gas cost for the transaction (L2 optimized)
        gasCost += 5000;
        
        return (
            portfolioValue,
            assetValuesArray,
            assetWeightsArray,
            yieldHarvested,
            rebalanced,
            gasCost
        );
    }
    
    /**
     * @notice Update asset prices from data provider
     * @param timestamp The current timestamp
     */
    function _updateAssetPrices(uint256 timestamp) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            
            // Get price from data provider
            uint256 price = dataProvider.getAssetPrice(asset.tokenAddress, timestamp);
            
            // Update asset value based on price change
            if (price > 0) {
                uint256 previousPrice = dataProvider.getAssetPrice(asset.tokenAddress, timestamp - 1 days);
                if (previousPrice > 0) {
                    assetValues[asset.wrapperAddress] = (assetValues[asset.wrapperAddress] * price) / previousPrice;
                }
            }
        }
    }
    
    /**
     * @notice Calculate the total portfolio value
     * @return totalValue The total portfolio value
     */
    function _calculateTotalPortfolioValue() internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            totalValue += assetValues[asset.wrapperAddress];
        }
        return totalValue;
    }
    
    /**
     * @notice Determine if rebalancing is needed
     * @param timestamp The current timestamp
     * @return shouldRebalance Whether rebalancing is needed
     */
    function _shouldRebalance(uint256 timestamp) internal view returns (bool) {
        // Check if minimum interval has passed
        if (lastRebalanceTimestamp > 0 && timestamp - lastRebalanceTimestamp < rebalanceInterval) {
            return false;
        }
        
        // Check if any asset is outside the threshold
        uint256 totalValue = _calculateTotalPortfolioValue();
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 currentValue = assetValues[asset.wrapperAddress];
            uint256 currentWeight = (currentValue * 10000) / totalValue;
            uint256 targetWeight = asset.targetWeight;
            
            // Calculate absolute difference from target weight
            uint256 weightDiff = currentWeight > targetWeight ? 
                currentWeight - targetWeight : targetWeight - currentWeight;
            
            // If difference exceeds threshold, rebalance
            if (weightDiff > rebalanceThreshold) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @notice Rebalance the portfolio
     * @param timestamp The current timestamp
     */
    function _rebalance(uint256 timestamp) internal {
        uint256 totalValue = _calculateTotalPortfolioValue();
        if (totalValue == 0) return;
        
        // Calculate target values for each asset
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            uint256 targetValue = (totalValue * asset.targetWeight) / 10000;
            // uint256 currentValue = assetValues[asset.wrapperAddress]; // Unused variable
            
            // Update asset values to match targets
            assetValues[asset.wrapperAddress] = targetValue;
            assetBaseValues[asset.wrapperAddress] = targetValue;
        }
        
        lastRebalanceTimestamp = timestamp;
        emit Rebalanced(timestamp, totalValue);
    }
    
    /**
     * @notice Harvest yield from yield-generating assets
     * @param timestamp The current timestamp
     * @return totalYield The total yield harvested
     */
    function _harvestYield(uint256 timestamp) internal returns (uint256 totalYield) {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            if (asset.isYieldGenerating) {
                // Get yield rate from data provider
                uint256 yieldRate = dataProvider.getYieldRate(asset.wrapperAddress, timestamp);
                if (yieldRate > 0) {
                    // Calculate yield based on base value and time since last harvest
                    uint256 baseValue = assetBaseValues[asset.wrapperAddress];
                    uint256 yield = (baseValue * yieldRate) / 10000;
                    
                    // Add yield to asset value
                    assetValues[asset.wrapperAddress] += yield;
                    totalYield += yield;
                    
                    emit YieldHarvested(timestamp, asset.wrapperAddress, yield);
                }
            }
        }
        return totalYield;
    }
    
    /**
     * @notice Charge management fee
     * @param timestamp The current timestamp
     * @param portfolioValue The current portfolio value
     * @return fee The management fee charged
     */
    function _chargeManagementFee(uint256 timestamp, uint256 portfolioValue) internal returns (uint256 fee) {
        // Calculate daily fee rate (annual rate / 365)
        uint256 dailyFeeRate = managementFeeRate / 365;
        
        // Calculate fee amount
        fee = (portfolioValue * dailyFeeRate) / 10000;
        
        if (fee > 0) {
            emit FeeCharged(timestamp, "Management", fee);
        }
        
        return fee;
    }
    
    /**
     * @notice Charge performance fee
     * @param timestamp The current timestamp
     * @param portfolioValue The current portfolio value
     * @return fee The performance fee charged
     */
    function _chargePerformanceFee(uint256 timestamp, uint256 portfolioValue) internal returns (uint256 fee) {
        // Only charge if portfolio value exceeds high water mark
        if (portfolioValue > highWaterMark) {
            // Calculate fee on profits above high water mark
            uint256 profit = portfolioValue - highWaterMark;
            fee = (profit * performanceFeeRate) / 10000;
            
            // Update high water mark
            highWaterMark = portfolioValue - fee;
            
            if (fee > 0) {
                emit FeeCharged(timestamp, "Performance", fee);
            }
        }
        
        return fee;
    }
}
