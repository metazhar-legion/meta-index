// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakingReturnsStrategy} from "../src/StakingReturnsStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ILiquidStaking} from "../src/interfaces/ILiquidStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

// Simplified mock implementation of ILiquidStaking for specific tests
contract SimpleMockLiquidStaking is ILiquidStaking {
    MockERC20 public baseAsset;
    MockERC20 public stakingToken;
    uint256 public exchangeRate = 1e6; // 1:1 initially (in 6 decimals)
    uint256 public currentAPY = 450; // 4.5%
    
    constructor(address _baseAsset, address _stakingToken) {
        baseAsset = MockERC20(_baseAsset);
        stakingToken = MockERC20(_stakingToken);
    }
    
    function getTotalStaked() external view returns (uint256 totalStaked) {
        return stakingToken.totalSupply();
    }
    
    function stake(uint256 amount) external override returns (uint256) {
        // Transfer base asset from sender to this contract
        baseAsset.transferFrom(msg.sender, address(this), amount);
        
        // Calculate staking tokens to mint based on exchange rate
        uint256 stakingTokenAmount = (amount * 1e6) / exchangeRate;
        
        // Mint staking tokens to sender
        stakingToken.mint(msg.sender, stakingTokenAmount);
        
        return stakingTokenAmount;
    }
    
    function unstake(uint256 stakingTokenAmount) external override returns (uint256) {
        // Transfer staking tokens from sender to this contract
        stakingToken.transferFrom(msg.sender, address(this), stakingTokenAmount);
        
        // Calculate base asset amount based on exchange rate
        uint256 baseAssetAmount = (stakingTokenAmount * exchangeRate) / 1e6;
        
        // Transfer base asset to sender
        baseAsset.transfer(msg.sender, baseAssetAmount);
        
        return baseAssetAmount;
    }
    
    function getBaseAssetValue(uint256 stakingTokenAmount) external view override returns (uint256) {
        return (stakingTokenAmount * exchangeRate) / 1e6;
    }
    
    function getStakingTokensForBaseAsset(uint256 baseAssetAmount) external view override returns (uint256) {
        return (baseAssetAmount * 1e6) / exchangeRate;
    }
    
    function getCurrentAPY() external view override returns (uint256) {
        return currentAPY;
    }
    
    // Additional functions for testing
    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }
    
    function setAPY(uint256 _apy) external {
        currentAPY = _apy;
    }
}

contract StakingReturnsStrategySpecificTest is Test {
    // Constants
    uint256 constant DEPOSIT_AMOUNT = 100e9; // 100 USDC
    
    // Contracts
    MockERC20 usdc;
    MockERC20 stakingToken;
    SimpleMockLiquidStaking liquidStaking;
    StakingReturnsStrategy stakingStrategy;
    
    // Actors
    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address feeRecipient = address(0x4);
    
    function setUp() public {
        // Setup contracts
        vm.startPrank(owner);
        
        // Create tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        stakingToken = new MockERC20("Staking Token", "stUSDC", 6);
        
        // Create liquid staking protocol
        liquidStaking = new SimpleMockLiquidStaking(address(usdc), address(stakingToken));
        
        // Create strategy
        stakingStrategy = new StakingReturnsStrategy(
            "Staking Returns Strategy",
            address(usdc),
            address(stakingToken),
            address(liquidStaking),
            feeRecipient,
            450, // 4.5% initial APY
            3    // Risk level (1-10)
        );
        
        // Mint initial tokens to users
        usdc.mint(user1, DEPOSIT_AMOUNT * 10);
        usdc.mint(user2, DEPOSIT_AMOUNT * 10);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 100);
        
        vm.stopPrank();
    }
    
    // Test emergency withdrawal
    function test_EmergencyWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check initial state
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        
        // Ensure the staking protocol has enough tokens to return
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        // Make sure the staking tokens are properly minted to the strategy
        uint256 stakingTokensAmount = liquidStaking.getStakingTokensForBaseAsset(DEPOSIT_AMOUNT);
        
        // Approve staking tokens for the staking protocol
        vm.prank(address(stakingStrategy));
        stakingToken.approve(address(liquidStaking), stakingTokensAmount);
        
        // Perform emergency withdrawal
        vm.prank(owner);
        stakingStrategy.emergencyWithdraw();
        
        // Check final state - funds should be in the owner address
        uint256 finalOwnerBalance = usdc.balanceOf(owner);
        
        // The owner should have received the funds after emergency withdrawal
        assertEq(finalOwnerBalance - initialOwnerBalance, DEPOSIT_AMOUNT);
        
        // Check strategy state
        IYieldStrategy.StrategyInfo memory info = stakingStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, 0);
        assertEq(info.currentValue, 0);
        assertFalse(info.active);
    }
    
    // Test yield calculation with exchange rate changes
    function test_YieldCalculation_ExchangeRateChanges() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate yield by increasing exchange rate (10% increase)
        liquidStaking.setExchangeRate(1.1e6);
        
        // Calculate expected yield and fee
        uint256 expectedYield = DEPOSIT_AMOUNT * 10 / 100; // 10% of deposit
        uint256 expectedFee = expectedYield * 50 / 10000; // 0.5% fee
        uint256 expectedNetYield = expectedYield - expectedFee;
        
        // Make sure the staking tokens are properly minted to the strategy
        uint256 stakingTokensAmount = liquidStaking.getStakingTokensForBaseAsset(DEPOSIT_AMOUNT);
        
        // Ensure the liquid staking protocol has enough tokens to return
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), expectedYield);
        vm.stopPrank();
        
        // Approve staking tokens for the staking protocol
        vm.prank(address(stakingStrategy));
        stakingToken.approve(address(liquidStaking), stakingTokensAmount);
        
        // Capture the initial balances
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        
        // Harvest yield
        vm.prank(owner);
        uint256 harvestedYield = stakingStrategy.harvestYield();
        
        // Check harvested amount (net yield after fee)
        assertEq(harvestedYield, expectedNetYield);
        
        // Check fee recipient received fee
        assertEq(usdc.balanceOf(feeRecipient) - initialFeeRecipientBalance, expectedFee);
        
        // Check owner received net yield
        assertEq(usdc.balanceOf(owner) - initialOwnerBalance, expectedNetYield);
    }
}
