// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CapitalAllocationManager} from "../src/CapitalAllocationManager.sol";
import {ICapitalAllocationManager} from "../src/interfaces/ICapitalAllocationManager.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {IRWASyntheticToken} from "../src/interfaces/IRWASyntheticToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Mock yield strategy with reentrancy attack capabilities
contract MockYieldStrategyAdvanced is IYieldStrategy {
    IERC20 public baseAsset;
    uint256 public totalShares;
    uint256 public totalValue;
    uint256 public apy;
    bool public active = true;
    mapping(address => uint256) private _balances;
    
    // Reentrancy attack variables
    address public target;
    bool public attackOnDeposit;
    bool public attackOnWithdraw;
    bool public attackActive;
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
        apy = 500; // 5% APY by default
    }
    
    function setTarget(address _target) external {
        target = _target;
    }
    
    function setAttackMode(bool _onDeposit, bool _onWithdraw) external {
        attackOnDeposit = _onDeposit;
        attackOnWithdraw = _onWithdraw;
    }
    
    function activateAttack(bool _active) external {
        attackActive = _active;
    }
    
    function setAPY(uint256 _apy) external {
        apy = _apy;
    }
    
    function setActive(bool _active) external {
        active = _active;
    }
    
    function deposit(uint256 amount) external override returns (uint256 shares) {
        baseAsset.transferFrom(msg.sender, address(this), amount);
        shares = amount; // 1:1 for simplicity
        _balances[msg.sender] += shares;
        totalShares += shares;
        totalValue += amount;
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnDeposit && target != address(0)) {
            // Try to call rebalance on the manager
            CapitalAllocationManager(target).rebalance();
        }
        
        return shares;
    }
    
    function withdraw(uint256 shares) external override returns (uint256 amount) {
        require(_balances[msg.sender] >= shares, "Insufficient shares");
        amount = (shares * totalValue) / totalShares;
        _balances[msg.sender] -= shares;
        totalShares -= shares;
        totalValue -= amount;
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnWithdraw && target != address(0)) {
            // Try to call rebalance on the manager before transferring funds
            CapitalAllocationManager(target).rebalance();
        }
        
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueOfShares(uint256 shares) public view override returns (uint256 value) {
        if (totalShares == 0) return 0;
        return (shares * totalValue) / totalShares;
    }
    
    function getTotalValue() public view override returns (uint256 value) {
        return totalValue;
    }
    
    function getCurrentAPY() external view override returns (uint256) {
        return apy;
    }
    
    function getStrategyInfo() external view override returns (StrategyInfo memory info) {
        return StrategyInfo({
            name: "Mock Yield Strategy Advanced",
            asset: address(baseAsset),
            totalDeposited: totalValue,
            currentValue: totalValue,
            apy: apy,
            lastUpdated: block.timestamp,
            active: active,
            risk: 3
        });
    }
    
    function harvestYield() external override returns (uint256 harvested) {
        // Simulate yield harvesting
        uint256 yield = (totalValue * apy) / 10000; // APY is in basis points
        totalValue += yield;
        return yield;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}

// Mock RWA token with reentrancy attack capabilities
contract MockRWASyntheticTokenAdvanced is IRWASyntheticToken {
    IERC20 public baseAsset;
    uint256 public price = 1e18; // 1:1 initially
    bool public active = true;
    
    // Reentrancy attack variables
    address public target;
    bool public attackOnMint;
    bool public attackOnBurn;
    bool public attackActive;
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setTarget(address _target) external {
        target = _target;
    }
    
    function setAttackMode(bool _onMint, bool _onBurn) external {
        attackOnMint = _onMint;
        attackOnBurn = _onBurn;
    }
    
    function activateAttack(bool _active) external {
        attackActive = _active;
    }
    
    function setPrice(uint256 _price) external {
        price = _price;
    }
    
    function setActive(bool _active) external {
        active = _active;
    }
    
    function mint(address to, uint256 amount) external override returns (bool) {
        baseAsset.transferFrom(msg.sender, address(this), amount);
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnMint && target != address(0)) {
            // Try to call rebalance on the manager
            CapitalAllocationManager(target).rebalance();
        }
        
        return true;
    }
    
    function burn(address from, uint256 amount) external override returns (bool) {
        // Attempt reentrancy if configured
        if (attackActive && attackOnBurn && target != address(0)) {
            // Try to call rebalance on the manager before transferring funds
            CapitalAllocationManager(target).rebalance();
        }
        
        baseAsset.transfer(msg.sender, amount);
        return true;
    }
    
    function getCurrentPrice() external view override returns (uint256) {
        return price;
    }
    
    function getAssetInfo() external view override returns (AssetInfo memory info) {
        return AssetInfo({
            name: "Mock RWA Advanced",
            symbol: "MRWA",
            assetType: AssetType.OTHER,
            oracle: address(0),
            lastPrice: price,
            lastUpdated: block.timestamp,
            marketId: bytes32(0),
            isActive: active
        });
    }
    
    function updatePrice() external pure override returns (bool success) {
        // Mock implementation - price doesn't change
        return true;
    }
    
    // IERC20 implementation
    function totalSupply() external view override returns (uint256) {
        return 0;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return 0;
    }
    
    function transfer(address to, uint256 value) external override returns (bool) {
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return 0;
    }
    
    function approve(address spender, uint256 value) external override returns (bool) {
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        return true;
    }
}

contract CapitalAllocationManagerComprehensiveTest is Test {
    CapitalAllocationManager public manager;
    MockERC20 public baseAsset;
    MockYieldStrategyAdvanced public yieldStrategy1;
    MockYieldStrategyAdvanced public yieldStrategy2;
    MockRWASyntheticTokenAdvanced public rwaToken1;
    MockRWASyntheticTokenAdvanced public rwaToken2;
    
    address public owner;
    address public user;
    address public attacker;
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant ALLOCATION_AMOUNT = 100_000e6; // 100k USDC
    
    // Events
    event AllocationUpdated(uint256 rwaPercentage, uint256 yieldPercentage, uint256 liquidityBufferPercentage);
    event YieldStrategyAdded(address indexed strategy, uint256 percentage);
    event YieldStrategyUpdated(address indexed strategy, uint256 percentage);
    event YieldStrategyRemoved(address indexed strategy);
    event RWATokenAdded(address indexed rwaToken, uint256 percentage);
    event RWATokenUpdated(address indexed rwaToken, uint256 percentage);
    event RWATokenRemoved(address indexed rwaToken);
    event Rebalanced(uint256 timestamp);
    
    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        attacker = makeAddr("attacker");
        
        // Deploy mock tokens and contracts
        baseAsset = new MockERC20("USD Coin", "USDC", 6);
        yieldStrategy1 = new MockYieldStrategyAdvanced(address(baseAsset));
        yieldStrategy2 = new MockYieldStrategyAdvanced(address(baseAsset));
        rwaToken1 = new MockRWASyntheticTokenAdvanced(address(baseAsset));
        rwaToken2 = new MockRWASyntheticTokenAdvanced(address(baseAsset));
        
        // Deploy capital allocation manager
        manager = new CapitalAllocationManager(address(baseAsset));
        
        // Mint tokens
        baseAsset.mint(address(this), INITIAL_SUPPLY);
        baseAsset.mint(user, INITIAL_SUPPLY);
        baseAsset.mint(attacker, INITIAL_SUPPLY);
        
        // Approve tokens
        baseAsset.approve(address(manager), type(uint256).max);
        baseAsset.approve(address(yieldStrategy1), type(uint256).max);
        baseAsset.approve(address(yieldStrategy2), type(uint256).max);
        baseAsset.approve(address(rwaToken1), type(uint256).max);
        baseAsset.approve(address(rwaToken2), type(uint256).max);
        
        vm.startPrank(user);
        baseAsset.approve(address(manager), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(attacker);
        baseAsset.approve(address(manager), type(uint256).max);
        baseAsset.approve(address(yieldStrategy1), type(uint256).max);
        baseAsset.approve(address(rwaToken1), type(uint256).max);
        vm.stopPrank();
        
        // Configure attack targets
        yieldStrategy1.setTarget(address(manager));
        rwaToken1.setTarget(address(manager));
    }
    
    // Test allocate with no strategies or tokens
    function test_Allocate_NoStrategiesOrTokens() public {
        // Should not revert but do nothing
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // All funds should remain in the manager (in the liquidity buffer)
        assertEq(baseAsset.balanceOf(address(manager)), ALLOCATION_AMOUNT);
    }
    
    // Test allocate with only yield strategies
    function test_Allocate_OnlyYieldStrategies() public {
        // Set allocation to 100% yield
        manager.setAllocation(0, 10000, 0);
        
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Check that funds were allocated correctly
        assertEq(yieldStrategy1.getTotalValue(), ALLOCATION_AMOUNT * 60 / 100);
        assertEq(yieldStrategy2.getTotalValue(), ALLOCATION_AMOUNT * 40 / 100);
        assertEq(baseAsset.balanceOf(address(manager)), 0);
    }
    
    // Test allocate with only RWA tokens
    function test_Allocate_OnlyRWATokens() public {
        // Set allocation to 100% RWA
        manager.setAllocation(10000, 0, 0);
        
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Check that funds were allocated correctly
        assertEq(baseAsset.balanceOf(address(rwaToken1)), ALLOCATION_AMOUNT * 70 / 100);
        assertEq(baseAsset.balanceOf(address(rwaToken2)), ALLOCATION_AMOUNT * 30 / 100);
        assertEq(baseAsset.balanceOf(address(manager)), 0);
    }
    
    // Test allocate with mixed allocation
    function test_Allocate_MixedAllocation() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Check that funds were allocated correctly
        assertEq(yieldStrategy1.getTotalValue(), ALLOCATION_AMOUNT * 50 / 100);
        assertEq(baseAsset.balanceOf(address(rwaToken1)), ALLOCATION_AMOUNT * 40 / 100);
        assertEq(baseAsset.balanceOf(address(manager)), ALLOCATION_AMOUNT * 10 / 100);
    }
    
    // Test rebalance with price changes
    function test_Rebalance_PriceChanges() public {
        // Set allocation to 40% RWA, 60% yield
        manager.setAllocation(4000, 6000, 0);
        
        // Add yield strategies and RWA tokens
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Simulate price increase in RWA token (50% increase)
        rwaToken1.setPrice(1.5e18);
        
        // Rebalance
        manager.rebalance();
        
        // After rebalance, the allocation should be corrected
        // RWA value is now 40k * 1.5 = 60k, which is 46.15% of the total 130k
        // We need to withdraw from RWA to get back to 40%
        uint256 expectedRWAValue = ALLOCATION_AMOUNT * 40 / 100; // 40k
        uint256 expectedYieldValue = ALLOCATION_AMOUNT * 60 / 100; // 60k
        
        // Check that funds were reallocated correctly
        assertApproxEqRel(baseAsset.balanceOf(address(rwaToken1)), expectedRWAValue, 0.01e18);
        assertApproxEqRel(yieldStrategy1.getTotalValue(), expectedYieldValue, 0.01e18);
    }
    
    // Test reentrancy protection on rebalance
    function test_Rebalance_ReentrancyProtection() public {
        // Set allocation to 50% RWA, 50% yield
        manager.setAllocation(5000, 5000, 0);
        
        // Add yield strategy and RWA token
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Configure for reentrancy attack
        yieldStrategy1.setAttackMode(true, false); // Attack on deposit
        yieldStrategy1.activateAttack(true);
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Try to rebalance (should not be vulnerable to reentrancy)
        manager.rebalance();
        
        // Verify that the rebalance completed successfully despite attack attempt
        assertEq(yieldStrategy1.getTotalValue(), ALLOCATION_AMOUNT * 50 / 100);
        assertEq(baseAsset.balanceOf(address(rwaToken1)), ALLOCATION_AMOUNT * 50 / 100);
    }
    
    // Test getTotalValue calculation
    function test_GetTotalValue() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Add yield strategies and RWA tokens
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Initial total value should match allocation amount
        assertEq(manager.getTotalValue(), ALLOCATION_AMOUNT);
        
        // Simulate yield in the strategy (10% increase)
        yieldStrategy1.harvestYield();
        
        // Simulate price increase in RWA token (20% increase)
        rwaToken1.setPrice(1.2e18);
        
        // Calculate expected total value
        uint256 yieldValue = ALLOCATION_AMOUNT * 50 / 100 * 110 / 100; // 50k with 10% yield
        uint256 rwaValue = ALLOCATION_AMOUNT * 40 / 100 * 120 / 100; // 40k with 20% price increase
        uint256 liquidityBuffer = ALLOCATION_AMOUNT * 10 / 100; // 10k
        uint256 expectedTotalValue = yieldValue + rwaValue + liquidityBuffer;
        
        // Check total value calculation
        assertApproxEqRel(manager.getTotalValue(), expectedTotalValue, 0.01e18);
    }
    
    // Test getRWAValue calculation
    function test_GetRWAValue() public {
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Set allocation to 100% RWA
        manager.setAllocation(10000, 0, 0);
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Initial RWA value should match allocation amount
        assertEq(manager.getRWAValue(), ALLOCATION_AMOUNT);
        
        // Simulate price changes
        rwaToken1.setPrice(1.2e18); // 20% increase
        rwaToken2.setPrice(0.9e18); // 10% decrease
        
        // Calculate expected RWA value
        uint256 rwa1Value = ALLOCATION_AMOUNT * 70 / 100 * 120 / 100; // 70k with 20% increase
        uint256 rwa2Value = ALLOCATION_AMOUNT * 30 / 100 * 90 / 100; // 30k with 10% decrease
        uint256 expectedRWAValue = rwa1Value + rwa2Value;
        
        // Check RWA value calculation
        assertApproxEqRel(manager.getRWAValue(), expectedRWAValue, 0.01e18);
    }
    
    // Test getYieldValue calculation
    function test_GetYieldValue() public {
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Set allocation to 100% yield
        manager.setAllocation(0, 10000, 0);
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Initial yield value should match allocation amount
        assertEq(manager.getYieldValue(), ALLOCATION_AMOUNT);
        
        // Simulate yield in strategies
        yieldStrategy1.harvestYield(); // 5% yield (default)
        yieldStrategy2.setAPY(1000); // 10% APY
        yieldStrategy2.harvestYield();
        
        // Calculate expected yield value
        uint256 yield1Value = ALLOCATION_AMOUNT * 60 / 100 * 105 / 100; // 60k with 5% yield
        uint256 yield2Value = ALLOCATION_AMOUNT * 40 / 100 * 110 / 100; // 40k with 10% yield
        uint256 expectedYieldValue = yield1Value + yield2Value;
        
        // Check yield value calculation
        assertApproxEqRel(manager.getYieldValue(), expectedYieldValue, 0.01e18);
    }
    
    // Test handling inactive strategies and tokens
    function test_InactiveStrategiesAndTokens() public {
        // Set allocation to 50% RWA, 50% yield
        manager.setAllocation(5000, 5000, 0);
        
        // Add yield strategies and RWA tokens
        manager.addYieldStrategy(address(yieldStrategy1), 5000); // 50%
        manager.addYieldStrategy(address(yieldStrategy2), 5000); // 50%
        manager.addRWAToken(address(rwaToken1), 5000); // 50%
        manager.addRWAToken(address(rwaToken2), 5000); // 50%
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Mark one strategy and one token as inactive
        yieldStrategy2.setActive(false);
        rwaToken2.setActive(false);
        
        // Rebalance
        manager.rebalance();
        
        // Check that inactive components were not included in allocation
        assertEq(yieldStrategy1.getTotalValue(), ALLOCATION_AMOUNT * 50 / 100);
        assertEq(baseAsset.balanceOf(address(rwaToken1)), ALLOCATION_AMOUNT * 50 / 100);
        assertEq(yieldStrategy2.getTotalValue(), 0);
        assertEq(baseAsset.balanceOf(address(rwaToken2)), 0);
    }
    
    // Test removing yield strategy
    function test_RemoveYieldStrategy() public {
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Set allocation to 100% yield
        manager.setAllocation(0, 10000, 0);
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Remove one strategy
        manager.removeYieldStrategy(address(yieldStrategy1));
        
        // Check that the strategy was removed
        ICapitalAllocationManager.StrategyAllocation[] memory strategies = manager.getYieldStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0].strategy, address(yieldStrategy2));
        assertEq(strategies[0].percentage, 4000);
        
        // Rebalance
        manager.rebalance();
        
        // Check that funds were withdrawn from the removed strategy
        assertEq(yieldStrategy1.getTotalValue(), 0);
        assertEq(yieldStrategy2.getTotalValue(), ALLOCATION_AMOUNT);
    }
    
    // Test removing RWA token
    function test_RemoveRWAToken() public {
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Set allocation to 100% RWA
        manager.setAllocation(10000, 0, 0);
        
        // Allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        // Remove one token
        manager.removeRWAToken(address(rwaToken1));
        
        // Check that the token was removed
        ICapitalAllocationManager.RWAAllocation[] memory tokens = manager.getRWATokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0].rwaToken, address(rwaToken2));
        assertEq(tokens[0].percentage, 3000);
        
        // Rebalance
        manager.rebalance();
        
        // Check that funds were withdrawn from the removed token
        assertEq(baseAsset.balanceOf(address(rwaToken1)), 0);
        assertEq(baseAsset.balanceOf(address(rwaToken2)), ALLOCATION_AMOUNT);
    }
    
    // Test non-owner access restrictions
    function test_NonOwnerAccessRestrictions() public {
        vm.startPrank(user);
        
        // All owner-only functions should revert
        vm.expectRevert();
        manager.setAllocation(3000, 6000, 1000);
        
        vm.expectRevert();
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        
        vm.expectRevert();
        manager.updateYieldStrategy(address(yieldStrategy1), 5000);
        
        vm.expectRevert();
        manager.removeYieldStrategy(address(yieldStrategy1));
        
        vm.expectRevert();
        manager.addRWAToken(address(rwaToken1), 10000);
        
        vm.expectRevert();
        manager.updateRWAToken(address(rwaToken1), 5000);
        
        vm.expectRevert();
        manager.removeRWAToken(address(rwaToken1));
        
        // Non-owner cannot allocate funds
        baseAsset.transfer(address(manager), ALLOCATION_AMOUNT);
        
        vm.expectRevert();
        manager.rebalance();
        
        vm.stopPrank();
    }
}
