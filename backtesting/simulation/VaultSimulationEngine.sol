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
    
    // Timestamps for tracking events
    uint256 public lastRebalanceTimestamp;
    uint256 public lastYieldTimestamp;
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
        
        // Initialize timestamps
        lastYieldTimestamp = timestamp;
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
            
            // If no price available for this exact timestamp, find the most recent price
            if (price == 0) {
                // Look back up to 30 days to find a valid price
                for (uint256 j = 1; j <= 30; j++) {
                    price = dataProvider.getAssetPrice(asset.tokenAddress, timestamp - (j * 1 days));
                    if (price > 0) break;
                }
            }
            
            // Get previous price point for comparison
            uint256 previousTimestamp = lastRebalanceTimestamp > 0 ? lastRebalanceTimestamp : timestamp - 1 days;
            uint256 previousPrice = dataProvider.getAssetPrice(asset.tokenAddress, previousTimestamp);
            
            // If no previous price available, look for the most recent price before previousTimestamp
            if (previousPrice == 0) {
                // Look back up to 30 days to find a valid previous price
                for (uint256 j = 1; j <= 30; j++) {
                    previousPrice = dataProvider.getAssetPrice(asset.tokenAddress, previousTimestamp - (j * 1 days));
                    if (previousPrice > 0) break;
                }
            }
            
            // If we have both current and previous prices, update asset value
            if (price > 0 && previousPrice > 0) {
                // Calculate price change ratio and apply to asset value
                uint256 newValue = (assetValues[asset.wrapperAddress] * price) / previousPrice;
                assetValues[asset.wrapperAddress] = newValue;
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
        // If this is the first harvest, initialize lastYieldTimestamp
        if (lastYieldTimestamp == 0) {
            lastYieldTimestamp = timestamp;
            // Initialize assetBaseValues to match current assetValues
            for (uint256 i = 0; i < assets.length; i++) {
                AssetConfig memory asset = assets[i];
                if (asset.isYieldGenerating) {
                    assetBaseValues[asset.wrapperAddress] = assetValues[asset.wrapperAddress];
                }
            }
            return 0;
        }
        
        // Calculate time elapsed since last yield harvest in seconds
        uint256 timeElapsed = timestamp - lastYieldTimestamp;
        if (timeElapsed == 0) return 0;
        
        // Convert time elapsed to fraction of a year (365 days)
        // Using 1e18 for precision in the calculation
        uint256 yearFraction = (timeElapsed * 1e18) / 365 days;
        
        for (uint256 i = 0; i < assets.length; i++) {
            AssetConfig memory asset = assets[i];
            if (asset.isYieldGenerating) {
                // Get annual yield rate from data provider (in basis points)
                // The enhanced getYieldRate method will find the nearest yield rate within 90 days
                uint256 annualYieldRate = dataProvider.getYieldRate(asset.wrapperAddress, timestamp);
                
                // If still no yield rate found, use a default value for RWA assets (4%)
                if (annualYieldRate == 0) {
                    annualYieldRate = 400; // 4% annual yield in basis points
                }
                if (annualYieldRate > 0) {
                    // Calculate yield for the elapsed time period
                    uint256 baseValue = assetValues[asset.wrapperAddress]; // Use current value instead of base value
                    
                    // Convert annual yield to the actual yield for the elapsed time period
                    // annualYieldRate is in basis points (1/100 of a percent)
                    // 10000 basis points = 100%
                    uint256 periodYield = (baseValue * annualYieldRate * yearFraction) / (10000 * 1e18);
                    
                    // Add yield to asset value
                    assetValues[asset.wrapperAddress] += periodYield;
                    totalYield += periodYield;
                    
                    // Update base value for next yield calculation
                    assetBaseValues[asset.wrapperAddress] = assetValues[asset.wrapperAddress];
                    
                    // Log the yield harvested
                    emit YieldHarvested(timestamp, asset.wrapperAddress, periodYield);
                }
            }
        }
        
        // Update last yield timestamp
        lastYieldTimestamp = timestamp;
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
