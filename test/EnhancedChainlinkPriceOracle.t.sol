// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EnhancedChainlinkPriceOracle.sol";
import "../src/interfaces/AggregatorV3Interface.sol";
import "../src/interfaces/IPriceOracleV2.sol";
import "./mocks/MockERC20.sol";

contract MockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint256 private _timestamp;
    uint80 private _roundId;
    
    constructor(int256 price, uint256 timestamp) {
        _price = price;
        _timestamp = timestamp;
        _roundId = 1;
    }
    
    function setPrice(int256 price, uint256 timestamp) external {
        _price = price;
        _timestamp = timestamp;
        _roundId++;
    }
    
    function decimals() external pure override returns (uint8) {
        return 8;
    }
    
    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }
    
    function version() external pure override returns (uint256) {
        return 1;
    }
    
    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _timestamp, _timestamp, _roundId);
    }
    
    function getRoundData(uint80 /* _roundId */) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _timestamp, _timestamp, _roundId);
    }
}

contract EnhancedChainlinkPriceOracleTest is Test {
    EnhancedChainlinkPriceOracle oracle;
    MockERC20 baseAsset;
    MockERC20 testToken;
    MockAggregator primaryAggregator;
    MockAggregator fallbackAggregator;
    MockAggregator emergencyAggregator;
    
    address emergencyOperator = address(0x1);
    
    function setUp() public {
        baseAsset = new MockERC20("USDC", "USDC", 6);
        testToken = new MockERC20("Test Token", "TEST", 18);
        
        oracle = new EnhancedChainlinkPriceOracle(address(baseAsset), emergencyOperator);
        
        // Create mock aggregators
        primaryAggregator = new MockAggregator(100000000, block.timestamp); // $1000
        fallbackAggregator = new MockAggregator(99000000, block.timestamp); // $990
        emergencyAggregator = new MockAggregator(98000000, block.timestamp); // $980
    }
    
    function test_BasicOracleConfiguration() public {
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600, // 1 hour
            maxPriceDeviation: 500, // 5%
            isPaused: false,
            lastUpdateTime: block.timestamp
        });

        oracle.updateOracleConfig(address(testToken), config);

        IPriceOracleV2.OracleConfig memory retrievedConfig = oracle.getOracleConfig(address(testToken));
        assertEq(retrievedConfig.primaryOracle, address(primaryAggregator));
        assertEq(retrievedConfig.fallbackOracle, address(fallbackAggregator));
        assertEq(retrievedConfig.emergencyOracle, address(emergencyAggregator));
    }
    
    function test_FreshPriceRetrieval() public {
        // Configure oracle
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 500,
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Get price - should use primary oracle
        uint256 price = oracle.getPrice(address(testToken));
        assertEq(price, 100000000); // $1000 with 8 decimals
    }
    
    function test_StalePriceFallback() public {
        // Configure oracle
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 1000, // 10% tolerance
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Make primary oracle stale
        vm.warp(block.timestamp + 7200); // 2 hours later
        
        // Price should fallback to fallback oracle
        uint256 price = oracle.getPrice(address(testToken));
        assertEq(price, 99000000); // $990 from fallback oracle
    }
    
    function test_PriceDeviationProtection() public {
        // Configure oracle with tight deviation tolerance
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 200, // 2% tolerance
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Set fallback price with high deviation
        fallbackAggregator.setPrice(80000000, block.timestamp); // $800 (20% deviation)
        
        // Make primary stale to force fallback
        primaryAggregator.setPrice(100000000, block.timestamp - 7200); // 2 hours old
        
        // Should reject fallback due to high deviation and use emergency oracle
        uint256 price = oracle.getPrice(address(testToken));
        assertEq(price, 98000000); // $980 from emergency oracle
    }
    
    function test_CircuitBreakerTriggered() public {
        // Configure oracle
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 500,
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Trigger circuit breaker
        vm.prank(emergencyOperator);
        oracle.triggerCircuitBreaker(address(testToken), "Manual test trigger");
        
        // Price retrieval should fail
        vm.expectRevert();
        oracle.getPrice(address(testToken));
    }
    
    function test_ManualPriceOverride() public {
        // Configure oracle
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 500,
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Set manual price override
        vm.prank(emergencyOperator);
        oracle.setManualPrice(address(testToken), 105000000, 1800); // $1050 for 30 minutes
        
        // Should use manual price
        uint256 price = oracle.getPrice(address(testToken));
        assertEq(price, 105000000);
        
        // After expiry, should use oracle again
        vm.warp(block.timestamp + 1801);
        price = oracle.getPrice(address(testToken));
        assertEq(price, 100000000); // Back to primary oracle
    }
    
    function test_OracleHealthMonitoring() public {
        // Configure oracle
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 500,
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Check initial health
        IPriceOracleV2.OracleHealth memory health = oracle.getOracleHealth(address(testToken));
        assertTrue(health.isPrimaryHealthy);
        assertTrue(health.isFallbackHealthy);
        assertEq(health.failureCount, 0);
        
        // Make primary oracle stale and update health
        primaryAggregator.setPrice(100000000, block.timestamp - 7200);
        oracle.updateOracleHealth(address(testToken));
        
        health = oracle.getOracleHealth(address(testToken));
        assertFalse(health.isPrimaryHealthy);
        assertTrue(health.isFallbackHealthy);
        assertEq(health.failureCount, 1);
    }
    
    function test_BatchOperations() public {
        // Configure oracle for test token
        IPriceOracleV2.OracleConfig memory config = IPriceOracleV2.OracleConfig({
            primaryOracle: address(primaryAggregator),
            fallbackOracle: address(fallbackAggregator),
            emergencyOracle: address(emergencyAggregator),
            maxStaleness: 3600,
            maxPriceDeviation: 500,
            isPaused: false,
            lastUpdateTime: block.timestamp
        });
        
        oracle.updateOracleConfig(address(testToken), config);
        
        // Test batch price retrieval
        address[] memory assets = new address[](1);
        assets[0] = address(testToken);
        
        uint256[] memory prices = oracle.getPricesBatch(assets);
        assertEq(prices.length, 1);
        assertEq(prices[0], 100000000);
        
        // Test batch health updates
        oracle.updateOracleHealthBatch(assets);

        IPriceOracleV2.OracleHealth memory health = oracle.getOracleHealth(address(testToken));
        assertTrue(health.isPrimaryHealthy);
    }
}