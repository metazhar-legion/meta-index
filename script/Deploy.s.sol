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

/**
 * @title Deploy
 * @dev Deployment script for the Index Fund Vault
 */
contract Deploy is Script {
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

        // Deploy mock USDC for testing
        MockUSDC usdc = new MockUSDC();
        
        // Deploy mock tokens for the index
        MockERC20 wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 link = new MockERC20("Chainlink", "LINK", 18);
        MockERC20 uni = new MockERC20("Uniswap", "UNI", 18);
        MockERC20 aave = new MockERC20("Aave", "AAVE", 18);
        
        // Deploy price oracle
        MockPriceOracle priceOracle = new MockPriceOracle(address(usdc));
        
        // Set prices for tokens (in USDC terms with 18 decimals)
        // For example, if BTC is $50,000 and USDC is $1, then BTC is 50,000 USDC
        priceOracle.setPrice(address(wbtc), 50_000 * 1e18);
        priceOracle.setPrice(address(weth), 3_000 * 1e18);
        priceOracle.setPrice(address(link), 20 * 1e18);
        priceOracle.setPrice(address(uni), 10 * 1e18);
        priceOracle.setPrice(address(aave), 100 * 1e18);
        
        // Deploy DEX
        MockDEX dex = new MockDEX(priceOracle);
        
        // Deploy index registry
        IndexRegistry indexRegistry = new IndexRegistry();
        
        // Deploy index fund vault
        IndexFundVault vault = new IndexFundVault(
            usdc,
            indexRegistry,
            priceOracle,
            dex
        );
        
        // Set up initial index
        indexRegistry.addToken(address(wbtc), 4000); // 40%
        indexRegistry.addToken(address(weth), 3000); // 30%
        indexRegistry.addToken(address(link), 1000); // 10%
        indexRegistry.addToken(address(uni), 1000);  // 10%
        indexRegistry.addToken(address(aave), 1000); // 10%
        
        // Mint some tokens for testing
        address deployer = vm.addr(deployerPrivateKey);
        usdc.mint(deployer, 1_000_000 * 1e6); // 1M USDC
        wbtc.mint(address(dex), 100 * 1e8);     // 100 BTC
        weth.mint(address(dex), 1000 * 1e18);   // 1000 ETH
        link.mint(address(dex), 100000 * 1e18); // 100,000 LINK
        uni.mint(address(dex), 100000 * 1e18);  // 100,000 UNI
        aave.mint(address(dex), 10000 * 1e18);  // 10,000 AAVE
        
        // Deploy RWA S&P500 components
        console.log("\n=== Deploying RWA S&P500 Components ===");
        
        // Deploy mock perpetual trading platform
        MockPerpetualTrading perpetualTrading = new MockPerpetualTrading(address(usdc));
        console.log("MockPerpetualTrading deployed at:", address(perpetualTrading));
        
        // Deploy RWA Synthetic S&P500 token
        RWASyntheticSP500 rwaSP500 = new RWASyntheticSP500(
            address(usdc),
            address(perpetualTrading),
            address(priceOracle)
        );
        console.log("RWASyntheticSP500 deployed at:", address(rwaSP500));
        
        // Set price for RWA S&P500 in the oracle
        uint256 sp500Price = 5000 * 1e18; // $5000 with 18 decimals
        priceOracle.setPrice(address(rwaSP500), sp500Price);
        console.log("Set RWA S&P500 price to $5000 in the oracle");
        
        // Add RWA S&P500 to the index with a 10% weight
        // Adjust other weights to make room for S&P500
        indexRegistry.updateTokenWeight(address(wbtc), 3500); // 35% (was 40%)
        indexRegistry.updateTokenWeight(address(weth), 2500); // 25% (was 30%)
        indexRegistry.addToken(address(rwaSP500), 1000); // 10% allocation to S&P500
        console.log("Added RWA S&P500 to IndexRegistry with 10% weight");
        
        // Deploy capital allocation manager
        CapitalAllocationManager capitalAllocationManager = new CapitalAllocationManager(address(usdc));
        console.log("CapitalAllocationManager deployed at:", address(capitalAllocationManager));
        
        // Set allocation percentages (70% RWA, 20% yield, 10% liquidity buffer)
        capitalAllocationManager.setAllocation(7000, 2000, 1000);
        console.log("Set allocation percentages in CapitalAllocationManager");
        
        // Add RWA S&P500 to the capital allocation manager with 100% allocation within the RWA category
        capitalAllocationManager.addRWAToken(address(rwaSP500), 10000); // 100% allocation
        console.log("Added RWA S&P500 to CapitalAllocationManager with 100% allocation");
        
        // Deploy concrete RWA index fund vault
        ConcreteRWAIndexFundVault rwaVault = new ConcreteRWAIndexFundVault(
            usdc,
            indexRegistry,
            priceOracle,
            dex,
            capitalAllocationManager
        );
        console.log("ConcreteRWAIndexFundVault deployed at:", address(rwaVault));
        
        // Transfer ownership of the capital allocation manager to the vault
        capitalAllocationManager.transferOwnership(address(rwaVault));
        console.log("Transferred ownership of CapitalAllocationManager to the vault");
        
        // Approve the vault to spend USDC
        usdc.approve(address(rwaVault), 100_000 * 1e6); // 100,000 USDC
        console.log("Approved RWA vault to spend 100,000 USDC");
        
        // Deposit into the RWA vault
        rwaVault.deposit(10_000 * 1e6, deployer); // 10,000 USDC
        console.log("Deposited 10,000 USDC into the RWA vault");
        
        // Transfer some USDC to the CapitalAllocationManager for rebalancing
        // This is needed because the vault doesn't automatically transfer funds to the manager
        usdc.mint(address(capitalAllocationManager), 7000 * 1e6); // 7000 USDC (70% of deposit)
        console.log("Minted 7,000 USDC directly to CapitalAllocationManager for testing");
        
        // Rebalance the RWA vault to allocate funds to the RWA S&P500
        rwaVault.rebalance();
        console.log("Rebalanced the RWA vault to allocate funds to RWA S&P500");
        
        vm.stopBroadcast();
        
        // Log deployed addresses
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
        console.log("ConcreteRWAIndexFundVault deployed at:", address(rwaVault));
    }
}
