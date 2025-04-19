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
    
    function setName(string memory _name) external {
        name = _name;
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
    string public name = "Mock RWA Token";
    uint256 public totalSupply;
    mapping(address => uint256) private _balances;
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setPrice(uint256 _price) external {
        price = _price;
    }
    
    function setActive(bool _active) external {
        active = _active;
    }
    
    function setName(string memory _name) external {
        name = _name;
    }
    
    function mint(address to, uint256 amount) external override returns (bool) {
        // Calculate how much base asset is needed
        uint256 baseAmount = (amount * 1e18) / price;
        
        // Transfer base asset from sender to this contract
        baseAsset.transferFrom(msg.sender, address(this), baseAmount);
        
        // Mint RWA tokens to recipient
        _balances[to] += amount;
        totalSupply += amount;
        
        return true;
    }
    
    function burn(uint256 amount) external override returns (uint256 baseAmount) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        
        // Calculate how much base asset to return
        baseAmount = (amount * price) / 1e18;
        
        // Burn RWA tokens
        _balances[msg.sender] -= amount;
        totalSupply -= amount;
        
        // Transfer base asset back to sender
        baseAsset.transfer(msg.sender, baseAmount);
        
        return baseAmount;
    }
    
    function getPrice() external view override returns (uint256) {
        return price;
    }
    
    function getTokenInfo() external view override returns (TokenInfo memory info) {
        return TokenInfo({
            name: name,
            baseAsset: address(baseAsset),
            price: price,
            totalSupply: totalSupply,
            lastUpdated: block.timestamp,
            active: active
        });
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
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
        baseAsset = new MockERC20();
        
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
        manager = new CapitalAllocationManager(IERC20(address(baseAsset)));
        
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
        assertEq(manager.getRWAAllocation(), 3000); // Default 30%
        assertEq(manager.getYieldAllocation(), 6000); // Default 60%
        assertEq(manager.getLiquidityBuffer(), 1000); // Default 10%
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
}
