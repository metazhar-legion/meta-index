// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {RWAIndexFundVault} from "../src/RWAIndexFundVault.sol";
import {ConcreteRWAIndexFundVault} from "../src/ConcreteRWAIndexFundVault.sol";
import {CapitalAllocationManager} from "../src/CapitalAllocationManager.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";

/**
 * @title DeployRWASP500
 * @dev Deployment script for the RWA S&P500 Synthetic Asset and integration with the Index Fund
 */
contract DeployRWASP500 is Script {
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
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying RWA S&P500 Synthetic Asset and Index Fund...");
        console.log("Deployer address:", deployer);

        // Deploy mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Mint USDC to the deployer
        usdc.mint(deployer, 1_000_000 * 1e6); // 1M USDC
        console.log("Minted 1,000,000 USDC to deployer");
        
        // Deploy price oracle
        MockPriceOracle priceOracle = new MockPriceOracle(address(usdc));
        console.log("MockPriceOracle deployed at:", address(priceOracle));
        
        // Deploy mock DEX
        MockDEX dex = new MockDEX(priceOracle);
        console.log("MockDEX deployed at:", address(dex));
        
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
        
        // Set price for RWA S&P500 in the oracle (e.g., $5000 per token)
        uint256 sp500Price = 5000 * 1e18; // $5000 with 18 decimals
        priceOracle.setPrice(address(rwaSP500), sp500Price);
        console.log("Set RWA S&P500 price to $5000 in the oracle");
        
        // Deploy index registry
        IndexRegistry indexRegistry = new IndexRegistry();
        console.log("IndexRegistry deployed at:", address(indexRegistry));
        
        // Add RWA S&P500 to the index with a 20% weight
        indexRegistry.addToken(address(rwaSP500), 2000); // 20% allocation
        console.log("Added RWA S&P500 to IndexRegistry with 20% weight");
        
        // Deploy capital allocation manager
        CapitalAllocationManager capitalAllocationManager = new CapitalAllocationManager(address(usdc));
        console.log("CapitalAllocationManager deployed at:", address(capitalAllocationManager));
        
        // Set allocation percentages (70% RWA, 20% yield, 10% liquidity buffer)
        capitalAllocationManager.setAllocation(7000, 2000, 1000);
        console.log("Set allocation percentages in CapitalAllocationManager");
        
        // Add RWA S&P500 to the capital allocation manager with 50% allocation within the RWA category
        capitalAllocationManager.addRWAToken(address(rwaSP500), 5000); // 50% allocation
        console.log("Added RWA S&P500 to CapitalAllocationManager with 50% allocation");
        
        // Deploy concrete RWA index fund vault
        ConcreteRWAIndexFundVault vault = new ConcreteRWAIndexFundVault(
            usdc,
            indexRegistry,
            priceOracle,
            dex,
            capitalAllocationManager
        );
        console.log("ConcreteRWAIndexFundVault deployed at:", address(vault));
        
        // Transfer ownership of the capital allocation manager to the vault
        capitalAllocationManager.transferOwnership(address(vault));
        console.log("Transferred ownership of CapitalAllocationManager to the vault");
        
        // Approve the vault to spend USDC
        usdc.approve(address(vault), 100_000 * 1e6); // 100,000 USDC
        console.log("Approved vault to spend 100,000 USDC");
        
        // Deposit into the vault
        vault.deposit(10_000 * 1e6, deployer); // 10,000 USDC
        console.log("Deposited 10,000 USDC into the vault");
        
        // Get vault share balance
        uint256 shareBalance = vault.balanceOf(deployer);
        console.log("Vault share balance:", shareBalance / 1e18, "shares");
        
        // Rebalance the vault to allocate funds to the RWA S&P500
        vault.rebalance();
        console.log("Rebalanced the vault to allocate funds to RWA S&P500");
        
        // Get total assets in the vault after rebalancing
        uint256 totalAssets = vault.totalAssets();
        console.log("Total assets in vault after rebalancing:", totalAssets / 1e6, "USDC");
        
        vm.stopBroadcast();
        
        // Print deployment summary
        console.log("\n=== RWA S&P500 Integration Summary ===");
        console.log("MockUSDC:", address(usdc));
        console.log("MockPriceOracle:", address(priceOracle));
        console.log("MockDEX:", address(dex));
        console.log("MockPerpetualTrading:", address(perpetualTrading));
        console.log("RWASyntheticSP500:", address(rwaSP500));
        console.log("IndexRegistry:", address(indexRegistry));
        console.log("CapitalAllocationManager:", address(capitalAllocationManager));
        console.log("ConcreteRWAIndexFundVault:", address(vault));
        console.log("=== Deployment Complete ===");
    }
}
