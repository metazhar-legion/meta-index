// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {IndexFundVault} from "../src/IndexFundVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";

/**
 * @title DeploySepolia
 * @dev Deployment script for the Index Fund Vault on Sepolia testnet
 */
contract DeploySepolia is Script {
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
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy mock tokens for the index
        MockERC20 wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 link = new MockERC20("Chainlink", "LINK", 18);
        MockERC20 uni = new MockERC20("Uniswap", "UNI", 18);
        MockERC20 aave = new MockERC20("Aave", "AAVE", 18);
        
        // Deploy price oracle
        MockPriceOracle priceOracle = new MockPriceOracle(address(usdc));
        
        // Set prices for tokens (in USDC terms with 18 decimals)
        priceOracle.setPrice(address(wbtc), 50_000 * 1e18);
        priceOracle.setPrice(address(weth), 3_000 * 1e18);
        priceOracle.setPrice(address(link), 20 * 1e18);
        priceOracle.setPrice(address(uni), 10 * 1e18);
        priceOracle.setPrice(address(aave), 100 * 1e18);
        
        // Deploy DEX
        MockDEX dex = new MockDEX(priceOracle);
        
        // Deploy index registry
        IndexRegistry indexRegistry = new IndexRegistry();
        
        // Deploy fee manager
        FeeManager feeManager = new FeeManager();
        console.log("FeeManager deployed at:", address(feeManager));
        
        // Deploy index fund vault
        IndexFundVault vault = new IndexFundVault(
            usdc,
            indexRegistry,
            priceOracle,
            dex,
            IFeeManager(address(feeManager))
        );
        
        // Transfer ownership of the fee manager to the vault
        feeManager.transferOwnership(address(vault));
        console.log("Transferred ownership of FeeManager to the vault");
        
        // Set up initial index
        indexRegistry.addToken(address(wbtc), 4000); // 40%
        indexRegistry.addToken(address(weth), 3000); // 30%
        indexRegistry.addToken(address(link), 1000); // 10%
        indexRegistry.addToken(address(uni), 1000);  // 10%
        indexRegistry.addToken(address(aave), 1000); // 10%
        
        // Mint some tokens for testing
        usdc.mint(msg.sender, 1_000_000 * 1e6); // 1M USDC
        wbtc.mint(address(dex), 100 * 1e8);     // 100 BTC
        weth.mint(address(dex), 1000 * 1e18);   // 1000 ETH
        link.mint(address(dex), 100000 * 1e18); // 100,000 LINK
        uni.mint(address(dex), 100000 * 1e18);  // 100,000 UNI
        aave.mint(address(dex), 10000 * 1e18);  // 10,000 AAVE
        
        vm.stopBroadcast();
        
        // Log deployed addresses
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
    }
}
