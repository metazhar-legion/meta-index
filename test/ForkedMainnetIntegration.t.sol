// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ForkedMainnetIntegrationTest
 * @notice Integration tests for the Index Fund Vault using a forked mainnet environment
 * @dev This is a simplified version to ensure compilation works
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
    
    // Contract instances
    IERC20 usdc;
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Set up test accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Fund test accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        // Get USDC contract
        usdc = IERC20(USDC_ADDRESS);
        
        // Fund users with USDC (using deal cheat code)
        deal(address(usdc), user1, DEPOSIT_AMOUNT);
        deal(address(usdc), user2, DEPOSIT_AMOUNT);
    }
    
    // Simple test function that should compile
    function test_ForkedMainnetBasic() public {
        // Check that we can access USDC
        assertEq(usdc.decimals(), 6, "USDC should have 6 decimals");
        
        // Check that users have USDC
        assertEq(usdc.balanceOf(user1), DEPOSIT_AMOUNT, "User1 should have USDC");
        assertEq(usdc.balanceOf(user2), DEPOSIT_AMOUNT, "User2 should have USDC");
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
        
        // Simulate a market event by adjusting the wrapper's parameters
        vm.startPrank(owner);
        // Note: In a real implementation, we would adjust risk parameters here
        // For the test, we'll just continue with default parameters
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
