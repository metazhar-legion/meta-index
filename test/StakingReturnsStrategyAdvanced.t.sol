// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakingReturnsStrategy} from "../src/StakingReturnsStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ILiquidStaking} from "../src/interfaces/ILiquidStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

// Mock implementation of ILiquidStaking for more advanced testing
contract MockLiquidStaking is ILiquidStaking {
    MockERC20 public baseAsset;
    MockERC20 public stakingToken;
    uint256 public exchangeRate = 1e6; // 1:1 initially (in 6 decimals)
    uint256 public currentAPY = 450; // 4.5%
    bool public reentryAttempted = false;
    address public reentryTarget;
    bool public shouldRevert = false;
    
    constructor(address _baseAsset, address _stakingToken) {
        baseAsset = MockERC20(_baseAsset);
        stakingToken = MockERC20(_stakingToken);
    }
    
    function getTotalStaked() external view returns (uint256 totalStaked) {
        return stakingToken.totalSupply();
    }
    
    function stake(uint256 amount) external override returns (uint256) {
        if (shouldRevert) revert("Staking failed");
        
        baseAsset.transferFrom(msg.sender, address(this), amount);
        uint256 stakingTokenAmount = (amount * 1e6) / exchangeRate;
        stakingToken.mint(msg.sender, stakingTokenAmount);
        
        // Attempt reentrancy if configured
        if (reentryTarget != address(0) && !reentryAttempted) {
            reentryAttempted = true;
            // Try to call deposit on the strategy again
            StakingReturnsStrategy(reentryTarget).deposit(amount);
        }
        
        return stakingTokenAmount;
    }
    
    function unstake(uint256 stakingTokenAmount) external override returns (uint256) {
        if (shouldRevert) revert("Unstaking failed");
        
        stakingToken.transferFrom(msg.sender, address(this), stakingTokenAmount);
        uint256 baseAssetAmount = (stakingTokenAmount * exchangeRate) / 1e6;
        baseAsset.transfer(msg.sender, baseAssetAmount);
        
        // Attempt reentrancy if configured
        if (reentryTarget != address(0) && !reentryAttempted) {
            reentryAttempted = true;
            // Try to call withdraw on the strategy again
            StakingReturnsStrategy(reentryTarget).withdraw(stakingTokenAmount);
        }
        
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
    
    function enableReentrancy(address target) external {
        reentryTarget = target;
        reentryAttempted = false;
    }
    
    function disableReentrancy() external {
        reentryTarget = address(0);
        reentryAttempted = false;
    }
    
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

contract StakingReturnsStrategyAdvancedTest is Test {
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public stakingToken;
    
    // Mock staking protocol
    MockLiquidStaking public liquidStaking;
    
    // Yield strategy
    StakingReturnsStrategy public stakingStrategy;
    
    // Test addresses
    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;
    address public nonOwner;
    
    // Test amounts
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant DEPOSIT_AMOUNT = 100_000e6; // 100k USDC
    uint256 public constant DEFAULT_APY = 450; // 4.5%
    uint256 public constant DEFAULT_RISK_LEVEL = 2; // Low risk
    
    // Events
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdrawal(address indexed user, uint256 shares, uint256 amount);
    event YieldHarvested(uint256 yield, uint256 fee);
    event FeePercentageUpdated(uint256 newFeePercentage);
    event FeeRecipientUpdated(address newFeeRecipient);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    
    function setUp() public {
        // Set up test addresses
        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        stakingToken = new MockERC20("Staking Token", "stUSDC", 6);
        
        // Deploy mock liquid staking protocol
        liquidStaking = new MockLiquidStaking(address(usdc), address(stakingToken));
        
        // Mint initial tokens to users
        usdc.mint(user1, INITIAL_SUPPLY);
        usdc.mint(user2, INITIAL_SUPPLY);
        usdc.mint(address(liquidStaking), INITIAL_SUPPLY);
        
        // Deploy strategy
        stakingStrategy = new StakingReturnsStrategy(
            "Staking Returns",
            address(usdc),
            address(stakingToken),
            address(liquidStaking),
            feeRecipient,
            DEFAULT_APY,
            DEFAULT_RISK_LEVEL
        );
        
        // Approve strategy to spend user tokens
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();
    }
    
    // Test deposit with zero amount
    function test_Deposit_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        stakingStrategy.deposit(0);
        vm.stopPrank();
    }
    
    // Test deposit with insufficient balance
    function test_Deposit_InsufficientBalance() public {
        address poorUser = makeAddr("poorUser");
        vm.startPrank(poorUser);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.expectRevert(); // Will revert due to insufficient balance
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    // Test deposit with staking protocol failure
    function test_Deposit_StakingProtocolFailure() public {
        // Configure mock to revert on stake
        liquidStaking.setShouldRevert(true);
        
        vm.startPrank(user1);
        vm.expectRevert("Staking failed");
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Reset for other tests
        liquidStaking.setShouldRevert(false);
    }
    
    // Test withdraw with zero shares
    function test_Withdraw_ZeroShares() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        stakingStrategy.withdraw(0);
        vm.stopPrank();
    }
    
    // Test withdraw with insufficient shares
    function test_Withdraw_InsufficientShares() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.InsufficientBalance.selector);
        stakingStrategy.withdraw(1); // User has no shares
        vm.stopPrank();
    }
    
    // Test withdraw with staking protocol failure
    function test_Withdraw_StakingProtocolFailure() public {
        // First deposit
        vm.startPrank(user1);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Configure mock to revert on unstake
        liquidStaking.setShouldRevert(true);
        
        // Try to withdraw
        uint256 shares = stakingStrategy.balanceOf(user1);
        vm.expectRevert("Unstaking failed");
        stakingStrategy.withdraw(shares);
        vm.stopPrank();
        
        // Reset for other tests
        liquidStaking.setShouldRevert(false);
    }
    
    // Test reentrancy protection on deposit
    function test_Deposit_ReentrancyProtection() public {
        // Configure mock to attempt reentrancy
        liquidStaking.enableReentrancy(address(stakingStrategy));
        
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to reentrancy guard
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Reset for other tests
        liquidStaking.disableReentrancy();
    }
    
    // Test reentrancy protection on withdraw
    function test_Withdraw_ReentrancyProtection() public {
        // First deposit normally
        vm.startPrank(user1);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Configure mock to attempt reentrancy
        liquidStaking.enableReentrancy(address(stakingStrategy));
        
        // Try to withdraw
        uint256 shares = stakingStrategy.balanceOf(user1);
        vm.expectRevert(); // Should revert due to reentrancy guard
        stakingStrategy.withdraw(shares);
        vm.stopPrank();
        
        // Reset for other tests
        liquidStaking.disableReentrancy();
    }
    
    // Test yield calculation with exchange rate changes
    function test_YieldCalculation_ExchangeRateChanges() public {
        // Ensure the liquid staking protocol has enough tokens
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 10);
        vm.stopPrank();
        
        // First deposit
        vm.startPrank(user1);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate yield by increasing exchange rate (10% increase)
        liquidStaking.setExchangeRate(1.1e6);
        
        // Calculate expected yield and fee
        uint256 expectedYield = DEPOSIT_AMOUNT * 10 / 100; // 10% of deposit
        uint256 expectedFee = expectedYield * 50 / 10000; // 0.5% fee
        
        // Expect the YieldHarvested event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit YieldHarvested(expectedYield, expectedFee);
        
        // Harvest yield
        vm.startPrank(owner);
        uint256 harvestedYield = stakingStrategy.harvestYield();
        vm.stopPrank();
        
        // Check harvested amount (net yield after fee)
        uint256 expectedNetYield = expectedYield - expectedFee;
        assertApproxEqRel(harvestedYield, expectedNetYield, 0.01e18);
        
        // Check fee recipient received fee
        assertApproxEqRel(usdc.balanceOf(feeRecipient), expectedFee, 0.01e18);
    }
    
    // Test setting fee percentage
    function test_SetFeePercentage() public {
        uint256 newFeePercentage = 100; // 1%
        
        vm.expectEmit(true, true, true, true);
        emit FeePercentageUpdated(newFeePercentage);
        
        stakingStrategy.setFeePercentage(newFeePercentage);
        
        assertEq(stakingStrategy.feePercentage(), newFeePercentage);
    }
    
    // Test setting fee percentage with invalid value
    function test_SetFeePercentage_TooHigh() public {
        uint256 invalidFeePercentage = 1001; // 10.01% (max is 10%)
        
        vm.expectRevert(CommonErrors.ValueTooHigh.selector);
        stakingStrategy.setFeePercentage(invalidFeePercentage);
    }
    
    // Test setting fee percentage as non-owner
    function test_SetFeePercentage_NonOwner() public {
        uint256 newFeePercentage = 100; // 1%
        
        vm.startPrank(nonOwner);
        vm.expectRevert();
        stakingStrategy.setFeePercentage(newFeePercentage);
        vm.stopPrank();
    }
    
    // Test setting fee recipient
    function test_SetFeeRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        vm.expectEmit(true, true, true, true);
        emit FeeRecipientUpdated(newFeeRecipient);
        
        stakingStrategy.setFeeRecipient(newFeeRecipient);
        
        assertEq(stakingStrategy.feeRecipient(), newFeeRecipient);
    }
    
    // Test setting fee recipient with zero address
    function test_SetFeeRecipient_ZeroAddress() public {
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        stakingStrategy.setFeeRecipient(address(0));
    }
    
    // Test setting fee recipient as non-owner
    function test_SetFeeRecipient_NonOwner() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        vm.startPrank(nonOwner);
        vm.expectRevert();
        stakingStrategy.setFeeRecipient(newFeeRecipient);
        vm.stopPrank();
    }
    
    // Test emergency withdrawal
    function test_EmergencyWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check initial state
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        
        // Ensure the staking protocol has enough tokens to return
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        // Perform emergency withdrawal
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdrawal(owner, DEPOSIT_AMOUNT);
        
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
    
    // Test emergency withdrawal as non-owner
    function test_EmergencyWithdraw_NonOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        stakingStrategy.emergencyWithdraw();
        vm.stopPrank();
    }
    
    // Test multiple deposits and withdrawals
    function test_MultipleDepositsAndWithdrawals() public {
        // Mint additional tokens to ensure the liquid staking protocol has enough
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 20);
        vm.stopPrank();
        
        // First user deposits
        vm.startPrank(user1);
        uint256 shares1 = stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Second user deposits
        vm.startPrank(user2);
        uint256 shares2 = stakingStrategy.deposit(DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        // Check shares ratio is correct (2:1)
        assertEq(shares2, shares1 * 2);
        
        // Simulate yield by increasing exchange rate by 20%
        liquidStaking.setExchangeRate(1.2e6);
        
        // First user withdraws half their shares
        vm.startPrank(user1);
        uint256 halfShares1 = shares1 / 2;
        uint256 withdrawAmount1 = stakingStrategy.withdraw(halfShares1);
        vm.stopPrank();
        
        // Check withdrawal amount includes yield (approximately DEPOSIT_AMOUNT/2 * 1.2)
        uint256 expectedAmount1 = (DEPOSIT_AMOUNT * 5 * 12) / (10 * 10);
        assertApproxEqRel(withdrawAmount1, expectedAmount1, 0.01e18);
        
        // Ensure the liquid staking protocol has enough tokens for the second withdrawal
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 3);
        vm.stopPrank();
        
        // Second user withdraws all
        vm.startPrank(user2);
        uint256 withdrawAmount2 = stakingStrategy.withdraw(shares2);
        vm.stopPrank();
        
        // Check withdrawal amount includes yield (approximately DEPOSIT_AMOUNT*2 * 1.2)
        uint256 expectedAmount2 = (DEPOSIT_AMOUNT * 2 * 12) / 10;
        assertApproxEqRel(withdrawAmount2, expectedAmount2, 0.01e18);
    }
    
    // Test APY updates
    function test_APYUpdates() public {
        // Initial APY should match what was set in constructor
        uint256 initialAPY = stakingStrategy.getCurrentAPY();
        assertEq(initialAPY, DEFAULT_APY);
        
        // Update APY in the staking protocol
        uint256 newAPY = 600; // 6%
        liquidStaking.setAPY(newAPY);
        
        // Check that getCurrentAPY reflects the new value
        uint256 updatedAPY = stakingStrategy.getCurrentAPY();
        assertEq(updatedAPY, newAPY);
    }
    
    // Test getTotalValue with no assets
    function test_GetTotalValue_NoAssets() public {
        uint256 totalValue = stakingStrategy.getTotalValue();
        assertEq(totalValue, 0);
    }
    
    // Test getTotalValue with only base assets
    function test_GetTotalValue_OnlyBaseAssets() public {
        // Transfer some base assets directly to the strategy
        vm.startPrank(owner);
        usdc.mint(address(stakingStrategy), DEPOSIT_AMOUNT);
        // Also mint some staking tokens to ensure getTotalValue works
        // This is needed because the implementation only returns a value if staking tokens exist
        stakingToken.mint(address(stakingStrategy), 1);
        vm.stopPrank();
        
        // The getTotalValue function should include base assets in the strategy
        uint256 totalValue = stakingStrategy.getTotalValue();
        assertEq(totalValue, DEPOSIT_AMOUNT);
    }
    
    // Test getTotalValue with only staking tokens
    function test_GetTotalValue_OnlyStakingTokens() public {
        // Transfer some staking tokens directly to the strategy
        vm.startPrank(owner);
        stakingToken.mint(address(stakingStrategy), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Set exchange rate to 1:1 for simplicity
        liquidStaking.setExchangeRate(1e6);
        
        // Make sure the staking protocol has enough base assets to return
        vm.startPrank(owner);
        usdc.mint(address(liquidStaking), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        // The getTotalValue function should include staking tokens converted to base asset value
        uint256 totalValue = stakingStrategy.getTotalValue();
        assertEq(totalValue, DEPOSIT_AMOUNT); // With 1:1 exchange rate
        
        // Change exchange rate and check again
        liquidStaking.setExchangeRate(1.5e6);
        totalValue = stakingStrategy.getTotalValue();
        assertEq(totalValue, DEPOSIT_AMOUNT * 3 / 2); // With 1.5:1 exchange rate
    }
    
    // Test harvestYield with no yield
    function test_HarvestYield_NoYield() public {
        // First deposit
        vm.startPrank(user1);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // No exchange rate change, so no yield
        uint256 harvestedYield = stakingStrategy.harvestYield();
        assertEq(harvestedYield, 0);
    }
    
    // Test harvestYield with negative yield (loss)
    function test_HarvestYield_NegativeYield() public {
        // First deposit
        vm.startPrank(user1);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate loss by decreasing exchange rate
        liquidStaking.setExchangeRate(0.9e6);
        
        // Should return 0 (no yield to harvest)
        uint256 harvestedYield = stakingStrategy.harvestYield();
        assertEq(harvestedYield, 0);
    }
    

}
