// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployChainlinkPriceOracle
 * @dev Deployment script for the Chainlink Price Oracle
 */
contract DeployChainlinkPriceOracle is Script {
    // Mainnet addresses
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC_MAINNET = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // Chainlink Price Feed addresses (Mainnet)
    address constant BTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    
    // Sepolia addresses
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Example address
    address constant WBTC_SEPOLIA = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063; // Example address
    address constant WETH_SEPOLIA = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; // Example address
    
    // Chainlink Price Feed addresses (Sepolia)
    address constant BTC_USD_FEED_SEPOLIA = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address constant ETH_USD_FEED_SEPOLIA = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    
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

        console.log("Deploying Chainlink Price Oracle...");
        console.log("Deployer address:", deployer);
        
        // Determine if we're on mainnet or testnet
        bool isMainnet = block.chainid == 1;
        
        // Select the appropriate addresses based on the network
        address usdc = isMainnet ? USDC_MAINNET : USDC_SEPOLIA;
        address wbtc = isMainnet ? WBTC_MAINNET : WBTC_SEPOLIA;
        address weth = isMainnet ? WETH_MAINNET : WETH_SEPOLIA;
        address btcUsdFeed = isMainnet ? BTC_USD_FEED : BTC_USD_FEED_SEPOLIA;
        address ethUsdFeed = isMainnet ? ETH_USD_FEED : ETH_USD_FEED_SEPOLIA;
        
        // Deploy the Chainlink Price Oracle
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(usdc);
        console.log("Chainlink Price Oracle deployed at:", address(oracle));
        
        // Set up price feeds
        oracle.setPriceFeed(wbtc, btcUsdFeed);
        console.log("Set BTC/USD price feed");
        
        oracle.setPriceFeed(weth, ethUsdFeed);
        console.log("Set ETH/USD price feed");
        
        vm.stopBroadcast();
    }
}
