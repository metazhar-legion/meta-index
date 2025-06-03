// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {CapitalAllocationManager} from "../src/CapitalAllocationManager.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {RWAAssetWrapper} from "../src/RWAAssetWrapper.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SetupLocalFork
 * @notice Script to set up a local mainnet fork with deployed contracts for development and testing
 * @dev Run with: forge script script/SetupLocalFork.s.sol --fork-url $ETH_RPC_URL --broadcast
 */
contract SetupLocalFork is Script {
    // Constants
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant BTC_USD_PRICE_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    
    // Contract instances
    IndexFundVaultV2 public vault;
    FeeManager public feeManager;
    CapitalAllocationManager public allocationManager;
    IndexRegistry public indexRegistry;
    RWAAssetWrapper public sp500Wrapper;
    RWAAssetWrapper public btcWrapper;
    ChainlinkPriceOracle public priceOracle;
    
    // Test accounts
    address deployer;
    address investor1;
    address investor2;
    address daoMember;
    
    function setUp() public {
        // Set up test accounts
        deployer = vm.addr(1);
        investor1 = vm.addr(2);
        investor2 = vm.addr(3);
        daoMember = vm.addr(4);
        
        // Fund accounts with ETH
        vm.deal(deployer, 100 ether);
        vm.deal(investor1, 10 ether);
        vm.deal(investor2, 10 ether);
        vm.deal(daoMember, 10 ether);
        
        // Fund accounts with USDC (using deal cheatcode)
        vm.deal(address(USDC_ADDRESS), 1000 ether); // Fund the USDC contract itself
        vm.startPrank(address(USDC_ADDRESS));
        // This is a simplified approach since we can't directly mint USDC tokens in a fork
        // In a real scenario, we would use a whale address or other methods
        vm.stopPrank();
    }
    
    function run() public {
        setUp();
        
        // Start broadcasting transactions from deployer
        vm.startBroadcast(deployer);
        
        // Deploy price oracle with USDC as base asset
        priceOracle = new ChainlinkPriceOracle(USDC_ADDRESS);
        
        // Set price feeds for assets
        priceOracle.setPriceFeed(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), ETH_USD_PRICE_FEED); // WETH
        priceOracle.setPriceFeed(address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), BTC_USD_PRICE_FEED); // WBTC
        
        // Deploy fee manager
        feeManager = new FeeManager();
        feeManager.setManagementFee(200); // 2% annual management fee (in basis points)
        feeManager.setPerformanceFee(2000); // 20% performance fee (in basis points)
        
        // Deploy capital allocation manager
        allocationManager = new CapitalAllocationManager();
        
        // Deploy index registry
        indexRegistry = new IndexRegistry();
        
        // Deploy asset wrappers
        sp500Wrapper = new RWASyntheticSP500(
            "S&P 500 Index",
            "SP500",
            USDC_ADDRESS,
            address(priceOracle)
        );
        
        btcWrapper = new RWAAssetWrapper(
            "Bitcoin",
            "BTC",
            USDC_ADDRESS,
            address(priceOracle)
        );
        
        // Register wrappers with index registry
        address[] memory wrappers = new address[](2);
        wrappers[0] = address(sp500Wrapper);
        wrappers[1] = address(btcWrapper);
        indexRegistry.addWrappers(wrappers);
        
        // Set allocation targets
        uint256[] memory targets = new uint256[](2);
        targets[0] = 6000; // 60% S&P 500
        targets[1] = 4000; // 40% BTC
        allocationManager.setAllocationTargets(wrappers, targets);
        
        // Deploy vault
        vault = new IndexFundVaultV2(
            "Web3 Index Fund",
            "W3IF",
            USDC_ADDRESS,
            address(feeManager),
            address(allocationManager),
            address(indexRegistry)
        );
        
        // Set vault as approved for wrappers
        sp500Wrapper.setVault(address(vault));
        btcWrapper.setVault(address(vault));
        
        // Grant roles
        bytes32 managerRole = vault.MANAGER_ROLE();
        vault.grantRole(managerRole, daoMember);
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Output deployment information
        console.log("Local Mainnet Fork Setup Complete");
        console.log("--------------------------------");
        console.log("Vault: ", address(vault));
        console.log("FeeManager: ", address(feeManager));
        console.log("AllocationManager: ", address(allocationManager));
        console.log("IndexRegistry: ", address(indexRegistry));
        console.log("S&P 500 Wrapper: ", address(sp500Wrapper));
        console.log("BTC Wrapper: ", address(btcWrapper));
        console.log("Price Oracle: ", address(priceOracle));
        console.log("--------------------------------");
        console.log("Deployer: ", deployer);
        console.log("Investor1: ", investor1);
        console.log("Investor2: ", investor2);
        console.log("DAO Member: ", daoMember);
    }
}
