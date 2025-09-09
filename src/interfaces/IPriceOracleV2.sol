// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPriceOracle.sol";

/**
 * @title IPriceOracleV2
 * @dev Enhanced price oracle interface with staleness protection and fallback mechanisms
 * @notice Extends IPriceOracle with advanced reliability features
 */
interface IPriceOracleV2 is IPriceOracle {
    
    // ============ STRUCTS ============
    
    /**
     * @dev Price data with metadata for staleness checks
     */
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 blockNumber;
        bool isValid;
        uint8 sourceId; // 0 = primary, 1 = fallback1, 2 = fallback2, etc.
    }

    /**
     * @dev Oracle configuration for an asset
     */
    struct OracleConfig {
        address primaryOracle;
        address fallbackOracle;
        address emergencyOracle;
        uint256 maxStaleness; // Maximum age in seconds
        uint256 maxPriceDeviation; // Maximum deviation in basis points (10000 = 100%)
        bool isPaused;
        uint256 lastUpdateTime;
    }

    /**
     * @dev Oracle health status
     */
    struct OracleHealth {
        bool isPrimaryHealthy;
        bool isFallbackHealthy;
        bool isEmergencyHealthy;
        uint256 lastPrimaryUpdate;
        uint256 lastFallbackUpdate;
        uint256 lastEmergencyUpdate;
        uint256 failureCount;
        bool circuitBreakerActive;
    }

    // ============ EVENTS ============
    
    event OracleConfigUpdated(
        address indexed asset, 
        address primaryOracle, 
        address fallbackOracle,
        uint256 maxStaleness
    );
    
    event FallbackOracleUsed(
        address indexed asset,
        address oracle,
        uint256 price,
        string reason
    );
    
    event OracleHealthUpdated(
        address indexed asset,
        bool isPrimaryHealthy,
        bool isFallbackHealthy,
        uint256 failureCount
    );
    
    event CircuitBreakerTriggered(
        address indexed asset,
        string reason,
        uint256 timestamp
    );
    
    event StaleDataDetected(
        address indexed asset,
        address oracle,
        uint256 dataAge,
        uint256 maxAge
    );
    
    event PriceDeviationAlert(
        address indexed asset,
        uint256 primaryPrice,
        uint256 fallbackPrice,
        uint256 deviation
    );

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Gets price data with metadata
     * @param asset Address of the asset
     * @return priceData Complete price data with validation info
     */
    function getPriceData(address asset) external view returns (PriceData memory priceData);
    
    /**
     * @dev Gets oracle configuration for an asset
     * @param asset Address of the asset
     * @return config Oracle configuration
     */
    function getOracleConfig(address asset) external view returns (OracleConfig memory config);
    
    /**
     * @dev Gets oracle health status for an asset
     * @param asset Address of the asset
     * @return health Oracle health information
     */
    function getOracleHealth(address asset) external view returns (OracleHealth memory health);
    
    /**
     * @dev Checks if price data is fresh (not stale)
     * @param asset Address of the asset
     * @return isFresh True if price is within staleness threshold
     */
    function isPriceFresh(address asset) external view returns (bool isFresh);
    
    /**
     * @dev Gets the age of the latest price data
     * @param asset Address of the asset
     * @return age Age in seconds since last update
     */
    function getPriceAge(address asset) external view returns (uint256 age);
    
    /**
     * @dev Validates price against deviation thresholds
     * @param asset Address of the asset
     * @param primaryPrice Primary oracle price
     * @param fallbackPrice Fallback oracle price
     * @return isValid True if deviation is within acceptable range
     */
    function validatePriceDeviation(
        address asset,
        uint256 primaryPrice,
        uint256 fallbackPrice
    ) external view returns (bool isValid);

    // ============ STATE-CHANGING FUNCTIONS ============
    
    /**
     * @dev Updates oracle configuration for an asset
     * @param asset Address of the asset
     * @param config New oracle configuration
     */
    function updateOracleConfig(address asset, OracleConfig calldata config) external;
    
    /**
     * @dev Manually triggers circuit breaker for an asset
     * @param asset Address of the asset
     * @param reason Reason for triggering circuit breaker
     */
    function triggerCircuitBreaker(address asset, string calldata reason) external;
    
    /**
     * @dev Resets circuit breaker for an asset (emergency function)
     * @param asset Address of the asset
     */
    function resetCircuitBreaker(address asset) external;
    
    /**
     * @dev Emergency function to set manual price override
     * @param asset Address of the asset
     * @param price Manual price to set
     * @param validityPeriod How long this manual price should be valid (seconds)
     */
    function setManualPrice(address asset, uint256 price, uint256 validityPeriod) external;
    
    /**
     * @dev Updates oracle health based on recent performance
     * @param asset Address of the asset
     */
    function updateOracleHealth(address asset) external;

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Sets global staleness threshold for all assets
     * @param maxStaleness New staleness threshold in seconds
     */
    function setGlobalStalenessThreshold(uint256 maxStaleness) external;
    
    /**
     * @dev Sets global deviation threshold for all assets
     * @param maxDeviation New deviation threshold in basis points
     */
    function setGlobalDeviationThreshold(uint256 maxDeviation) external;
    
    /**
     * @dev Pauses oracle for an asset
     * @param asset Address of the asset
     */
    function pauseOracle(address asset) external;
    
    /**
     * @dev Unpauses oracle for an asset
     * @param asset Address of the asset
     */
    function unpauseOracle(address asset) external;

    // ============ BATCH OPERATIONS ============
    
    /**
     * @dev Gets prices for multiple assets in a single call
     * @param assets Array of asset addresses
     * @return prices Array of current prices
     */
    function getPricesBatch(address[] calldata assets) external view returns (uint256[] memory prices);
    
    /**
     * @dev Gets price data for multiple assets in a single call
     * @param assets Array of asset addresses
     * @return priceDataArray Array of price data structs
     */
    function getPriceDataBatch(address[] calldata assets) external view returns (PriceData[] memory priceDataArray);
    
    /**
     * @dev Updates oracle health for multiple assets
     * @param assets Array of asset addresses
     */
    function updateOracleHealthBatch(address[] calldata assets) external;
}