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
import {CommonErrors} from "../src/errors/CommonErrors.sol";

/**
 * @title MockYieldStrategyAdvanced
 * @dev Mock implementation of IYieldStrategy with reentrancy attack capabilities
 */
contract MockYieldStrategyAdvanced is IYieldStrategy {
    IERC20 public baseAsset;
    uint256 public totalShares;
    uint256 public totalValue;
    uint256 public apy;
    bool public active = true;
    uint256 public risk = 3;
    string public name = "Mock Yield Strategy";
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
    
    function setRisk(uint256 _risk) external {
        risk = _risk;
    }
    
    function setName(string memory tokenName) external {
        name = tokenName;
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
            name: name,
            asset: address(baseAsset),
            totalDeposited: totalValue,
            currentValue: totalValue,
            apy: apy,
            lastUpdated: block.timestamp,
            active: active,
            risk: risk
        });
    }
    
    function harvestYield() external pure override returns (uint256 harvested) {
        // Mock implementation - no yield harvesting
        return 0;
    }
}

/**
 * @title MockRWASyntheticTokenAdvanced
 * @dev Mock implementation of IRWASyntheticToken with advanced features
 */
contract MockRWASyntheticTokenAdvanced is IRWASyntheticToken {
    IERC20 public baseAsset;
    uint256 public price = 1e18; // 1:1 initially
    bool public active = true;
    string private _tokenName = "Mock RWA Token";
    string private _tokenSymbol = "MRWA";
    uint256 private _tokenTotalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Asset info
    AssetType public assetType = AssetType.EQUITY_INDEX;
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setPrice(uint256 _price) external {
        price = _price;
    }
    
    function setActive(bool _active) external {
        active = _active;
    }
    
    function setName(string memory tokenName) external {
        name = tokenName;
    }
    
    function mint(address to, uint256 amount) external returns (bool) {
        // Calculate how much base asset is needed
        uint256 baseAmount = (amount * 1e18) / price;
        
        // Transfer base asset from sender to this contract
        baseAsset.transferFrom(msg.sender, address(this), baseAmount);
        
        // Mint RWA tokens to recipient
        _balances[to] += amount;
        _tokenTotalSupply += amount;
        
        return true;
    }
    
    // Implement the burn function from the interface
    function burn(address from, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        
        // Calculate how much base asset to return
        uint256 baseAmount = (amount * price) / 1e18;
        
        // Burn RWA tokens
        _balances[from] -= amount;
        _tokenTotalSupply -= amount;
        
        // Transfer base asset back to sender
        baseAsset.transfer(msg.sender, baseAmount);
        
        return true;
    }
    
    function getCurrentPrice() external view override returns (uint256) {
        return price;
    }
    
    function getAssetInfo() external view override returns (AssetInfo memory info) {
        return AssetInfo({
            name: _tokenName,
            symbol: _tokenSymbol,
            assetType: assetType,
            oracle: address(0),
            lastPrice: price,
            lastUpdated: block.timestamp,
            marketId: bytes32(0),
            isActive: active
        });
    }
    
    // Implement updatePrice function from the interface
    function updatePrice() external returns (bool) {
        // Mock implementation - does nothing
        return true;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function decimals() external pure override returns (uint8) {
        return 18;
    }
    
    function name() external view override returns (string memory) {
        return _tokenName;
    }
    
    function symbol() external view override returns (string memory) {
        return _tokenSymbol;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _tokenTotalSupply;
    }
}

/**
 * @title CapitalAllocationManagerConsolidatedTest
 * @dev Comprehensive test suite for CapitalAllocationManager
 */
contract CapitalAllocationManagerConsolidatedTest is Test {
    // Contracts
    CapitalAllocationManager public manager;
    MockERC20 public baseAsset;
    MockYieldStrategyAdvanced public yieldStrategy1;
    MockYieldStrategyAdvanced public yieldStrategy2;
    MockRWASyntheticTokenAdvanced public rwaToken1;
    MockRWASyntheticTokenAdvanced public rwaToken2;
    
    // Users
    address public owner;
    address public user1;
    address public user2;
    address public attacker;
    
    // Constants
    uint256 public constant INITIAL_CAPITAL = 1000000 * 1e6; // 1M USDC
    uint256 public constant ALLOCATION_AMOUNT = 100000 * 1e6; // 100K USDC
    
    // Events
    event YieldStrategyAdded(address indexed strategyAddress, uint256 weight);
    event YieldStrategyRemoved(address indexed strategyAddress);
    event YieldStrategyWeightUpdated(address indexed strategyAddress, uint256 oldWeight, uint256 newWeight);
    event RWATokenAdded(address indexed tokenAddress, uint256 weight);
    event RWATokenRemoved(address indexed tokenAddress);
    event RWATokenWeightUpdated(address indexed tokenAddress, uint256 oldWeight, uint256 newWeight);
    event AllocationUpdated(uint256 rwaAllocation, uint256 yieldAllocation, uint256 liquidityBuffer);
    event Rebalanced();
    
    function setUp() public {
        owner = address(this); // Test contract is the owner
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");
        
        // Deploy mock contracts
        baseAsset = new MockERC20("Mock USDC", "USDC", 6);
        
        // Deploy yield strategies
        yieldStrategy1 = new MockYieldStrategyAdvanced(address(baseAsset));
        yieldStrategy2 = new MockYieldStrategyAdvanced(address(baseAsset));
        yieldStrategy1.setName("Yield Strategy 1");
        yieldStrategy2.setName("Yield Strategy 2");
        
        // Deploy RWA tokens
        rwaToken1 = new MockRWASyntheticTokenAdvanced(address(baseAsset));
        rwaToken2 = new MockRWASyntheticTokenAdvanced(address(baseAsset));
        rwaToken1.setName("RWA Token 1");
        rwaToken2.setName("RWA Token 2");
        
        // Deploy capital allocation manager
        manager = new CapitalAllocationManager(address(baseAsset));
        
        // Mint base asset to this contract for allocation
        baseAsset.mint(address(this), INITIAL_CAPITAL);
        
        // Approve base asset for the manager
        baseAsset.approve(address(manager), type(uint256).max);
        
        // Approve base asset for the yield strategies
        baseAsset.approve(address(yieldStrategy1), type(uint256).max);
        baseAsset.approve(address(yieldStrategy2), type(uint256).max);
        
        // Approve base asset for the RWA tokens
        baseAsset.approve(address(rwaToken1), type(uint256).max);
        baseAsset.approve(address(rwaToken2), type(uint256).max);
        
        // Set up reentrancy attack targets
        yieldStrategy1.setTarget(address(manager));
        yieldStrategy2.setTarget(address(manager));
    }
    
    // Test initialization
    function test_Initialization() public view {
        assertEq(address(manager.baseAsset()), address(baseAsset));
        assertEq(manager.owner(), address(this));
        
        // Get allocation info
        ICapitalAllocationManager.Allocation memory alloc = manager.allocation();
        assertEq(alloc.rwaPercentage, 3000); // Default 30%
        assertEq(alloc.yieldPercentage, 6000); // Default 60%
        assertEq(alloc.liquidityBufferPercentage, 1000); // Default 10%
    }
    
    // Test adding a yield strategy
    function test_AddYieldStrategy() public {
        // Add a yield strategy
        vm.expectEmit(true, true, true, true);
        emit YieldStrategyAdded(address(yieldStrategy1), 10000);
        
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        
        // Check strategy was added correctly
        (address strategy, uint256 weight, bool active) = manager.getYieldStrategyInfo(address(yieldStrategy1));
        assertEq(strategy, address(yieldStrategy1));
        assertEq(weight, 10000);
        assertTrue(active);
        
        // Check total weight
        assertEq(manager.getTotalYieldWeight(), 10000);
    }
    
    // Test adding an RWA token
    function test_AddRWAToken() public {
        // Add an RWA token
        vm.expectEmit(true, true, true, true);
        emit RWATokenAdded(address(rwaToken1), 10000);
        
        manager.addRWAToken(address(rwaToken1), 10000);
        
        // Check token was added correctly
        (address token, uint256 weight, bool active) = manager.getRWATokenInfo(address(rwaToken1));
        assertEq(token, address(rwaToken1));
        assertEq(weight, 10000);
        assertTrue(active);
        
        // Check total weight
        assertEq(manager.getTotalRWAWeight(), 10000);
    }
    
    // Test setting allocation percentages
    function test_SetAllocation() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        vm.expectEmit(true, true, true, true);
        emit AllocationUpdated(4000, 5000, 1000);
        
        manager.setAllocation(4000, 5000, 1000);
        
        // Check allocation was updated
        assertEq(manager.getRWAAllocation(), 4000);
        assertEq(manager.getYieldAllocation(), 5000);
        assertEq(manager.getLiquidityBuffer(), 1000);
    }
    
    // Test allocating capital with mixed allocation
    function test_Allocate_MixedAllocation() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Calculate expected allocations
        uint256 expectedRWAAllocation = ALLOCATION_AMOUNT * 4000 / 10000; // 40%
        uint256 expectedYieldAllocation = ALLOCATION_AMOUNT * 5000 / 10000; // 50%
        uint256 expectedLiquidityBuffer = ALLOCATION_AMOUNT * 1000 / 10000; // 10%
        
        // Calculate expected RWA token allocations
        uint256 expectedRWA1Allocation = expectedRWAAllocation * 7000 / 10000; // 70% of RWA allocation
        uint256 expectedRWA2Allocation = expectedRWAAllocation * 3000 / 10000; // 30% of RWA allocation
        
        // Calculate expected yield strategy allocations
        uint256 expectedYield1Allocation = expectedYieldAllocation * 6000 / 10000; // 60% of yield allocation
        uint256 expectedYield2Allocation = expectedYieldAllocation * 4000 / 10000; // 40% of yield allocation
        
        // Check RWA token allocations
        assertApproxEqRel(rwaToken1.totalSupply(), expectedRWA1Allocation, 0.01e18);
        assertApproxEqRel(rwaToken2.totalSupply(), expectedRWA2Allocation, 0.01e18);
        
        // Check yield strategy allocations
        assertApproxEqRel(yieldStrategy1.getTotalValue(), expectedYield1Allocation, 0.01e18);
        assertApproxEqRel(yieldStrategy2.getTotalValue(), expectedYield2Allocation, 0.01e18);
        
        // Check liquidity buffer
        assertApproxEqRel(baseAsset.balanceOf(address(manager)), expectedLiquidityBuffer, 0.01e18);
    }
    
    // Test rebalancing with price changes
    function test_RebalanceWithPriceChanges() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Add yield strategy and RWA token
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Simulate price increase for RWA token (50% increase)
        rwaToken1.setPrice(1.5e18);
        
        // Rebalance
        manager.rebalance();
        
        // Calculate expected allocations after rebalance
        uint256 expectedRWAAllocation = ALLOCATION_AMOUNT * 4000 / 10000; // 40%
        uint256 expectedYieldAllocation = ALLOCATION_AMOUNT * 5000 / 10000; // 50%
        uint256 expectedLiquidityBuffer = ALLOCATION_AMOUNT * 1000 / 10000; // 10%
        
        // Due to price increase, the RWA value is now 1.5x the original allocation
        // So we expect some RWA tokens to be sold to bring it back to 40%
        uint256 expectedRWAValue = expectedRWAAllocation;
        
        // Check RWA value after rebalance
        uint256 rwaValue = manager.getRWAValue();
        assertApproxEqRel(rwaValue, expectedRWAValue, 0.01e18);
        
        // Check yield strategy allocation after rebalance
        assertApproxEqRel(yieldStrategy1.getTotalValue(), expectedYieldAllocation, 0.01e18);
        
        // Check liquidity buffer after rebalance
        assertApproxEqRel(baseAsset.balanceOf(address(manager)), expectedLiquidityBuffer, 0.01e18);
    }
    
    // Test rebalancing with multiple assets and strategies
    function test_RebalanceMultipleAssetsAndStrategies() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Simulate price changes
        rwaToken1.setPrice(1.3e18); // 30% increase
        rwaToken2.setPrice(0.8e18); // 20% decrease
        
        // Rebalance
        manager.rebalance();
        
        // Calculate expected allocations after rebalance
        uint256 expectedRWAAllocation = ALLOCATION_AMOUNT * 4000 / 10000; // 40%
        uint256 expectedYieldAllocation = ALLOCATION_AMOUNT * 5000 / 10000; // 50%
        uint256 expectedLiquidityBuffer = ALLOCATION_AMOUNT * 1000 / 10000; // 10%
        
        // Calculate expected RWA token allocations
        uint256 expectedRWA1Value = expectedRWAAllocation * 7000 / 10000; // 70% of RWA allocation
        uint256 expectedRWA2Value = expectedRWAAllocation * 3000 / 10000; // 30% of RWA allocation
        
        // Calculate expected yield strategy allocations
        uint256 expectedYield1Value = expectedYieldAllocation * 6000 / 10000; // 60% of yield allocation
        uint256 expectedYield2Value = expectedYieldAllocation * 4000 / 10000; // 40% of yield allocation
        
        // Check RWA token values after rebalance
        uint256 rwa1Value = rwaToken1.totalSupply() * rwaToken1.getPrice() / 1e18;
        uint256 rwa2Value = rwaToken2.totalSupply() * rwaToken2.getPrice() / 1e18;
        assertApproxEqRel(rwa1Value, expectedRWA1Value, 0.01e18);
        assertApproxEqRel(rwa2Value, expectedRWA2Value, 0.01e18);
        
        // Check yield strategy values after rebalance
        assertApproxEqRel(yieldStrategy1.getTotalValue(), expectedYield1Value, 0.01e18);
        assertApproxEqRel(yieldStrategy2.getTotalValue(), expectedYield2Value, 0.01e18);
        
        // Check liquidity buffer after rebalance
        assertApproxEqRel(baseAsset.balanceOf(address(manager)), expectedLiquidityBuffer, 0.01e18);
    }
    
    // Test removing a yield strategy
    function test_RemoveYieldStrategy() public {
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Remove the first yield strategy
        vm.expectEmit(true, true, true, true);
        emit YieldStrategyRemoved(address(yieldStrategy1));
        
        manager.removeYieldStrategy(address(yieldStrategy1));
        
        // Check strategy was removed correctly
        (,, bool active) = manager.getYieldStrategyInfo(address(yieldStrategy1));
        assertFalse(active);
        
        // Check total weight
        assertEq(manager.getTotalYieldWeight(), 4000);
        
        // Check active yield strategies
        address[] memory activeStrategies = manager.getActiveYieldStrategies();
        assertEq(activeStrategies.length, 1);
        assertEq(activeStrategies[0], address(yieldStrategy2));
    }
    
    // Test removing an RWA token
    function test_RemoveRWAToken() public {
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Remove the first RWA token
        vm.expectEmit(true, true, true, true);
        emit RWATokenRemoved(address(rwaToken1));
        
        manager.removeRWAToken(address(rwaToken1));
        
        // Check token was removed correctly
        (,, bool active) = manager.getRWATokenInfo(address(rwaToken1));
        assertFalse(active);
        
        // Check total weight
        assertEq(manager.getTotalRWAWeight(), 3000);
        
        // Check active RWA tokens
        address[] memory activeTokens = manager.getActiveRWATokens();
        assertEq(activeTokens.length, 1);
        assertEq(activeTokens[0], address(rwaToken2));
    }
    
    // Test updating yield strategy weight
    function test_UpdateYieldStrategyWeight() public {
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Update weight of first strategy to 8000 (80%)
        vm.expectEmit(true, true, true, true);
        emit YieldStrategyWeightUpdated(address(yieldStrategy1), 6000, 8000);
        
        manager.updateYieldStrategyWeight(address(yieldStrategy1), 8000);
        
        // Check weight was updated
        (,uint256 weight,) = manager.getYieldStrategyInfo(address(yieldStrategy1));
        assertEq(weight, 8000);
        
        // Check total weight
        assertEq(manager.getTotalYieldWeight(), 12000);
    }
    
    // Test updating RWA token weight
    function test_UpdateRWATokenWeight() public {
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Update weight of first token to 5000 (50%)
        vm.expectEmit(true, true, true, true);
        emit RWATokenWeightUpdated(address(rwaToken1), 7000, 5000);
        
        manager.updateRWATokenWeight(address(rwaToken1), 5000);
        
        // Check weight was updated
        (,uint256 weight,) = manager.getRWATokenInfo(address(rwaToken1));
        assertEq(weight, 5000);
        
        // Check total weight
        assertEq(manager.getTotalRWAWeight(), 8000);
    }
    
    // Test reentrancy protection on rebalance
    function test_Rebalance_ReentrancyProtection() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Configure malicious yield strategy for attack
        yieldStrategy1.setAttackMode(true, false); // Attack on deposit
        yieldStrategy1.activateAttack(true);
        
        // Add malicious yield strategy
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        
        // Add RWA token
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Simulate price change to trigger rebalance
        rwaToken1.setPrice(1.5e18);
        
        // Try to rebalance (should revert with ReentrancyGuardReentrantCall)
        vm.expectRevert();
        manager.rebalance();
    }
    
    // Test reentrancy protection on allocate
    function test_Allocate_ReentrancyProtection() public {
        // Set allocation to 40% RWA, 50% yield, 10% liquidity buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Configure malicious yield strategy for attack
        yieldStrategy1.setAttackMode(true, false); // Attack on deposit
        yieldStrategy1.activateAttack(true);
        
        // Add malicious yield strategy
        manager.addYieldStrategy(address(yieldStrategy1), 10000); // 100%
        
        // Add RWA token
        manager.addRWAToken(address(rwaToken1), 10000); // 100%
        
        // Try to allocate capital (should revert with ReentrancyGuardReentrantCall)
        vm.expectRevert();
        manager.allocate(ALLOCATION_AMOUNT);
    }
    
    // Test invalid allocation parameters
    function test_SetAllocation_InvalidParams() public {
        // Test total exceeding 100%
        vm.expectRevert(CommonErrors.TotalExceeds100Percent.selector);
        manager.setAllocation(5000, 5001, 0);
        
        // Test zero RWA allocation
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        manager.setAllocation(0, 9000, 1000);
        
        // Test zero yield allocation
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        manager.setAllocation(9000, 0, 1000);
    }
    
    // Test adding yield strategy with invalid parameters
    function test_AddYieldStrategy_InvalidParams() public {
        // Test zero address
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        manager.addYieldStrategy(address(0), 5000);
        
        // Test zero weight
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        manager.addYieldStrategy(address(yieldStrategy1), 0);
        
        // Test adding same strategy twice
        manager.addYieldStrategy(address(yieldStrategy1), 5000);
        vm.expectRevert(CommonErrors.AlreadyExists.selector);
        manager.addYieldStrategy(address(yieldStrategy1), 5000);
    }
    
    // Test adding RWA token with invalid parameters
    function test_AddRWAToken_InvalidParams() public {
        // Test zero address
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        manager.addRWAToken(address(0), 5000);
        
        // Test zero weight
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        manager.addRWAToken(address(rwaToken1), 0);
        
        // Test adding same token twice
        manager.addRWAToken(address(rwaToken1), 5000);
        vm.expectRevert(CommonErrors.AlreadyExists.selector);
        manager.addRWAToken(address(rwaToken1), 5000);
    }
    
    // Test getting RWA value
    function test_GetRWAValue() public {
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 7000); // 70%
        manager.addRWAToken(address(rwaToken2), 3000); // 30%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Calculate expected RWA allocation
        uint256 expectedRWAAllocation = ALLOCATION_AMOUNT * 3000 / 10000; // 30% default allocation
        
        // Check RWA value
        uint256 rwaValue = manager.getRWAValue();
        assertApproxEqRel(rwaValue, expectedRWAAllocation, 0.01e18);
        
        // Simulate price changes
        rwaToken1.setPrice(1.2e18); // 20% increase
        rwaToken2.setPrice(0.9e18); // 10% decrease
        
        // Calculate expected RWA value after price changes
        uint256 expectedRWA1Value = expectedRWAAllocation * 7000 / 10000 * 12 / 10; // 70% of RWA allocation with 20% price increase
        uint256 expectedRWA2Value = expectedRWAAllocation * 3000 / 10000 * 9 / 10; // 30% of RWA allocation with 10% price decrease
        uint256 expectedTotalRWAValue = expectedRWA1Value + expectedRWA2Value;
        
        // Check updated RWA value
        rwaValue = manager.getRWAValue();
        assertApproxEqRel(rwaValue, expectedTotalRWAValue, 0.01e18);
    }
    
    // Test getting yield value
    function test_GetYieldValue() public {
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        manager.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        
        // Allocate capital
        manager.allocate(ALLOCATION_AMOUNT);
        
        // Calculate expected yield allocation
        uint256 expectedYieldAllocation = ALLOCATION_AMOUNT * 6000 / 10000; // 60% default allocation
        
        // Check yield value
        uint256 yieldValue = manager.getYieldValue();
        assertApproxEqRel(yieldValue, expectedYieldAllocation, 0.01e18);
    }
}
