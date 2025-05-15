// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {RWAWrapperFactory} from "../src/RWAWrapperFactory.sol";
import {RWAAssetWrapper} from "../src/RWAAssetWrapper.sol";
import {PerpetualPositionWrapper} from "../src/PerpetualPositionWrapper.sol";
import {MockPerpetualRouter} from "../src/mocks/MockPerpetualRouter.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";

/**
 * @title RWAWrapperFactoryTest
 * @dev Test contract for RWAWrapperFactory
 */
contract RWAWrapperFactoryTest is Test {
    // Test contracts
    RWAWrapperFactory public factory;
    MockPriceOracle public priceOracle;
    MockUSDC public usdc;
    MockPerpetualRouter public router;
    MockPerpetualTrading public perpetualTrading;
    MockDEX public dex;
    
    // Test parameters
    address public deployer = address(this);
    address public user = address(0x1);
    bytes32 public marketId = keccak256("BTC-USD");
    
    // Setup function
    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        priceOracle = new MockPriceOracle(address(usdc));
        dex = new MockDEX(address(priceOracle));
        perpetualTrading = new MockPerpetualTrading(address(usdc));
        router = new MockPerpetualRouter(address(priceOracle), address(usdc));
        
        // Set up market in router
        router.addMarket(
            marketId,
            "Bitcoin/USD",
            address(0x1234), // Mock BTC address
            address(usdc),
            5 // Max leverage
        );
        
        // Set initial price
        priceOracle.setPrice(address(0x1234), 50000 * 1e18); // $50,000 per BTC
        
        // Deploy factory
        factory = new RWAWrapperFactory(address(priceOracle), address(usdc));
        
        // Mint USDC for testing
        usdc.mint(address(this), 1000000 * 1e6); // 1M USDC
    }
    
    // Test creating a standard RWA wrapper
    function testCreateStandardWrapper() public {
        // Create standard wrapper
        address wrapperAddress = factory.createStandardWrapper(
            "S&P500 Wrapper",
            "S&P500 Synthetic",
            "sSPX",
            address(perpetualTrading),
            "Stablecoin Lending",
            address(0x123), // Mock lending protocol
            address(usdc),
            address(this)
        );
        
        // Verify wrapper was created
        assertTrue(wrapperAddress != address(0), "Wrapper address should not be zero");
        assertTrue(factory.isRegisteredWrapper(wrapperAddress), "Wrapper should be registered");
        
        // Verify wrapper is of correct type
        RWAAssetWrapper wrapper = RWAAssetWrapper(wrapperAddress);
        assertEq(wrapper.name(), "S&P500 Wrapper", "Wrapper name should match");
        assertEq(address(wrapper.baseAsset()), address(usdc), "Base asset should be USDC");
        assertEq(address(wrapper.priceOracle()), address(priceOracle), "Price oracle should match");
    }
    
    // Test creating a perpetual position wrapper
    function testCreatePerpetualPositionWrapper() public {
        // Create perpetual position wrapper
        address wrapperAddress = factory.createPerpetualPositionWrapper(
            "BTC Perpetual",
            address(router),
            marketId,
            2, // 2x leverage
            true, // Long position
            "BTC"
        );
        
        // Verify wrapper was created
        assertTrue(wrapperAddress != address(0), "Wrapper address should not be zero");
        assertTrue(factory.isRegisteredWrapper(wrapperAddress), "Wrapper should be registered");
        
        // Verify wrapper is of correct type
        PerpetualPositionWrapper wrapper = PerpetualPositionWrapper(wrapperAddress);
        assertEq(wrapper.assetSymbol(), "BTC", "Asset symbol should match");
        assertEq(address(wrapper.perpetualRouter()), address(router), "Perpetual router should match");
        assertEq(wrapper.marketId(), marketId, "Market ID should match");
        assertEq(wrapper.leverage(), 2, "Leverage should be 2x");
        assertTrue(wrapper.isLong(), "Position should be long");
    }
    
    // Test creating multiple wrappers and retrieving them
    function testGetAllWrappers() public {
        // Create two wrappers
        address wrapper1 = factory.createStandardWrapper(
            "S&P500 Wrapper",
            "S&P500 Synthetic",
            "sSPX",
            address(perpetualTrading),
            "Stablecoin Lending",
            address(0x123), // Mock lending protocol
            address(usdc),
            address(this)
        );
        
        address wrapper2 = factory.createPerpetualPositionWrapper(
            "BTC Perpetual",
            address(router),
            marketId,
            2, // 2x leverage
            true, // Long position
            "BTC"
        );
        
        // Get all wrappers
        address[] memory allWrappers = factory.getAllWrappers();
        
        // Verify correct wrappers are returned
        assertEq(allWrappers.length, 2, "Should have 2 wrappers");
        assertEq(allWrappers[0], wrapper1, "First wrapper should match");
        assertEq(allWrappers[1], wrapper2, "Second wrapper should match");
    }
    
    // Test changing factory settings
    function testChangeFactorySettings() public {
        // Create new price oracle
        MockPriceOracle newPriceOracle = new MockPriceOracle(address(usdc));
        
        // Create new base asset
        MockUSDC newBaseAsset = new MockUSDC();
        
        // Update factory settings
        factory.setPriceOracle(address(newPriceOracle));
        factory.setBaseAsset(address(newBaseAsset));
        
        // Verify settings were updated
        assertEq(address(factory.priceOracle()), address(newPriceOracle), "Price oracle should be updated");
        assertEq(factory.baseAsset(), address(newBaseAsset), "Base asset should be updated");
        
        // Create wrapper with new settings
        address wrapperAddress = factory.createPerpetualPositionWrapper(
            "BTC Perpetual",
            address(router),
            marketId,
            2, // 2x leverage
            true, // Long position
            "BTC"
        );
        
        // Verify wrapper uses new settings
        PerpetualPositionWrapper wrapper = PerpetualPositionWrapper(wrapperAddress);
        assertEq(address(wrapper.priceOracle()), address(newPriceOracle), "Wrapper should use new price oracle");
        assertEq(address(wrapper.baseAsset()), address(newBaseAsset), "Wrapper should use new base asset");
    }
    
    // Test creating a hybrid wrapper
    function testCreateHybridWrapper() public {
        // Create hybrid wrapper
        address wrapperAddress = factory.createHybridWrapper(
            "Hybrid Wrapper",
            "Hybrid Token",
            "HYB",
            address(router),
            marketId,
            2, // 2x leverage
            true, // Long position
            "Yield Strategy",
            address(0x123), // Mock lending protocol
            address(usdc),
            address(this)
        );
        
        // Verify wrapper was created
        assertTrue(wrapperAddress != address(0), "Wrapper address should not be zero");
        assertTrue(factory.isRegisteredWrapper(wrapperAddress), "Wrapper should be registered");
        
        // Verify wrapper is of correct type
        RWAAssetWrapper wrapper = RWAAssetWrapper(wrapperAddress);
        assertEq(wrapper.name(), "Hybrid Wrapper", "Wrapper name should match");
        assertEq(address(wrapper.baseAsset()), address(usdc), "Base asset should be USDC");
        assertEq(address(wrapper.priceOracle()), address(priceOracle), "Price oracle should match");
        
        // Verify that the wrapper has both a synthetic token and a yield strategy
        address rwaToken = address(wrapper.rwaToken());
        address yieldStrategy = address(wrapper.yieldStrategy());
        
        assertTrue(rwaToken != address(0), "RWA token should not be zero address");
        assertTrue(yieldStrategy != address(0), "Yield strategy should not be zero address");
    }
}
