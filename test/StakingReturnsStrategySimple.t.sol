// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakingReturnsStrategy} from "../src/StakingReturnsStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ILiquidStaking} from "../src/interfaces/ILiquidStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

// Mock implementation of ILiquidStaking
contract MockLiquidStaking is ILiquidStaking {
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
        baseAsset.transferFrom(msg.sender, address(this), amount);
        uint256 stakingTokenAmount = (amount * 1e6) / exchangeRate;
        stakingToken.mint(msg.sender, stakingTokenAmount);
        return stakingTokenAmount;
    }
    
    function unstake(uint256 stakingTokenAmount) external override returns (uint256) {
        stakingToken.transferFrom(msg.sender, address(this), stakingTokenAmount);
        uint256 baseAssetAmount = (stakingTokenAmount * exchangeRate) / 1e6;
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
    
    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }
    
    function setAPY(uint256 _apy) external {
        currentAPY = _apy;
    }
}

contract StakingReturnsStrategySimpleTest is Test {
    // Constants
    uint256 constant DEPOSIT_AMOUNT = 100e9; // 100 USDC
    
    // Contracts
    MockERC20 usdc;
    MockERC20 stakingToken;
    MockLiquidStaking liquidStaking;
    StakingReturnsStrategy stakingStrategy;
    
    // Actors
    address owner = address(0x1);
    address user1 = address(0x2);
    address feeRecipient = address(0x4);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Create tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        stakingToken = new MockERC20("Staking Token", "stUSDC", 6);
        
        // Create liquid staking protocol
        liquidStaking = new MockLiquidStaking(address(usdc), address(stakingToken));
        
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
        
        // Mint initial tokens
        usdc.mint(user1, DEPOSIT_AMOUNT * 10);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 100);
        
        vm.stopPrank();
    }
    
    // Test emergency withdrawal
    function testEmergencyWithdraw() public {
        // First deposit from user1
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Record initial balances
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        
        // Make sure the liquid staking protocol has enough base assets to return
        vm.prank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT);
        
        // Approve staking tokens for unstaking
        uint256 stakingTokenBalance = stakingToken.balanceOf(address(stakingStrategy));
        vm.prank(address(stakingStrategy));
        stakingToken.approve(address(liquidStaking), stakingTokenBalance);
        
        // Perform emergency withdrawal
        vm.prank(owner);
        stakingStrategy.emergencyWithdraw();
        
        // Check strategy state
        IYieldStrategy.StrategyInfo memory info = stakingStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, 0, "Total deposited should be 0");
        assertEq(info.currentValue, 0, "Current value should be 0");
        assertFalse(info.active, "Strategy should be inactive");
        
        // Check that the owner received funds
        uint256 finalOwnerBalance = usdc.balanceOf(owner);
        assertGt(finalOwnerBalance, initialOwnerBalance, "Owner should have received funds");
    }
    
    // Test yield calculation with exchange rate changes
    function testYieldCalculation() public {
        // First deposit from user1
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate yield by increasing exchange rate (10% increase)
        liquidStaking.setExchangeRate(1.1e6);
        
        // Make sure the liquid staking protocol has enough base assets to return
        uint256 expectedYield = DEPOSIT_AMOUNT * 10 / 100; // 10% of deposit
        vm.prank(owner);
        usdc.mint(address(liquidStaking), expectedYield);
        
        // Approve staking tokens for unstaking
        uint256 stakingTokenBalance = stakingToken.balanceOf(address(stakingStrategy));
        vm.prank(address(stakingStrategy));
        stakingToken.approve(address(liquidStaking), stakingTokenBalance);
        
        // Record initial balances
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        
        // Harvest yield
        vm.prank(owner);
        stakingStrategy.harvestYield();
        
        // Check that the fee recipient received a fee
        uint256 finalFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        assertGt(finalFeeRecipientBalance, initialFeeRecipientBalance, "Fee recipient should have received a fee");
        
        // Check that the owner received the net yield
        uint256 finalOwnerBalance = usdc.balanceOf(owner);
        assertGt(finalOwnerBalance, initialOwnerBalance, "Owner should have received net yield");
    }
}
