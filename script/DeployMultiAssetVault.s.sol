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
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployMultiAssetVault
 * @dev Deployment script for a multi-asset vault using the new IndexFundVaultV2 architecture
 */
contract DeployMultiAssetVault is Script {
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

        console.log("Deploying Multi-Asset Vault with IndexFundVaultV2 architecture...");
        console.log("Deployer address:", deployer);

        // Deploy mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Mint USDC to the deployer
        usdc.mint(deployer, 10_000_000 * 1e6); // 10M USDC
        console.log("Minted 10,000,000 USDC to deployer");
        
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
        
        // Deploy yield strategy for all assets
        StableYieldStrategy yieldStrategy = new StableYieldStrategy(
            "Stable Yield",
            address(usdc),
            address(0), // No actual yield protocol in mock
            address(usdc), // Use USDC as mock yield token
            deployer // Fee recipient
        );
        console.log("StableYieldStrategy deployed at:", address(yieldStrategy));
        
        // Deploy RWA Synthetic S&P500 token
        RWASyntheticSP500 rwaSP500 = new RWASyntheticSP500(
            address(usdc),
            address(perpetualTrading),
            address(priceOracle)
        );
        console.log("RWASyntheticSP500 deployed at:", address(rwaSP500));
        
        // Set price for RWA S&P500 in the oracle
        priceOracle.setPrice(address(rwaSP500), 5000 * 1e18); // $5000 per token
        console.log("Set RWA S&P500 price to $5000 in the oracle");
        
        // Deploy RWA Asset Wrapper for S&P500
        RWAAssetWrapper sp500Wrapper = new RWAAssetWrapper(
            "S&P500 Wrapper",
            IERC20(address(usdc)),
            rwaSP500,
            yieldStrategy,
            priceOracle
        );
        console.log("RWAAssetWrapper for S&P500 deployed at:", address(sp500Wrapper));
        
        // Transfer ownership of RWA S&P500 to the RWA Asset Wrapper
        rwaSP500.transferOwnership(address(sp500Wrapper));
        console.log("Transferred ownership of RWA S&P500 to its wrapper");
        
        // Deploy a synthetic NASDAQ token
        RWASyntheticSP500 rwaNasdaq = new RWASyntheticSP500(
            address(usdc),
            address(perpetualTrading),
            address(priceOracle)
        );
        // We can't set name after deployment, so we'll just use the default name
        console.log("Synthetic NASDAQ deployed at:", address(rwaNasdaq));
        
        // Set price for NASDAQ in the oracle
        priceOracle.setPrice(address(rwaNasdaq), 15000 * 1e18); // $15000 per token
        console.log("Set NASDAQ price to $15000 in the oracle");
        
        // Deploy RWA Asset Wrapper for NASDAQ
        RWAAssetWrapper nasdaqWrapper = new RWAAssetWrapper(
            "NASDAQ Wrapper",
            IERC20(address(usdc)),
            rwaNasdaq,
            yieldStrategy,
            priceOracle
        );
        console.log("RWAAssetWrapper for NASDAQ deployed at:", address(nasdaqWrapper));
        
        // Transfer ownership of NASDAQ to its wrapper
        rwaNasdaq.transferOwnership(address(nasdaqWrapper));
        console.log("Transferred ownership of NASDAQ to its wrapper");
        
        // Deploy a synthetic Real Estate token
        RWASyntheticSP500 rwaRealEstate = new RWASyntheticSP500(
            address(usdc),
            address(perpetualTrading),
            address(priceOracle)
        );
        // We can't set name after deployment, so we'll just use the default name
        console.log("Synthetic Real Estate deployed at:", address(rwaRealEstate));
        
        // Set price for Real Estate in the oracle
        priceOracle.setPrice(address(rwaRealEstate), 1000 * 1e18); // $1000 per token
        console.log("Set Real Estate price to $1000 in the oracle");
        
        // Deploy RWA Asset Wrapper for Real Estate
        RWAAssetWrapper realEstateWrapper = new RWAAssetWrapper(
            "Real Estate Wrapper",
            IERC20(address(usdc)),
            rwaRealEstate,
            yieldStrategy,
            priceOracle
        );
        console.log("RWAAssetWrapper for Real Estate deployed at:", address(realEstateWrapper));
        
        // Transfer ownership of Real Estate to its wrapper
        rwaRealEstate.transferOwnership(address(realEstateWrapper));
        console.log("Transferred ownership of Real Estate to its wrapper");
        
        // Transfer ownership of Yield Strategy to the vault (single yield strategy for all assets)
        yieldStrategy.transferOwnership(address(vault));
        console.log("Transferred ownership of StableYieldStrategy to vault");
        
        // Add the asset wrappers to the vault with appropriate allocations
        vault.addAsset(address(sp500Wrapper), 5000);      // 50% S&P500
        vault.addAsset(address(nasdaqWrapper), 3000);     // 30% NASDAQ
        vault.addAsset(address(realEstateWrapper), 2000); // 20% Real Estate
        console.log("Added all asset wrappers to the vault with their allocations");
        
        // Approve the vault to spend USDC
        usdc.approve(address(vault), 1_000_000 * 1e6); // 1M USDC
        console.log("Approved vault to spend 1,000,000 USDC");
        
        // Deposit into the vault
        vault.deposit(100_000 * 1e6, deployer); // 100,000 USDC
        console.log("Deposited 100,000 USDC into the vault");
        
        // Get vault share balance
        uint256 shareBalance = vault.balanceOf(deployer);
        console.log("Vault share balance:", shareBalance / 1e18, "shares");
        
        // Force a rebalance to allocate assets
        vault.rebalance();
        console.log("Forced rebalance to allocate assets");
        
        vm.stopBroadcast();
        
        console.log("Multi-Asset Vault deployment complete!");
    }
}
