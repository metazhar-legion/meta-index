// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Import ComposableRWA contracts
import {ComposableRWABundle} from "../src/ComposableRWABundle.sol";
import {StrategyOptimizer} from "../src/StrategyOptimizer.sol";
import {TRSExposureStrategy} from "../src/strategies/TRSExposureStrategy.sol";
import {EnhancedPerpetualStrategy} from "../src/strategies/EnhancedPerpetualStrategy.sol";
import {DirectTokenStrategy} from "../src/strategies/DirectTokenStrategy.sol";

// Import mock infrastructure
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockRWAToken} from "../src/mocks/MockRWAToken.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockTRSProvider} from "../src/mocks/MockTRSProvider.sol";
import {MockPerpetualRouter} from "../src/mocks/MockPerpetualRouter.sol";
import {MockDEXRouter} from "../src/mocks/MockDEXRouter.sol";
import {MockYieldStrategy} from "../src/mocks/MockYieldStrategy.sol";

contract DeployComposableRWA is Script {
    // Deployment constants
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant INITIAL_MINT = 1000000 * 1e6; // 1M USDC
    uint256 constant RWA_TOKEN_PRICE = 100e18; // $100 per RWA token
    
    // Deployment addresses (will be set during deployment)
    address public deployer;
    
    // Core tokens
    MockUSDC public usdc;
    MockRWAToken public rwaToken;
    MockPriceOracle public priceOracle;
    
    // Core system
    StrategyOptimizer public optimizer;
    ComposableRWABundle public bundle;
    
    // Mock infrastructure
    MockTRSProvider public trsProvider;
    MockPerpetualRouter public perpetualRouter;
    MockDEXRouter public dexRouter;
    MockYieldStrategy public yieldStrategy;
    
    // Strategy contracts
    TRSExposureStrategy public trsStrategy;
    EnhancedPerpetualStrategy public perpetualStrategy;
    DirectTokenStrategy public directStrategy;

    function run() external {
        // Get deployer from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying ComposableRWA System...");
        console.log("Deployer address:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy base tokens and infrastructure
        deployTokensAndInfrastructure();
        
        // Step 2: Deploy core system contracts
        deployCoreSystem();
        
        // Step 3: Deploy strategy contracts
        deployStrategies();
        
        // Step 4: Configure the system
        configureSystem();
        
        // Step 5: Fund accounts for testing
        fundTestAccounts();
        
        vm.stopBroadcast();
        
        // Step 6: Log deployment addresses
        logDeploymentAddresses();
    }
    
    function deployTokensAndInfrastructure() internal {
        console.log("\n=== Deploying Tokens and Infrastructure ===");
        
        // Deploy USDC
        usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Deploy RWA Token
        rwaToken = new MockRWAToken("RWA Token", "RWA");
        rwaToken.setDecimals(6); // Match USDC decimals
        console.log("MockRWAToken deployed at:", address(rwaToken));
        
        // Deploy Price Oracle
        priceOracle = new MockPriceOracle(address(usdc));
        priceOracle.setPrice(address(rwaToken), RWA_TOKEN_PRICE);
        console.log("MockPriceOracle deployed at:", address(priceOracle));
        
        // Deploy TRS Provider
        trsProvider = new MockTRSProvider(address(usdc));
        console.log("MockTRSProvider deployed at:", address(trsProvider));
        
        // Deploy Perpetual Router
        perpetualRouter = new MockPerpetualRouter(address(priceOracle), address(usdc));
        console.log("MockPerpetualRouter deployed at:", address(perpetualRouter));
        
        // Deploy DEX Router
        dexRouter = new MockDEXRouter(address(usdc), address(rwaToken));
        console.log("MockDEXRouter deployed at:", address(dexRouter));
        
        // Deploy Yield Strategy
        yieldStrategy = new MockYieldStrategy(usdc, "Primary Yield Strategy");
        console.log("MockYieldStrategy deployed at:", address(yieldStrategy));
    }
    
    function deployCoreSystem() internal {
        console.log("\n=== Deploying Core System ===");
        
        // Deploy Strategy Optimizer
        optimizer = new StrategyOptimizer(address(priceOracle));
        console.log("StrategyOptimizer deployed at:", address(optimizer));
        
        // Deploy ComposableRWA Bundle
        bundle = new ComposableRWABundle(
            "ComposableRWA Bundle",
            address(usdc),
            address(priceOracle), 
            address(optimizer)
        );
        console.log("ComposableRWABundle deployed at:", address(bundle));
    }
    
    function deployStrategies() internal {
        console.log("\n=== Deploying Strategy Contracts ===");
        
        // Deploy TRS Exposure Strategy
        trsStrategy = new TRSExposureStrategy(
            address(usdc),
            address(trsProvider),
            address(priceOracle),
            "SP500", // underlying asset ID
            "TRS S&P 500 Strategy"
        );
        console.log("TRSExposureStrategy deployed at:", address(trsStrategy));
        
        // Deploy Enhanced Perpetual Strategy
        perpetualStrategy = new EnhancedPerpetualStrategy(
            address(usdc),
            address(perpetualRouter),
            address(priceOracle),
            "SP500-PERP", // market ID
            "Perpetual S&P 500 Strategy"
        );
        console.log("EnhancedPerpetualStrategy deployed at:", address(perpetualStrategy));
        
        // Deploy Direct Token Strategy
        directStrategy = new DirectTokenStrategy(
            address(usdc),
            address(rwaToken),
            address(priceOracle),
            address(dexRouter),
            "Direct RWA Token Strategy"
        );
        console.log("DirectTokenStrategy deployed at:", address(directStrategy));
    }
    
    function configureSystem() internal {
        console.log("\n=== Configuring System ===");
        
        // Configure DEX exchange rates
        // At $100 per RWA token: 1 USDC = 0.01 RWA tokens
        dexRouter.setExchangeRate(address(usdc), address(rwaToken), 1e16); // 1 USDC = 0.01 RWA
        dexRouter.setExchangeRate(address(rwaToken), address(usdc), 100e18); // 1 RWA = 100 USDC
        console.log("DEX exchange rates configured");
        
        // Add counterparties to TRS strategy
        trsStrategy.addCounterparty(address(0x1111), 4000, 2000000e6); // 40% allocation, $2M max
        trsStrategy.addCounterparty(address(0x2222), 3500, 1500000e6); // 35% allocation, $1.5M max
        trsStrategy.addCounterparty(address(0x3333), 2500, 1000000e6); // 25% allocation, $1M max
        console.log("TRS counterparties configured");
        
        // Add perpetual market
        perpetualRouter.addMarket(
            "SP500-PERP",
            "S&P 500 Perpetual",
            address(usdc),
            address(0), // No quote token needed for mock
            500 // 5x max leverage
        );
        console.log("Perpetual market configured");
        
        // Add yield strategy to DirectTokenStrategy
        directStrategy.addYieldStrategy(address(yieldStrategy), BASIS_POINTS); // 100% allocation
        console.log("Direct token yield strategy configured");
        
        // Add strategies to the bundle
        bundle.addExposureStrategy(address(trsStrategy), 4000, 6000, true);       // 40% target, 60% max, primary
        bundle.addExposureStrategy(address(perpetualStrategy), 3500, 5000, false); // 35% target, 50% max
        bundle.addExposureStrategy(address(directStrategy), 2500, 4000, false);   // 25% target, 40% max
        console.log("Strategies added to bundle");
        
        // Configure yield bundle
        address[] memory yieldStrategies = new address[](1);
        yieldStrategies[0] = address(yieldStrategy);
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = BASIS_POINTS; // 100% to single yield strategy
        bundle.updateYieldBundle(yieldStrategies, allocations);
        console.log("Yield bundle configured");
    }
    
    function fundTestAccounts() internal {
        console.log("\n=== Funding Test Accounts ===");
        
        // Fund deployer
        usdc.mint(deployer, INITIAL_MINT);
        console.log("Deployer funded with", INITIAL_MINT / 1e6, "USDC");
        
        // Fund some test addresses
        address[] memory testUsers = new address[](3);
        testUsers[0] = address(0x1001);
        testUsers[1] = address(0x1002);
        testUsers[2] = address(0x1003);
        
        for (uint i = 0; i < testUsers.length; i++) {
            usdc.mint(testUsers[i], INITIAL_MINT);
            console.log("Test user", testUsers[i], "funded with", INITIAL_MINT / 1e6, "USDC");
        }
        
        // Fund mock providers for operations
        usdc.mint(address(trsProvider), INITIAL_MINT);
        usdc.mint(address(perpetualRouter), INITIAL_MINT);
        usdc.mint(address(dexRouter), INITIAL_MINT);
        usdc.mint(address(yieldStrategy), INITIAL_MINT);
        
        // Mint RWA tokens for DEX operations
        rwaToken.mint(address(dexRouter), 100000e6); // 100k RWA tokens
        
        console.log("Mock providers funded for operations");
    }
    
    function logDeploymentAddresses() internal {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("");
        console.log("📋 Copy these addresses to frontend/src/contracts/addresses.ts:");
        console.log("");
        console.log("export const CONTRACT_ADDRESSES = {");
        console.log("  // Core ComposableRWABundle System");
        console.log("  COMPOSABLE_RWA_BUNDLE: '%s',", address(bundle));
        console.log("  STRATEGY_OPTIMIZER: '%s',", address(optimizer));
        console.log("  ");
        console.log("  // Exposure Strategies");
        console.log("  TRS_EXPOSURE_STRATEGY: '%s',", address(trsStrategy));
        console.log("  PERPETUAL_STRATEGY: '%s',", address(perpetualStrategy));
        console.log("  DIRECT_TOKEN_STRATEGY: '%s',", address(directStrategy));
        console.log("  ");
        console.log("  // Mock Infrastructure");
        console.log("  MOCK_USDC: '%s',", address(usdc));
        console.log("  MOCK_RWA_TOKEN: '%s',", address(rwaToken));
        console.log("  MOCK_PRICE_ORACLE: '%s',", address(priceOracle));
        console.log("  MOCK_TRS_PROVIDER: '%s',", address(trsProvider));
        console.log("  MOCK_PERPETUAL_ROUTER: '%s',", address(perpetualRouter));
        console.log("  MOCK_DEX_ROUTER: '%s',", address(dexRouter));
        console.log("  ");
        console.log("  // Legacy System (for compatibility)");
        console.log("  LEGACY_VAULT: '%s',", address(bundle));
        console.log("  LEGACY_REGISTRY: '%s',", address(optimizer));
        console.log("};");
        console.log("");
        console.log("🚀 Deployment Complete!");
        console.log("📊 Total deployed contracts: 11");
        console.log("💰 Bundle ready for capital allocation");
        console.log("🎯 Frontend ready for testing");
    }
}