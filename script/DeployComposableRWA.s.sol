// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// Import ComposableRWA contracts
import {ComposableRWABundle} from "../src/ComposableRWABundle.sol";
import {StrategyOptimizer} from "../src/StrategyOptimizer.sol";
import {TRSExposureStrategy} from "../src/strategies/TRSExposureStrategy.sol";
import {EnhancedPerpetualStrategy} from "../src/strategies/EnhancedPerpetualStrategy.sol";
import {DirectTokenStrategy} from "../src/strategies/DirectTokenStrategy.sol";

// Import Vault contracts
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";

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
    IndexFundVaultV2 public vault;
    FeeManager public feeManager;
    
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
        
        console2.log("Deploying ComposableRWA System...");
        console2.log("Deployer address:", deployer);
        
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
        console2.log("\n=== Deploying Tokens and Infrastructure ===");
        
        // Deploy USDC
        usdc = new MockUSDC();
        console2.log("MockUSDC deployed at:", address(usdc));
        
        // Deploy RWA Token
        rwaToken = new MockRWAToken("RWA Token", "RWA");
        rwaToken.setDecimals(6); // Match USDC decimals
        console2.log("MockRWAToken deployed at:", address(rwaToken));
        
        // Deploy Price Oracle
        priceOracle = new MockPriceOracle(address(usdc));
        priceOracle.setPrice(address(rwaToken), RWA_TOKEN_PRICE);
        console2.log("MockPriceOracle deployed at:", address(priceOracle));
        
        // Deploy TRS Provider
        trsProvider = new MockTRSProvider(address(usdc));
        console2.log("MockTRSProvider deployed at:", address(trsProvider));
        
        // Deploy Perpetual Router
        perpetualRouter = new MockPerpetualRouter(address(priceOracle), address(usdc));
        console2.log("MockPerpetualRouter deployed at:", address(perpetualRouter));
        
        // Deploy DEX Router
        dexRouter = new MockDEXRouter(address(usdc), address(rwaToken));
        console2.log("MockDEXRouter deployed at:", address(dexRouter));
        
        // Deploy Yield Strategy
        yieldStrategy = new MockYieldStrategy(usdc, "Primary Yield Strategy");
        console2.log("MockYieldStrategy deployed at:", address(yieldStrategy));
    }
    
    function deployCoreSystem() internal {
        console2.log("\n=== Deploying Core System ===");
        
        // Deploy Fee Manager
        feeManager = new FeeManager();
        console2.log("FeeManager deployed at:", address(feeManager));
        
        // Deploy Strategy Optimizer
        optimizer = new StrategyOptimizer(address(priceOracle));
        console2.log("StrategyOptimizer deployed at:", address(optimizer));
        
        // Deploy ComposableRWA Bundle
        bundle = new ComposableRWABundle(
            "ComposableRWA Bundle",
            address(usdc),
            address(priceOracle), 
            address(optimizer)
        );
        console2.log("ComposableRWABundle deployed at:", address(bundle));
        
        // Deploy IndexFundVaultV2 (ERC4626 Vault)
        vault = new IndexFundVaultV2(
            usdc,
            IFeeManager(address(feeManager)),
            priceOracle,
            IDEX(address(dexRouter))
        );
        console2.log("IndexFundVaultV2 deployed at:", address(vault));
        
        // Transfer fee manager ownership to vault
        feeManager.transferOwnership(address(vault));
        console2.log("FeeManager ownership transferred to vault");
    }
    
    function deployStrategies() internal {
        console2.log("\n=== Deploying Strategy Contracts ===");
        
        // Deploy TRS Exposure Strategy
        trsStrategy = new TRSExposureStrategy(
            address(usdc),
            address(trsProvider),
            address(priceOracle),
            "SP500", // underlying asset ID
            "TRS S&P 500 Strategy"
        );
        console2.log("TRSExposureStrategy deployed at:", address(trsStrategy));
        
        // Deploy Enhanced Perpetual Strategy
        perpetualStrategy = new EnhancedPerpetualStrategy(
            address(usdc),
            address(perpetualRouter),
            address(priceOracle),
            "SP500-PERP", // market ID
            "Perpetual S&P 500 Strategy"
        );
        console2.log("EnhancedPerpetualStrategy deployed at:", address(perpetualStrategy));
        
        // Deploy Direct Token Strategy
        directStrategy = new DirectTokenStrategy(
            address(usdc),
            address(rwaToken),
            address(priceOracle),
            address(dexRouter),
            "Direct RWA Token Strategy"
        );
        console2.log("DirectTokenStrategy deployed at:", address(directStrategy));
    }
    
    function configureSystem() internal {
        console2.log("\n=== Configuring System ===");
        
        // Configure DEX exchange rates
        // At $100 per RWA token: 1 USDC = 0.01 RWA tokens
        dexRouter.setExchangeRate(address(usdc), address(rwaToken), 1e16); // 1 USDC = 0.01 RWA
        dexRouter.setExchangeRate(address(rwaToken), address(usdc), 100e18); // 1 RWA = 100 USDC
        console2.log("DEX exchange rates configured");
        
        // Add counterparties to TRS strategy
        trsStrategy.addCounterparty(address(0x1111), 4000, 2000000e6); // 40% allocation, $2M max
        trsStrategy.addCounterparty(address(0x2222), 3500, 1500000e6); // 35% allocation, $1.5M max
        trsStrategy.addCounterparty(address(0x3333), 2500, 1000000e6); // 25% allocation, $1M max
        console2.log("TRS counterparties configured");
        
        // Add perpetual market
        perpetualRouter.addMarket(
            "SP500-PERP",
            "S&P 500 Perpetual",
            address(usdc),
            address(0), // No quote token needed for mock
            500 // 5x max leverage
        );
        console2.log("Perpetual market configured");
        
        // Add yield strategy to DirectTokenStrategy
        directStrategy.addYieldStrategy(address(yieldStrategy), BASIS_POINTS); // 100% allocation
        console2.log("Direct token yield strategy configured");
        
        // Add strategies to the bundle
        bundle.addExposureStrategy(address(trsStrategy), 4000, 6000, true);       // 40% target, 60% max, primary
        bundle.addExposureStrategy(address(perpetualStrategy), 3500, 5000, false); // 35% target, 50% max
        bundle.addExposureStrategy(address(directStrategy), 2500, 4000, false);   // 25% target, 40% max
        console2.log("Strategies added to bundle");
        
        // Configure yield bundle
        address[] memory yieldStrategies = new address[](1);
        yieldStrategies[0] = address(yieldStrategy);
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = BASIS_POINTS; // 100% to single yield strategy
        bundle.updateYieldBundle(yieldStrategies, allocations);
        console2.log("Yield bundle configured");
        
        // Add ComposableRWABundle as an asset to the vault
        vault.addAsset(address(bundle), BASIS_POINTS); // 100% weight to the bundle
        console2.log("ComposableRWABundle added to vault as asset wrapper");
        
        // Transfer bundle ownership to vault for proper management
        bundle.transferOwnership(address(vault));
        console2.log("Bundle ownership transferred to vault");
    }
    
    function fundTestAccounts() internal {
        console2.log("\n=== Funding Test Accounts ===");
        
        // Fund deployer
        usdc.mint(deployer, INITIAL_MINT);
        console2.log("Deployer funded with USDC");
        
        // Fund some test addresses
        address[] memory testUsers = new address[](3);
        testUsers[0] = address(0x1001);
        testUsers[1] = address(0x1002);
        testUsers[2] = address(0x1003);
        
        for (uint i = 0; i < testUsers.length; i++) {
            usdc.mint(testUsers[i], INITIAL_MINT);
            console2.log("Test user funded with USDC:", testUsers[i]);
        }
        
        // Fund mock providers for operations
        usdc.mint(address(trsProvider), INITIAL_MINT);
        usdc.mint(address(perpetualRouter), INITIAL_MINT);
        usdc.mint(address(dexRouter), INITIAL_MINT);
        usdc.mint(address(yieldStrategy), INITIAL_MINT);
        
        // Mint RWA tokens for DEX operations
        rwaToken.mint(address(dexRouter), 100000e6); // 100k RWA tokens
        
        console2.log("Mock providers funded for operations");
    }
    
    function logDeploymentAddresses() internal view {
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("");
        console2.log("Copy these addresses to frontend/src/contracts/addresses.ts:");
        console2.log("");
        console2.log("export const CONTRACT_ADDRESSES = {");
        console2.log("  // ERC4626 Vault (Main user interface)");
        console2.log("  VAULT:", address(vault));
        console2.log("  FEE_MANAGER:", address(feeManager));
        console2.log("  ");
        console2.log("  // Core ComposableRWABundle System");
        console2.log("  COMPOSABLE_RWA_BUNDLE:", address(bundle));
        console2.log("  STRATEGY_OPTIMIZER:", address(optimizer));
        console2.log("  ");
        console2.log("  // Exposure Strategies");
        console2.log("  TRS_EXPOSURE_STRATEGY:", address(trsStrategy));
        console2.log("  PERPETUAL_STRATEGY:", address(perpetualStrategy));
        console2.log("  DIRECT_TOKEN_STRATEGY:", address(directStrategy));
        console2.log("  ");
        console2.log("  // Mock Infrastructure");
        console2.log("  MOCK_USDC:", address(usdc));
        console2.log("  MOCK_RWA_TOKEN:", address(rwaToken));
        console2.log("  MOCK_PRICE_ORACLE:", address(priceOracle));
        console2.log("  MOCK_TRS_PROVIDER:", address(trsProvider));
        console2.log("  MOCK_PERPETUAL_ROUTER:", address(perpetualRouter));
        console2.log("  MOCK_DEX_ROUTER:", address(dexRouter));
        console2.log("};");
        console2.log("");
        console2.log("Deployment Complete!");
        console2.log("Total deployed contracts: 13");
        console2.log("Vault ready for deposits and withdrawals");
        console2.log("Bundle integrated as asset wrapper");
        console2.log("Frontend ready for testing");
    }
}