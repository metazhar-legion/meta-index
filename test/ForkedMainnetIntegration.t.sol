// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {RWAAssetWrapper} from "../src/RWAAssetWrapper.sol";
import {PerpetualPositionWrapper} from "../src/PerpetualPositionWrapper.sol";
import {PerpetualPositionAdapter} from "../src/adapters/PerpetualPositionAdapter.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {CommonErrors} from "../src/libraries/CommonErrors.sol";

/**
 * @title ForkedMainnetIntegrationTest
 * @notice Integration tests for the Index Fund Vault using a forked mainnet environment
 * @dev These tests interact with real contracts deployed on mainnet
 */
contract ForkedMainnetIntegrationTest is Test {
    // Constants
    uint256 constant BASIS_POINTS = 10000; // 100% in basis points
    uint256 constant DEPOSIT_AMOUNT = 100_000 * 10**6; // 100,000 USDC
    
    // Mainnet contract addresses
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AAVE_LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 Pool
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 Router
    
    // Chainlink price feed addresses
    address constant BTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant SP500_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3; // Using S&P 500 / USD feed
    
    // Test accounts
    address owner;
    address user1;
    address user2;
    address treasury;
    
    // Contracts
    IERC20 usdc;
    IndexFundVaultV2 vault;
    RWAAssetWrapper sp500Wrapper;
    RWAAssetWrapper btcWrapper;
    PerpetualPositionAdapter sp500Adapter;
    PerpetualPositionAdapter btcAdapter;
    PerpetualPositionWrapper sp500PerpWrapper;
    PerpetualPositionWrapper btcPerpWrapper;
    
    // Fork ID
    uint256 mainnetFork;
    
    function setUp() public {
        // Create a fork of mainnet
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);
        
        // Set up test accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        treasury = makeAddr("treasury");
        
        // Deal USDC to test accounts
        vm.startPrank(address(0)); // Use address(0) as the sender for deal
        usdc = IERC20(USDC_ADDRESS);
        deal(address(usdc), user1, DEPOSIT_AMOUNT * 2);
        deal(address(usdc), user2, DEPOSIT_AMOUNT * 2);
        deal(address(usdc), owner, DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Deploy the contracts
        _deployContracts();
    }
    
    function _deployContracts() internal {
        vm.startPrank(owner);
        
        // Deploy the perpetual position wrappers
        sp500PerpWrapper = new PerpetualPositionWrapper(
            "S&P 500 Perpetual Position",
            USDC_ADDRESS
        );
        
        btcPerpWrapper = new PerpetualPositionWrapper(
            "BTC Perpetual Position",
            USDC_ADDRESS
        );
        
        // Deploy the perpetual position adapters
        sp500Adapter = new PerpetualPositionAdapter(
            address(sp500PerpWrapper),
            SP500_USD_FEED, // S&P 500 price feed
            USDC_ADDRESS,
            "S&P 500 Index",
            owner
        );
        
        btcAdapter = new PerpetualPositionAdapter(
            address(btcPerpWrapper),
            BTC_USD_FEED, // BTC price feed
            USDC_ADDRESS,
            "Bitcoin",
            owner
        );
        
        // Set up the adapters in the wrappers
        sp500PerpWrapper.setAdapter(address(sp500Adapter));
        btcPerpWrapper.setAdapter(address(btcAdapter));
        
        // Deploy the asset wrappers
        sp500Wrapper = new RWAAssetWrapper(
            "S&P 500 Index",
            USDC_ADDRESS,
            address(sp500Adapter)
        );
        
        btcWrapper = new RWAAssetWrapper(
            "Bitcoin",
            USDC_ADDRESS,
            address(btcAdapter)
        );
        
        // Deploy the vault
        vault = new IndexFundVaultV2(
            "Meta Index Fund",
            "META",
            USDC_ADDRESS,
            treasury,
            500, // 5% fee
            1 days, // 1 day rebalance interval
            300 // 3% rebalance threshold
        );
        
        // Add assets to the vault
        vault.addAsset(address(sp500Wrapper), 7000); // 70% allocation to S&P 500
        vault.addAsset(address(btcWrapper), 3000); // 30% allocation to BTC
        
        // Set leverage targets for the perpetual position adapters
        sp500Adapter.setLeverageTarget(300); // 3x leverage
        btcAdapter.setLeverageTarget(200); // 2x leverage
        
        // Set maximum position sizes
        sp500Adapter.setMaxPositionSize(8000); // 80% max allocation
        btcAdapter.setMaxPositionSize(5000); // 50% max allocation
        
        vm.stopPrank();
    }
    
    function test_ForkedMainnetEndToEndFlow() public {
        // User 1 deposits into the vault
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Check initial state
        uint256 initialTotalAssets = vault.totalAssets();
        console.log("Initial Total Assets:", initialTotalAssets);
        
        // Get initial wrapper values
        uint256 sp500InitialValue = sp500Wrapper.getValueInBaseAsset();
        uint256 btcInitialValue = btcWrapper.getValueInBaseAsset();
        console.log("Initial S&P 500 Wrapper Value:", sp500InitialValue);
        console.log("Initial BTC Wrapper Value:", btcInitialValue);
        
        // Perform initial rebalance
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        // Check values after rebalance
        uint256 sp500ValueAfterRebalance = sp500Wrapper.getValueInBaseAsset();
        uint256 btcValueAfterRebalance = btcWrapper.getValueInBaseAsset();
        uint256 totalValueAfterRebalance = sp500ValueAfterRebalance + btcValueAfterRebalance;
        
        console.log("After Rebalance:");
        console.log("S&P 500 Wrapper Value:", sp500ValueAfterRebalance);
        console.log("BTC Wrapper Value:", btcValueAfterRebalance);
        console.log("Total Wrapper Value:", totalValueAfterRebalance);
        
        // Calculate allocation percentages
        uint256 sp500PercentAfterRebalance = (sp500ValueAfterRebalance * BASIS_POINTS) / totalValueAfterRebalance;
        uint256 btcPercentAfterRebalance = (btcValueAfterRebalance * BASIS_POINTS) / totalValueAfterRebalance;
        
        console.log("S&P 500 Allocation:", sp500PercentAfterRebalance);
        console.log("BTC Allocation:", btcPercentAfterRebalance);
        
        // Verify allocations are close to targets (with some tolerance)
        assertApproxEqAbs(sp500PercentAfterRebalance, 7000, 200, "S&P 500 allocation should be close to 70%");
        assertApproxEqAbs(btcPercentAfterRebalance, 3000, 200, "BTC allocation should be close to 30%");
        
        // Simulate time passing (1 day) for the next rebalance
        vm.warp(block.timestamp + 1 days);
        
        // User 2 deposits
        vm.startPrank(user2);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user2);
        vm.stopPrank();
        
        // Check total assets after second deposit
        uint256 totalAssetsAfterDeposit2 = vault.totalAssets();
        console.log("Total Assets After Second Deposit:", totalAssetsAfterDeposit2);
        
        // Perform another rebalance
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        // Check values after second rebalance
        uint256 sp500ValueAfterRebalance2 = sp500Wrapper.getValueInBaseAsset();
        uint256 btcValueAfterRebalance2 = btcWrapper.getValueInBaseAsset();
        uint256 totalValueAfterRebalance2 = sp500ValueAfterRebalance2 + btcValueAfterRebalance2;
        
        console.log("After Second Rebalance:");
        console.log("S&P 500 Wrapper Value:", sp500ValueAfterRebalance2);
        console.log("BTC Wrapper Value:", btcValueAfterRebalance2);
        console.log("Total Wrapper Value:", totalValueAfterRebalance2);
        
        // User 1 withdraws half of their shares
        vm.startPrank(user1);
        uint256 user1Shares = vault.balanceOf(user1);
        vault.redeem(user1Shares / 2, user1, user1);
        vm.stopPrank();
        
        // Check total assets after withdrawal
        uint256 totalAssetsAfterWithdrawal = vault.totalAssets();
        console.log("Total Assets After Withdrawal:", totalAssetsAfterWithdrawal);
        
        // Verify the total assets decreased after withdrawal
        assertLt(totalAssetsAfterWithdrawal, totalAssetsAfterDeposit2, "Total assets should decrease after withdrawal");
    }
    
    function test_ForkedMainnetRiskManagement() public {
        // User 1 deposits into the vault
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Perform initial rebalance
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        // Check initial allocations
        uint256 sp500InitialValue = sp500Wrapper.getValueInBaseAsset();
        uint256 btcInitialValue = btcWrapper.getValueInBaseAsset();
        uint256 totalInitialValue = sp500InitialValue + btcInitialValue;
        
        uint256 sp500InitialPercent = (sp500InitialValue * BASIS_POINTS) / totalInitialValue;
        uint256 btcInitialPercent = (btcInitialValue * BASIS_POINTS) / totalInitialValue;
        
        console.log("Initial Allocations:");
        console.log("S&P 500:", sp500InitialPercent);
        console.log("BTC:", btcInitialPercent);
        
        // Simulate a market event by updating max position size for S&P 500
        vm.startPrank(owner);
        sp500Adapter.setMaxPositionSize(4000); // Reduce max position size to 40%
        vm.stopPrank();
        
        // Advance time to allow for rebalance
        vm.warp(block.timestamp + 1 days);
        
        // Trigger rebalance
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        // Check allocations after risk management rebalance
        uint256 sp500ValueAfterRebalance = sp500Wrapper.getValueInBaseAsset();
        uint256 btcValueAfterRebalance = btcWrapper.getValueInBaseAsset();
        uint256 totalValueAfterRebalance = sp500ValueAfterRebalance + btcValueAfterRebalance;
        
        uint256 sp500PercentAfterRebalance = (sp500ValueAfterRebalance * BASIS_POINTS) / totalValueAfterRebalance;
        uint256 btcPercentAfterRebalance = (btcValueAfterRebalance * BASIS_POINTS) / totalValueAfterRebalance;
        
        console.log("After Risk Management Rebalance:");
        console.log("S&P 500:", sp500PercentAfterRebalance);
        console.log("BTC:", btcPercentAfterRebalance);
        
        // Verify S&P 500 allocation doesn't exceed the new max position size
        assertLe(sp500PercentAfterRebalance, 4000, "S&P 500 allocation should not exceed max position size");
        
        // Test circuit breaker
        vm.startPrank(owner);
        sp500Wrapper.setCircuitBreaker(true);
        vm.stopPrank();
        
        // Advance time again
        vm.warp(block.timestamp + 1 days);
        
        // Trigger another rebalance
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        // Check values after circuit breaker rebalance
        uint256 sp500ValueAfterCircuitBreaker = sp500Wrapper.getValueInBaseAsset();
        
        console.log("After Circuit Breaker:");
        console.log("S&P 500 Value:", sp500ValueAfterCircuitBreaker);
        
        // Verify the S&P 500 value hasn't changed due to circuit breaker
        assertEq(sp500ValueAfterCircuitBreaker, sp500ValueAfterRebalance, "S&P 500 value should not change when circuit breaker is on");
    }
}
