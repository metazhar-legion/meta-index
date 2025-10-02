// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceOracleV2} from "./interfaces/IPriceOracleV2.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title EnhancedChainlinkPriceOracle
 * @dev Enhanced Chainlink price oracle with staleness protection and fallback mechanisms
 * @notice Implements comprehensive oracle reliability features including circuit breakers
 */
contract EnhancedChainlinkPriceOracle is IPriceOracleV2, Ownable, Pausable {
    using Math for uint256;

    // ============ CONSTANTS ============
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 3600; // 1 hour
    uint256 public constant DEFAULT_DEVIATION_THRESHOLD = 1000; // 10%
    uint256 public constant MAX_STALENESS_THRESHOLD = 86400; // 24 hours
    uint256 public constant MAX_DEVIATION_THRESHOLD = 5000; // 50%
    uint256 public constant CIRCUIT_BREAKER_THRESHOLD = 5; // 5 failures
    uint256 public constant PRICE_DECIMALS = 18;

    // ============ STATE VARIABLES ============
    
    address public immutable baseAsset;
    uint8 public immutable baseAssetDecimals;
    
    // Oracle configurations per asset
    mapping(address => OracleConfig) public oracleConfigs;
    
    // Oracle health tracking
    mapping(address => OracleHealth) public oracleHealths;
    
    // Manual price overrides (emergency use)
    mapping(address => uint256) public manualPrices;
    mapping(address => uint256) public manualPriceExpiry;
    
    // Global configuration
    uint256 public globalStalenessThreshold = DEFAULT_STALENESS_THRESHOLD;
    uint256 public globalDeviationThreshold = DEFAULT_DEVIATION_THRESHOLD;
    
    // Emergency controls
    mapping(address => bool) public emergencyPaused;
    address public emergencyOperator;

    // ============ MODIFIERS ============
    
    modifier onlyEmergencyOperator() {
        require(msg.sender == emergencyOperator || msg.sender == owner(), "Not authorized");
        _;
    }
    
    modifier validAsset(address asset) {
        require(asset != address(0), "Zero address");
        require(oracleConfigs[asset].primaryOracle != address(0), "Asset not configured");
        _;
    }

    // ============ CONSTRUCTOR ============
    
    constructor(address _baseAsset, address _emergencyOperator) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        if (_emergencyOperator == address(0)) revert CommonErrors.ZeroAddress();
        
        baseAsset = _baseAsset;
        baseAssetDecimals = IERC20Metadata(_baseAsset).decimals();
        emergencyOperator = _emergencyOperator;
    }

    // ============ VIEW FUNCTIONS ============

    function getPrice(address asset) external view override returns (uint256) {
        PriceData memory priceData = getPriceData(asset);
        require(priceData.isValid, "Invalid price data");
        return priceData.price;
    }

    function getPriceData(address asset) public view override validAsset(asset) returns (PriceData memory priceData) {
        if (emergencyPaused[asset]) {
            revert CommonErrors.NotActive();
        }

        OracleConfig memory config = oracleConfigs[asset];
        
        // Check for manual override first
        if (manualPrices[asset] > 0 && block.timestamp <= manualPriceExpiry[asset]) {
            return PriceData({
                price: manualPrices[asset],
                timestamp: block.timestamp,
                blockNumber: block.number,
                isValid: true,
                sourceId: 255 // Manual override
            });
        }

        // Try primary oracle first
        (bool success, uint256 price, uint256 timestamp) = _tryGetPrice(config.primaryOracle);
        
        if (success && _isPriceFresh(timestamp, config.maxStaleness)) {
            return PriceData({
                price: price,
                timestamp: timestamp,
                blockNumber: block.number,
                isValid: true,
                sourceId: 0
            });
        }

        // Try fallback oracle
        if (config.fallbackOracle != address(0)) {
            (bool fallbackSuccess, uint256 fallbackPrice, uint256 fallbackTimestamp) = _tryGetPrice(config.fallbackOracle);
            
            if (fallbackSuccess && _isPriceFresh(fallbackTimestamp, config.maxStaleness)) {
                // If we have both prices, validate deviation
                if (success && price > 0) {
                    if (!validatePriceDeviation(asset, price, fallbackPrice)) {
                        // Deviation too high, use emergency oracle or fail
                        return _tryEmergencyOracle(asset, config);
                    }
                }

                return PriceData({
                    price: fallbackPrice,
                    timestamp: fallbackTimestamp,
                    blockNumber: block.number,
                    isValid: true,
                    sourceId: 1
                });
            }
        }

        // Try emergency oracle as last resort
        return _tryEmergencyOracle(asset, config);
    }

    function getOracleConfig(address asset) external view override returns (OracleConfig memory) {
        return oracleConfigs[asset];
    }

    function getOracleHealth(address asset) external view override returns (OracleHealth memory) {
        return oracleHealths[asset];
    }

    function isPriceFresh(address asset) external view override validAsset(asset) returns (bool) {
        OracleConfig memory config = oracleConfigs[asset];
        (, , uint256 timestamp) = _tryGetPrice(config.primaryOracle);
        return _isPriceFresh(timestamp, config.maxStaleness);
    }

    function getPriceAge(address asset) external view override validAsset(asset) returns (uint256) {
        OracleConfig memory config = oracleConfigs[asset];
        (, , uint256 timestamp) = _tryGetPrice(config.primaryOracle);
        return block.timestamp > timestamp ? block.timestamp - timestamp : 0;
    }

    function validatePriceDeviation(
        address asset,
        uint256 primaryPrice,
        uint256 fallbackPrice
    ) public view override returns (bool) {
        if (primaryPrice == 0 || fallbackPrice == 0) return false;
        
        uint256 maxDeviation = oracleConfigs[asset].maxPriceDeviation;
        if (maxDeviation == 0) maxDeviation = globalDeviationThreshold;
        
        uint256 deviation;
        if (primaryPrice > fallbackPrice) {
            deviation = ((primaryPrice - fallbackPrice) * BASIS_POINTS) / fallbackPrice;
        } else {
            deviation = ((fallbackPrice - primaryPrice) * BASIS_POINTS) / primaryPrice;
        }

        return deviation <= maxDeviation;
    }

    function convertToBaseAsset(address asset, uint256 amount) external view override returns (uint256) {
        uint256 price = this.getPrice(asset);
        uint8 tokenDecimals = IERC20Metadata(asset).decimals();
        
        // Convert to base asset value
        // amount * price / 10^tokenDecimals * 10^baseAssetDecimals / 10^priceDecimals
        return (amount * price * (10 ** baseAssetDecimals)) / 
               ((10 ** tokenDecimals) * (10 ** PRICE_DECIMALS));
    }

    function convertFromBaseAsset(address asset, uint256 baseAmount) external view override returns (uint256) {
        uint256 price = this.getPrice(asset);
        uint8 tokenDecimals = IERC20Metadata(asset).decimals();
        
        // Convert from base asset value
        return (baseAmount * (10 ** tokenDecimals) * (10 ** PRICE_DECIMALS)) / 
               (price * (10 ** baseAssetDecimals));
    }

    // ============ BATCH OPERATIONS ============

    function getPricesBatch(address[] calldata assets) external view override returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = this.getPrice(assets[i]);
        }
    }

    function getPriceDataBatch(address[] calldata assets) external view override returns (PriceData[] memory priceDataArray) {
        priceDataArray = new PriceData[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            priceDataArray[i] = getPriceData(assets[i]);
        }
    }

    // ============ STATE-CHANGING FUNCTIONS ============

    function updateOracleConfig(address asset, OracleConfig calldata config) external override onlyOwner {
        require(asset != address(0), "Zero address");
        require(config.primaryOracle != address(0), "No primary oracle");
        require(config.maxStaleness <= MAX_STALENESS_THRESHOLD, "Staleness too high");
        require(config.maxPriceDeviation <= MAX_DEVIATION_THRESHOLD, "Deviation too high");

        // Validate oracles work
        _validateOracle(config.primaryOracle);
        if (config.fallbackOracle != address(0)) {
            _validateOracle(config.fallbackOracle);
        }
        if (config.emergencyOracle != address(0)) {
            _validateOracle(config.emergencyOracle);
        }

        oracleConfigs[asset] = config;
        
        // Initialize health tracking
        oracleHealths[asset] = OracleHealth({
            isPrimaryHealthy: true,
            isFallbackHealthy: true,
            isEmergencyHealthy: true,
            lastPrimaryUpdate: block.timestamp,
            lastFallbackUpdate: block.timestamp,
            lastEmergencyUpdate: block.timestamp,
            failureCount: 0,
            circuitBreakerActive: false
        });

        emit OracleConfigUpdated(asset, config.primaryOracle, config.fallbackOracle, config.maxStaleness);
    }

    function updateOracleHealth(address asset) external override validAsset(asset) {
        OracleHealth storage health = oracleHealths[asset];
        OracleConfig memory config = oracleConfigs[asset];
        
        // Check primary oracle
        (bool primarySuccess, , uint256 primaryTimestamp) = _tryGetPrice(config.primaryOracle);
        bool primaryHealthy = primarySuccess && _isPriceFresh(primaryTimestamp, config.maxStaleness);
        
        // Check fallback oracle
        bool fallbackHealthy = true;
        if (config.fallbackOracle != address(0)) {
            (bool fallbackSuccess, , uint256 fallbackTimestamp) = _tryGetPrice(config.fallbackOracle);
            fallbackHealthy = fallbackSuccess && _isPriceFresh(fallbackTimestamp, config.maxStaleness);
        }
        
        // Update health status
        if (!primaryHealthy || !fallbackHealthy) {
            health.failureCount++;
        } else {
            health.failureCount = 0; // Reset on success
        }
        
        health.isPrimaryHealthy = primaryHealthy;
        health.isFallbackHealthy = fallbackHealthy;
        
        if (primaryHealthy) health.lastPrimaryUpdate = block.timestamp;
        if (fallbackHealthy) health.lastFallbackUpdate = block.timestamp;
        
        // Trigger circuit breaker if needed
        if (health.failureCount >= CIRCUIT_BREAKER_THRESHOLD && !health.circuitBreakerActive) {
            health.circuitBreakerActive = true;
            emergencyPaused[asset] = true;
            emit CircuitBreakerTriggered(asset, "Too many oracle failures", block.timestamp);
        }
        
        emit OracleHealthUpdated(asset, primaryHealthy, fallbackHealthy, health.failureCount);
    }

    function updateOracleHealthBatch(address[] calldata assets) external override {
        for (uint256 i = 0; i < assets.length; i++) {
            this.updateOracleHealth(assets[i]);
        }
    }

    function triggerCircuitBreaker(address asset, string calldata reason) external override onlyEmergencyOperator {
        oracleHealths[asset].circuitBreakerActive = true;
        emergencyPaused[asset] = true;
        emit CircuitBreakerTriggered(asset, reason, block.timestamp);
    }

    function resetCircuitBreaker(address asset) external override onlyOwner {
        oracleHealths[asset].circuitBreakerActive = false;
        oracleHealths[asset].failureCount = 0;
        emergencyPaused[asset] = false;
    }

    function setManualPrice(address asset, uint256 price, uint256 validityPeriod) external override onlyEmergencyOperator {
        require(price > 0, "Invalid price");
        require(validityPeriod <= 86400, "Validity too long"); // Max 24 hours
        
        manualPrices[asset] = price;
        manualPriceExpiry[asset] = block.timestamp + validityPeriod;
    }

    // ============ ADMIN FUNCTIONS ============

    function setGlobalStalenessThreshold(uint256 maxStaleness) external override onlyOwner {
        require(maxStaleness <= MAX_STALENESS_THRESHOLD, "Threshold too high");
        globalStalenessThreshold = maxStaleness;
    }

    function setGlobalDeviationThreshold(uint256 maxDeviation) external override onlyOwner {
        require(maxDeviation <= MAX_DEVIATION_THRESHOLD, "Threshold too high");
        globalDeviationThreshold = maxDeviation;
    }

    function pauseOracle(address asset) external override onlyEmergencyOperator {
        emergencyPaused[asset] = true;
    }

    function unpauseOracle(address asset) external override onlyOwner {
        emergencyPaused[asset] = false;
        oracleHealths[asset].circuitBreakerActive = false;
    }

    function setEmergencyOperator(address _emergencyOperator) external onlyOwner {
        require(_emergencyOperator != address(0), "Zero address");
        emergencyOperator = _emergencyOperator;
    }

    function pause() external onlyEmergencyOperator {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ INTERNAL FUNCTIONS ============

    function _tryGetPrice(address oracle) internal view returns (bool success, uint256 price, uint256 timestamp) {
        if (oracle == address(0)) return (false, 0, 0);
        
        try AggregatorV3Interface(oracle).latestRoundData() returns (
            uint80,
            int256 _price,
            uint256,
            uint256 _timestamp,
            uint80
        ) {
            if (_price > 0) {
                return (true, uint256(_price), _timestamp);
            }
        } catch {
            return (false, 0, 0);
        }
        
        return (false, 0, 0);
    }

    function _isPriceFresh(uint256 timestamp, uint256 maxStaleness) internal view returns (bool) {
        if (maxStaleness == 0) maxStaleness = globalStalenessThreshold;
        return block.timestamp <= timestamp + maxStaleness;
    }

    function _tryEmergencyOracle(address /* asset */, OracleConfig memory config) internal view returns (PriceData memory) {
        if (config.emergencyOracle != address(0)) {
            (bool emergencySuccess, uint256 emergencyPrice, uint256 emergencyTimestamp) = _tryGetPrice(config.emergencyOracle);

            if (emergencySuccess && emergencyPrice > 0) {
                return PriceData({
                    price: emergencyPrice,
                    timestamp: emergencyTimestamp,
                    blockNumber: block.number,
                    isValid: true,
                    sourceId: 2
                });
            }
        }

        // All oracles failed
        return PriceData({
            price: 0,
            timestamp: 0,
            blockNumber: block.number,
            isValid: false,
            sourceId: 255
        });
    }

    function _validateOracle(address oracle) internal view {
        (bool success, uint256 price,) = _tryGetPrice(oracle);
        require(success && price > 0, "Invalid oracle");
    }
}