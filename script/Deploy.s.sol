// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {IndexFundVault} from "../src/IndexFundVault.sol";
import {RWAIndexFundVault} from "../src/RWAIndexFundVault.sol";
import {ConcreteRWAIndexFundVault} from "../src/ConcreteRWAIndexFundVault.sol";
import {CapitalAllocationManager} from "../src/CapitalAllocationManager.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";

/**
 * @title Deploy
 * @dev Deployment script for the Index Fund Vault
 */
contract Deploy is Script {
    // Contract-level state variables to avoid stack too deep errors
    address public deployer;
    
    // Mock tokens
    MockUSDC public usdc;
    MockERC20 public wbtc;
    MockERC20 public weth;
    MockERC20 public link;
    MockERC20 public uni;
    MockERC20 public aave;
    
    // Infrastructure contracts
    MockPriceOracle public priceOracle;
    MockDEX public dex;
    IndexRegistry public indexRegistry;
    IndexFundVault public vault;
    
    // RWA components
    MockPerpetualTrading public perpetualTrading;
    RWASyntheticSP500 public rwaSP500;
    CapitalAllocationManager public capitalAllocationManager;
    FeeManager public feeManager;
    ConcreteRWAIndexFundVault public rwaVault;
    
    function run() external {
        uint256 deployerPrivateKey;
        
        // Try to get the private key from environment variable
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            deployerPrivateKey = pk;
            console.log("Using private key from environment variable");
        } catch {
            // If environment variable not found, use the default Anvil private key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Using default Anvil private key");
        }
        
        vm.startBroadcast(deployerPrivateKey);
        deployer = vm.addr(deployerPrivateKey);
        
        // Deploy in stages to avoid stack too deep errors
        deployMockTokens();
        deployInfrastructure();
        deployRWAComponents();
        configureAndTest();
        
        vm.stopBroadcast();
        
        // Log deployment summary
        logDeploymentSummary();
    }
    
    function deployMockTokens() internal {
        console.log("\n=== Deploying Mock Tokens ===");
        console.log("Deployer address:", deployer);
        
        // Deploy mock USDC for testing
        usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Mint some USDC to the deployer
        usdc.mint(deployer, 1_000_000 * 1e6); // 1M USDC
        console.log("Minted 1,000,000 USDC to deployer");
        
        // Deploy mock tokens for the index
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        link = new MockERC20("Chainlink", "LINK", 18);
        uni = new MockERC20("Uniswap", "UNI", 18);
        aave = new MockERC20("Aave", "AAVE", 18);
        console.log("Deployed mock ERC20 tokens for the index");
    }
    
    function deployInfrastructure() internal {
        console.log("\n=== Deploying Infrastructure Contracts ===");
        
        // Deploy price oracle
        priceOracle = new MockPriceOracle(address(usdc));
        console.log("MockPriceOracle deployed at:", address(priceOracle));
        
        // Set prices for tokens (in USDC terms with 18 decimals)
        priceOracle.setPrice(address(wbtc), 50_000 * 1e18);
        priceOracle.setPrice(address(weth), 3_000 * 1e18);
        priceOracle.setPrice(address(link), 20 * 1e18);
        priceOracle.setPrice(address(uni), 10 * 1e18);
        priceOracle.setPrice(address(aave), 100 * 1e18);
        console.log("Set prices for tokens in the oracle");
        
        // Deploy DEX
        dex = new MockDEX(address(priceOracle));
        console.log("MockDEX deployed at:", address(dex));
        
        // Mint tokens to the DEX for liquidity
        wbtc.mint(address(dex), 100 * 1e8);     // 100 BTC
        weth.mint(address(dex), 1000 * 1e18);   // 1000 ETH
        link.mint(address(dex), 100000 * 1e18); // 100,000 LINK
        uni.mint(address(dex), 100000 * 1e18);  // 100,000 UNI
        aave.mint(address(dex), 10000 * 1e18);  // 10,000 AAVE
        console.log("Minted tokens to the DEX for liquidity");
        
        // Deploy index registry
        indexRegistry = new IndexRegistry();
        console.log("IndexRegistry deployed at:", address(indexRegistry));
        
        // Set up initial index
        indexRegistry.addToken(address(wbtc), 4000); // 40%
        indexRegistry.addToken(address(weth), 3000); // 30%
        indexRegistry.addToken(address(link), 1000); // 10%
        indexRegistry.addToken(address(uni), 1000);  // 10%
        indexRegistry.addToken(address(aave), 1000); // 10%
        console.log("Set up initial index with token weights");
        
        // Deploy fee manager for the index fund vault
        FeeManager indexVaultFeeManager = new FeeManager();
        console.log("FeeManager for IndexFundVault deployed at:", address(indexVaultFeeManager));
        
        // Deploy index fund vault
        vault = new IndexFundVault(
            usdc,
            indexRegistry,
            priceOracle,
            dex,
            IFeeManager(address(indexVaultFeeManager))
        );
        
        // Transfer ownership of the fee manager to the vault
        indexVaultFeeManager.transferOwnership(address(vault));
        console.log("Transferred ownership of FeeManager to the IndexFundVault");
        console.log("IndexFundVault deployed at:", address(vault));
    }
    
    function deployRWAComponents() internal {
        console.log("\n=== Deploying RWA S&P500 Components ===");
        
        // Deploy mock perpetual trading platform
        perpetualTrading = new MockPerpetualTrading(address(usdc));
        console.log("MockPerpetualTrading deployed at:", address(perpetualTrading));
        
        // Deploy RWA Synthetic S&P500 token
        rwaSP500 = new RWASyntheticSP500(
            address(usdc),
            address(perpetualTrading),
            address(priceOracle)
        );
        console.log("RWASyntheticSP500 deployed at:", address(rwaSP500));
        
        // Set price for RWA S&P500 in the oracle
        uint256 sp500Price = 5000 * 1e18; // $5000 with 18 decimals
        priceOracle.setPrice(address(rwaSP500), sp500Price);
        console.log("Set RWA S&P500 price to $5000 in the oracle");
        
        // Define the amount of RWA tokens we want to mint - use USDC decimal precision (6 decimals)
        uint256 rwaMintAmount = 1 * 1e6; // 1 token with 6 decimals instead of 18
        
        // Approve RWASyntheticSP500 to spend exactly the amount of USDC needed for minting
        usdc.approve(address(rwaSP500), rwaMintAmount);
        console.log("Approved RWASyntheticSP500 to spend exact USDC amount needed");
        
        // Mint RWA S&P500 tokens to the deployer for testing
        rwaSP500.mint(deployer, rwaMintAmount); // 1 token with 6 decimals
        console.log("Minted RWA S&P500 tokens to deployer with 6 decimal precision");
        
        // Deploy capital allocation manager
        capitalAllocationManager = new CapitalAllocationManager(address(usdc));
        console.log("CapitalAllocationManager deployed at:", address(capitalAllocationManager));
        
        // Deploy fee manager
        feeManager = new FeeManager();
        console.log("FeeManager deployed at:", address(feeManager));
    }
    
    function configureAndTest() internal {
        console.log("\n=== Configuring and Testing ===");
        
        // Update index registry to include RWA S&P500
        indexRegistry.updateTokenWeight(address(wbtc), 3500); // 35% (was 40%)
        indexRegistry.updateTokenWeight(address(weth), 2500); // 25% (was 30%)
        indexRegistry.addToken(address(rwaSP500), 1000); // 10% allocation to S&P500
        console.log("Added RWA S&P500 to IndexRegistry with 10% weight");
        
        // Configure capital allocation manager
        capitalAllocationManager.setAllocation(7000, 2000, 1000); // 70% RWA, 20% yield, 10% buffer
        capitalAllocationManager.addRWAToken(address(rwaSP500), 10000); // 100% allocation
        console.log("Configured CapitalAllocationManager with allocations");
        
        // Transfer ownership of RWA S&P500 to the capital allocation manager
        rwaSP500.transferOwnership(address(capitalAllocationManager));
        console.log("Transferred ownership of RWA S&P500 to CapitalAllocationManager");
        
        // Deploy concrete RWA index fund vault
        rwaVault = new ConcreteRWAIndexFundVault(
            usdc,
            indexRegistry,
            priceOracle,
            dex,
            capitalAllocationManager,
            IFeeManager(address(feeManager))
        );
        console.log("ConcreteRWAIndexFundVault deployed at:", address(rwaVault));
        
        // Transfer ownership of the capital allocation manager to the vault
        capitalAllocationManager.transferOwnership(address(rwaVault));
        console.log("Transferred ownership of CapitalAllocationManager to the vault");
        
        // Transfer ownership of the fee manager to the vault
        feeManager.transferOwnership(address(rwaVault));
        console.log("Transferred ownership of FeeManager to the vault");
        
        // Approve and deposit into the RWA vault
        usdc.approve(address(rwaVault), 100_000 * 1e6); // 100,000 USDC
        rwaVault.deposit(10_000 * 1e6, deployer); // 10,000 USDC
        console.log("Deposited 10,000 USDC into the RWA vault");
        
        // Transfer some USDC to the CapitalAllocationManager for rebalancing
        usdc.mint(address(capitalAllocationManager), 7000 * 1e6); // 7000 USDC (70% of deposit)
        console.log("Minted 7,000 USDC directly to CapitalAllocationManager for testing");
        
        // Rebalance the RWA vault to allocate funds to the RWA S&P500
        rwaVault.rebalance();
        console.log("Rebalanced the RWA vault to allocate funds to RWA S&P500");
    }
    
    function logDeploymentSummary() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("USDC deployed at:", address(usdc));
        console.log("WBTC deployed at:", address(wbtc));
        console.log("WETH deployed at:", address(weth));
        console.log("LINK deployed at:", address(link));
        console.log("UNI deployed at:", address(uni));
        console.log("AAVE deployed at:", address(aave));
        console.log("Price Oracle deployed at:", address(priceOracle));
        console.log("DEX deployed at:", address(dex));
        console.log("Index Registry deployed at:", address(indexRegistry));
        console.log("Index Fund Vault deployed at:", address(vault));
        console.log("\n=== RWA Components ===");
        console.log("MockPerpetualTrading deployed at:", address(perpetualTrading));
        console.log("RWASyntheticSP500 deployed at:", address(rwaSP500));
        console.log("CapitalAllocationManager deployed at:", address(capitalAllocationManager));
        console.log("FeeManager deployed at:", address(feeManager));
        console.log("ConcreteRWAIndexFundVault deployed at:", address(rwaVault));
    }
}
