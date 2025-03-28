// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {RWAAssetWrapper} from "../src/RWAAssetWrapper.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {StableYieldStrategy} from "../src/StableYieldStrategy.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployIndexFundVaultV2
 * @dev Deployment script for the new simplified IndexFundVaultV2 architecture
 */
contract DeployIndexFundVaultV2 is Script {
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

        console.log("Deploying IndexFundVaultV2 with simplified architecture...");
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
        MockDEX dex = new MockDEX(address(priceOracle));
        console.log("MockDEX deployed at:", address(dex));
        
        // Deploy mock perpetual trading platform
        MockPerpetualTrading perpetualTrading = new MockPerpetualTrading(address(usdc));
        console.log("MockPerpetualTrading deployed at:", address(perpetualTrading));
        
        // Deploy fee manager
        FeeManager feeManager = new FeeManager();
        console.log("FeeManager deployed at:", address(feeManager));
        
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
        
        // Deploy StableYieldStrategy
        StableYieldStrategy yieldStrategy = new StableYieldStrategy(
            "Stable Yield",
            address(usdc),
            address(0), // No actual yield protocol in mock
            address(usdc), // Use USDC as mock yield token
            deployer // Fee recipient
        );
        console.log("StableYieldStrategy deployed at:", address(yieldStrategy));
        
        // Deploy the new vault
        IndexFundVaultV2 vault = new IndexFundVaultV2(
            usdc,
            IFeeManager(address(feeManager)),
            priceOracle,
            dex
        );
        
        // Set rebalance interval
        vault.setRebalanceInterval(24 hours);
        console.log("IndexFundVaultV2 deployed at:", address(vault));
        
        // Transfer ownership of the fee manager to the vault
        feeManager.transferOwnership(address(vault));
        console.log("Transferred ownership of FeeManager to the vault");
        
        // Deploy RWA Asset Wrapper for S&P500
        RWAAssetWrapper rwaWrapper = new RWAAssetWrapper(
            "S&P500 Wrapper",
            IERC20(address(usdc)),
            rwaSP500,
            yieldStrategy,
            priceOracle
        );
        console.log("RWAAssetWrapper for S&P500 deployed at:", address(rwaWrapper));
        
        // Transfer ownership of RWA S&P500 to the RWA Asset Wrapper
        rwaSP500.transferOwnership(address(rwaWrapper));
        console.log("Transferred ownership of RWA S&P500 to RWAAssetWrapper");
        
        // Transfer ownership of Yield Strategy to the RWA Asset Wrapper
        yieldStrategy.transferOwnership(address(rwaWrapper));
        console.log("Transferred ownership of StableYieldStrategy to RWAAssetWrapper");
        
        // Add the RWA Asset Wrapper to the vault with 80% allocation
        vault.addAsset(address(rwaWrapper), 8000); // 80% allocation
        console.log("Added RWAAssetWrapper to vault with 80% allocation");
        
        // Approve the vault to spend USDC
        usdc.approve(address(vault), 100_000 * 1e6); // 100,000 USDC
        console.log("Approved vault to spend 100,000 USDC");
        
        // Deposit into the vault
        vault.deposit(10_000 * 1e6, deployer); // 10,000 USDC
        console.log("Deposited 10,000 USDC into the vault");
        
        // Get vault share balance
        uint256 shareBalance = vault.balanceOf(deployer);
        console.log("Vault share balance:", shareBalance / 1e18, "shares");
        
        // Force a rebalance to allocate assets
        vault.rebalance();
        console.log("Forced rebalance to allocate assets");
        
        vm.stopBroadcast();
        
        console.log("Deployment complete!");
    }
}
