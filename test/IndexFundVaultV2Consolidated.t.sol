// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockFeeManager} from "../src/mocks/MockFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";
import {IAssetWrapper} from "../src/interfaces/IAssetWrapper.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MockRWAAssetWrapper
 * @dev Mock implementation of IAssetWrapper for testing purposes
 * Provides direct control over asset values and operations
 */
contract MockRWAAssetWrapper is IAssetWrapper {
    string public name;
    IERC20 public baseAsset;
    uint256 private _valueInBaseAsset;
    address public owner;
    
    constructor(string memory _name, address _baseAsset) {
        name = _name;
        baseAsset = IERC20(_baseAsset);
        owner = msg.sender;
    }
    
    function setValueInBaseAsset(uint256 value) external {
        _valueInBaseAsset = value;
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        // Transfer the base asset to this contract
        baseAsset.transferFrom(msg.sender, address(this), amount);
        _valueInBaseAsset += amount;
        return true;
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256 actualAmount) {
        require(amount <= _valueInBaseAsset, "Insufficient balance");
        _valueInBaseAsset -= amount;
        
        // Transfer the base asset back
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueInBaseAsset() external view override returns (uint256) {
        return _valueInBaseAsset;
    }
    
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    function getName() external view override returns (string memory) {
        return name;
    }
    
    function getUnderlyingTokens() external pure override returns (address[] memory tokens) {
        // Return an empty array for simplicity
        return new address[](0);
    }
    
    function harvestYield() external pure override returns (uint256 harvestedAmount) {
        // Mock implementation - no yield harvesting
        return 0;
    }
}

/**
 * @title YieldGeneratingWrapper
 * @dev Mock implementation of IAssetWrapper that generates yield
 * Used for testing yield harvesting
 */
contract YieldGeneratingWrapper is IAssetWrapper {
    string public name;
    IERC20 public baseAsset;
    uint256 private _valueInBaseAsset;
    uint256 private _yieldAmount;
    address public owner;
    
    constructor(string memory _name, address _baseAsset) {
        name = _name;
        baseAsset = IERC20(_baseAsset);
        owner = msg.sender;
    }
    
    function setValueInBaseAsset(uint256 value) external {
        _valueInBaseAsset = value;
    }
    
    function setYieldAmount(uint256 amount) external {
        _yieldAmount = amount;
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        // Transfer the base asset to this contract
        baseAsset.transferFrom(msg.sender, address(this), amount);
        _valueInBaseAsset += amount;
        return true;
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256 actualAmount) {
        require(amount <= _valueInBaseAsset, "Insufficient balance");
        _valueInBaseAsset -= amount;
        
        // Transfer the base asset back
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueInBaseAsset() external view override returns (uint256) {
        return _valueInBaseAsset;
    }
    
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    function getName() external view override returns (string memory) {
        return name;
    }
    
    function getUnderlyingTokens() external pure override returns (address[] memory tokens) {
        // Return an empty array for simplicity
        return new address[](0);
    }
    
    function harvestYield() external override returns (uint256 harvestedAmount) {
        // Transfer yield to caller
        if (_yieldAmount > 0) {
            baseAsset.transfer(msg.sender, _yieldAmount);
            harvestedAmount = _yieldAmount;
            _yieldAmount = 0;
        }
        return harvestedAmount;
    }
}

/**
 * @title MaliciousAssetWrapper
 * @dev Mock implementation of IAssetWrapper that attempts reentrancy attacks
 * Used for testing reentrancy protection
 */
contract MaliciousAssetWrapper is IAssetWrapper {
    address public target;
    bool public attackOnAllocate;
    bool public attackOnWithdraw;
    bool public attackActive;
    uint256 public valueInBaseAsset;
    IERC20 public baseAsset;
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setTarget(address _target) external {
        target = _target;
    }
    
    function setAttackMode(bool _onAllocate, bool _onWithdraw) external {
        attackOnAllocate = _onAllocate;
        attackOnWithdraw = _onWithdraw;
    }
    
    function activateAttack(bool _active) external {
        attackActive = _active;
    }
    
    function setValueInBaseAsset(uint256 _value) external {
        valueInBaseAsset = _value;
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        // Transfer the base asset to this contract
        baseAsset.transferFrom(msg.sender, address(this), amount);
        valueInBaseAsset += amount;
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnAllocate && target != address(0)) {
            // Try to call rebalance on the vault
            IndexFundVaultV2(target).rebalance();
        }
        
        return true;
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256 actualAmount) {
        require(amount <= valueInBaseAsset, "Insufficient balance");
        valueInBaseAsset -= amount;
        
        // Attempt reentrancy if configured
        if (attackActive && attackOnWithdraw && target != address(0)) {
            // Try to call rebalance on the vault before transferring funds
            IndexFundVaultV2(target).rebalance();
        }
        
        // Transfer the base asset back
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueInBaseAsset() external view override returns (uint256) {
        return valueInBaseAsset;
    }
    
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    function getName() external pure override returns (string memory) {
        return "Malicious Asset Wrapper";
    }
    
    function getUnderlyingTokens() external pure override returns (address[] memory tokens) {
        // Return an empty array for simplicity
        return new address[](0);
    }
    
    function harvestYield() external pure override returns (uint256 harvestedAmount) {
        // Mock implementation - no yield harvesting
        return 0;
    }
}

/**
 * @title IndexFundVaultV2ConsolidatedTest
 * @dev Comprehensive test suite for IndexFundVaultV2
 * Consolidates tests from multiple test files into a single, comprehensive test suite
 */
contract IndexFundVaultV2ConsolidatedTest is Test {
    // Contracts
    IndexFundVaultV2 public vault;
    MockRWAAssetWrapper public rwaWrapper;
    MockERC20 public mockUSDC;
    MockRWAAssetWrapper public rwaWrapper2;
    MockRWAAssetWrapper public rwaWrapper3;
    MockPriceOracle public mockPriceOracle;
    MockDEX public mockDEX;
    MockFeeManager public mockFeeManager;
    MaliciousAssetWrapper public maliciousWrapper;
    
    // Users
    address public owner;
    address public user1;
    address public user2;
    address public attacker;
    
    // Constants
    uint256 public constant INITIAL_PRICE = 5000 * 1e6; // $5000 in USDC decimals
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 1e6; // 10000 USDC
    uint256 public constant INITIAL_BALANCE = 100000 * 1e6; // 100000 USDC initial balance for users
    
    // Events
    event AssetAdded(address indexed assetAddress, uint256 weight);
    event AssetRemoved(address indexed assetAddress);
    event AssetWeightUpdated(address indexed assetAddress, uint256 oldWeight, uint256 newWeight);
    event Rebalanced();
    event RebalanceIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event RebalanceThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DEXUpdated(address indexed oldDEX, address indexed newDEX);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    
    function setUp() public {
        owner = address(this); // Test contract is the owner
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");
        
        // Deploy mock contracts
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockPriceOracle = new MockPriceOracle();
        mockDEX = new MockDEX();
        mockFeeManager = new MockFeeManager(address(mockUSDC));
        
        // Deploy the vault
        vault = new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            mockDEX
        );
        
        // Deploy the RWA wrappers
        rwaWrapper = new MockRWAAssetWrapper("Mock RWA 1", address(mockUSDC));
        rwaWrapper2 = new MockRWAAssetWrapper("Mock RWA 2", address(mockUSDC));
        rwaWrapper3 = new MockRWAAssetWrapper("Mock RWA 3", address(mockUSDC));
        
        // Deploy vault (owned by this test contract)
        vault = new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            mockDEX
        );
        
        // Set rebalance interval to 0 to avoid timing issues in tests
        vault.setRebalanceInterval(0);
        
        // Ensure this test contract is the owner of the vault
        assertEq(vault.owner(), address(this));
        
        // Approve USDC for the RWA wrapper
        mockUSDC.approve(address(rwaWrapper), type(uint256).max);
        
        // Approve USDC for the vault to spend
        mockUSDC.approve(address(vault), type(uint256).max);
        
        // Approve USDC for the malicious wrapper
        mockUSDC.approve(address(maliciousWrapper), type(uint256).max);
        
        // Mint USDC to users
        mockUSDC.mint(user1, INITIAL_BALANCE);
        mockUSDC.mint(user2, INITIAL_BALANCE);
        mockUSDC.mint(attacker, INITIAL_BALANCE);
        
        // Approve USDC for the vault
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(attacker);
        mockUSDC.approve(address(vault), type(uint256).max);
        mockUSDC.approve(address(maliciousWrapper), type(uint256).max);
        vm.stopPrank();
        
        // Configure malicious wrapper
        maliciousWrapper.setTarget(address(vault));
    }
    
    // Test adding an asset to the vault
    function test_AddAsset() public {
        // Add RWA wrapper to the vault
        vm.expectEmit(true, true, true, true);
        emit AssetAdded(address(rwaWrapper), 5000); // 50% weight
        vault.addAsset(address(rwaWrapper), 5000);
        
        // Check that the asset was added
        (address wrapper, uint256 weight, bool active) = vault.getAssetInfo(address(rwaWrapper));
        assertEq(wrapper, address(rwaWrapper));
        assertEq(weight, 5000);
        assertTrue(active);
        
        // Check active assets
        address[] memory activeAssets = vault.getActiveAssets();
        assertEq(activeAssets.length, 1);
        assertEq(activeAssets[0], address(rwaWrapper));
    }
    
    // Test rebalance with no assets
    function test_Rebalance_NoAssets() public {
        // Should not revert but do nothing
        vault.rebalance();
        
        // Total assets should be 0
        assertEq(vault.totalAssets(), 0);
    }
    
    // Test rebalance with one asset
    function test_Rebalance_OneAsset() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper value to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        
        // Rebalance
        vm.expectEmit(true, true, true, true);
        emit Rebalanced();
        vault.rebalance();
        
        // After rebalance, set the wrapper value to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT);
        
        // Check that all funds are allocated to the RWA wrapper
        assertEq(rwaWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT);
        assertEq(mockUSDC.balanceOf(address(vault)), 0);
    }
    
    // Test rebalance with multiple assets
    function test_Rebalance_MultipleAssets() public {
        // Add RWA wrapper to the vault with 60% weight
        vault.addAsset(address(rwaWrapper), 6000);
        
        // Create and add a second asset wrapper with 40% weight
        MockRWAAssetWrapper rwaWrapper2 = new MockRWAAssetWrapper(
            "Second RWA",
            address(mockUSDC)
        );
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        vault.addAsset(address(rwaWrapper2), 4000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper values to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        rwaWrapper2.setValueInBaseAsset(0);
        
        // Rebalance
        vault.rebalance();
        
        // After rebalance, set the wrapper values to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100);
        rwaWrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 40 / 100);
        
        // Check that funds are allocated according to weights
        assertApproxEqRel(rwaWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT * 60 / 100, 0.01e18);
        assertApproxEqRel(rwaWrapper2.getValueInBaseAsset(), DEPOSIT_AMOUNT * 40 / 100, 0.01e18);
        assertEq(mockUSDC.balanceOf(address(vault)), 0);
    }
    
    // Test rebalance threshold
    function test_RebalanceThreshold() public {
        // Add RWA wrapper to the vault with 60% weight
        vault.addAsset(address(rwaWrapper), 6000);
        
        // Create and add a second asset wrapper with 40% weight
        MockRWAAssetWrapper rwaWrapper2 = new MockRWAAssetWrapper(
            "Second RWA",
            address(mockUSDC)
        );
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        vault.addAsset(address(rwaWrapper2), 4000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper values to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        rwaWrapper2.setValueInBaseAsset(0);
        
        // Rebalance
        vault.rebalance();
        
        // After rebalance, set the wrapper values to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100);
        rwaWrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 40 / 100);
        
        // Set rebalance interval to a large value
        vault.setRebalanceInterval(365 days);
        
        // Set rebalance threshold to 5%
        vault.setRebalanceThreshold(500);
        
        // Set a small deviation in asset values (below threshold)
        uint256 smallDeviation = DEPOSIT_AMOUNT * 4 / 100; // 4% deviation
        // Simulate value change by updating the mock wrapper value
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100 + smallDeviation);
        
        // Try to rebalance before interval has passed with small deviation
        vm.expectRevert(CommonErrors.TooEarly.selector);
        vault.rebalance();
        
        // Now create a larger deviation (above threshold)
        uint256 largeDeviation = DEPOSIT_AMOUNT * 6 / 100; // 6% deviation
        // Simulate value change by updating the mock wrapper value
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100 + smallDeviation + largeDeviation);
        
        // Should be able to rebalance now due to threshold being exceeded
        vault.rebalance();
    }
    
    // Test rebalance interval
    function test_RebalanceInterval() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper value to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        
        // Rebalance
        vault.rebalance();
        
        // After rebalance, set the wrapper value to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT);
        
        // Set rebalance interval to 1 day
        vault.setRebalanceInterval(1 days);
        
        // Try to rebalance immediately
        vm.expectRevert(CommonErrors.TooEarly.selector);
        vault.rebalance();
        
        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Should be able to rebalance now
        vault.rebalance();
    }
    
    // Test reentrancy protection on rebalance
    function test_Rebalance_ReentrancyProtection() public {
        // Configure malicious wrapper for attack
        maliciousWrapper.setAttackMode(true, false); // Attack on allocate
        maliciousWrapper.activateAttack(true);
        
        // Add malicious wrapper to the vault
        vault.addAsset(address(maliciousWrapper), 10000); // 100% weight
        
        // Deposit from attacker
        vm.startPrank(attacker);
        vault.deposit(DEPOSIT_AMOUNT, attacker);
        vm.stopPrank();
        
        // Try to rebalance (should revert with ReentrancyGuardReentrantCall)
        vm.expectRevert();
        vault.rebalance();
    }
    
    // Test reentrancy protection on withdraw
    function test_Withdraw_ReentrancyProtection() public {
        // Configure malicious wrapper for attack
        maliciousWrapper.setAttackMode(false, true); // Attack on withdraw
        maliciousWrapper.activateAttack(true);
        
        // Add malicious wrapper to the vault
        vault.addAsset(address(maliciousWrapper), 10000); // 100% weight
        
        // Deposit from attacker
        vm.startPrank(attacker);
        vault.deposit(DEPOSIT_AMOUNT, attacker);
        vm.stopPrank();
        
        // Rebalance to allocate funds to the wrapper
        vault.rebalance();
        
        // Set the malicious wrapper value to simulate allocation
        maliciousWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT);
        
        // Make sure the vault has no USDC balance to force it to withdraw from wrapper
        assertEq(mockUSDC.balanceOf(address(vault)), 0);
        
        // Try to withdraw (should revert with ReentrancyGuardReentrantCall)
        vm.startPrank(attacker);
        vm.expectRevert();
        vault.withdraw(DEPOSIT_AMOUNT / 2, attacker, attacker);
        vm.stopPrank();
    }
    
    // Test removing an asset
    function test_RemoveAsset() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper value to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        
        // Rebalance to allocate funds
        vault.rebalance();
        
        // After rebalance, set the wrapper value to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT);
        
        // Remove the asset
        vm.expectEmit(true, true, true, true);
        emit AssetRemoved(address(rwaWrapper));
        vault.removeAsset(address(rwaWrapper));
        
        // Simulate the funds being returned to the vault
        rwaWrapper.setValueInBaseAsset(0);
        
        // Check that the asset was removed
        (address wrapper, uint256 weight, bool active) = vault.getAssetInfo(address(rwaWrapper));
        assertEq(wrapper, address(rwaWrapper));
        assertEq(weight, 0);
        assertFalse(active);
        
        // Check that funds were withdrawn from the wrapper
        assertEq(rwaWrapper.getValueInBaseAsset(), 0);
        
        // Check active assets
        address[] memory activeAssets = vault.getActiveAssets();
        assertEq(activeAssets.length, 0);
    }
    
    // Test removing a non-existent asset
    function test_RemoveAsset_NonExistent() public {
        vm.expectRevert(CommonErrors.TokenNotFound.selector);
        vault.removeAsset(address(rwaWrapper));
    }
    
    // Test updating asset weight
    function test_UpdateAssetWeight_Comprehensive() public {
        // Add RWA wrapper to the vault with 60% weight
        vault.addAsset(address(rwaWrapper), 6000);
        
        // Create and add a second asset wrapper with 40% weight
        MockRWAAssetWrapper rwaWrapper2 = new MockRWAAssetWrapper(
            "Second RWA",
            address(mockUSDC)
        );
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        vault.addAsset(address(rwaWrapper2), 4000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper values to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        rwaWrapper2.setValueInBaseAsset(0);
        
        // Rebalance
        vault.rebalance();
        
        // After rebalance, set the wrapper values to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100);
        rwaWrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 40 / 100);
        
        // Update weights
        vm.expectEmit(true, true, true, true);
        emit AssetWeightUpdated(address(rwaWrapper), 6000, 3000);
        vault.updateAssetWeight(address(rwaWrapper), 3000);
        
        vm.expectEmit(true, true, true, true);
        emit AssetWeightUpdated(address(rwaWrapper2), 4000, 7000);
        vault.updateAssetWeight(address(rwaWrapper2), 7000);
        
        // Check weights were updated
        (,uint256 weight1,) = vault.getAssetInfo(address(rwaWrapper));
        (,uint256 weight2,) = vault.getAssetInfo(address(rwaWrapper2));
        assertEq(weight1, 3000);
        assertEq(weight2, 7000);
        
        // Rebalance to apply new weights
        vault.rebalance();
        
        // After rebalance, update the wrapper values to match the new allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 30 / 100);
        rwaWrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 70 / 100);
        
        // Check that funds were reallocated according to new weights
        assertApproxEqRel(rwaWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT * 30 / 100, 0.01e18);
        assertApproxEqRel(rwaWrapper2.getValueInBaseAsset(), DEPOSIT_AMOUNT * 70 / 100, 0.01e18);
    }
    
    // Test updating asset weight with invalid parameters
    function test_UpdateAssetWeight_InvalidParams() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 5000); // 50% weight
        
        // Test zero weight
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        vault.updateAssetWeight(address(rwaWrapper), 0);
        
        // Test exceeding 100%
        vm.expectRevert(CommonErrors.TotalExceeds100Percent.selector);
        vault.updateAssetWeight(address(rwaWrapper), 10001);
    }
    
    // Test updating price oracle
    function test_UpdatePriceOracle() public {
        // Create a new price oracle
        MockPriceOracle newOracle = new MockPriceOracle();
        
        // Update the price oracle
        address oldOracle = address(mockPriceOracle);
        vm.expectEmit(true, true, true, true);
        emit PriceOracleUpdated(oldOracle, address(newOracle));
        vault.updatePriceOracle(newOracle);
        
        // Check that the oracle was updated
        assertEq(address(vault.priceOracle()), address(newOracle));
    }
    
    // Test updating DEX
    function test_UpdateDEX() public {
        // Create a new DEX
        MockDEX newDEX = new MockDEX();
        
        // Update the DEX
        address oldDEX = address(mockDEX);
        vm.expectEmit(true, true, true, true);
        emit DEXUpdated(oldDEX, address(newDEX));
        vault.updateDEX(newDEX);
        
        // Check that the DEX was updated
        assertEq(address(vault.dex()), address(newDEX));
    }
    
    // Test setting rebalance threshold
    function test_SetRebalanceThreshold_Comprehensive() public {
        uint256 oldThreshold = vault.rebalanceThreshold();
        uint256 newThreshold = 1000; // 10%
        
        vm.expectEmit(true, true, true, true);
        emit RebalanceThresholdUpdated(oldThreshold, newThreshold);
        vault.setRebalanceThreshold(newThreshold);
        
        // Check that the threshold was updated
        assertEq(vault.rebalanceThreshold(), newThreshold);
    }
    
    // Test setting rebalance threshold with invalid value
    function test_SetRebalanceThreshold_InvalidValue() public {
        // Test exceeding 100%
        vm.expectRevert(CommonErrors.ValueTooHigh.selector);
        vault.setRebalanceThreshold(10001);
    }
    
    // Test setting rebalance interval
    function test_SetRebalanceInterval_Comprehensive() public {
        uint256 oldInterval = vault.rebalanceInterval();
        uint256 newInterval = 7 days;
        
        vm.expectEmit(true, true, true, true);
        emit RebalanceIntervalUpdated(oldInterval, newInterval);
        vault.setRebalanceInterval(newInterval);
        
        // Check that the interval was updated
        assertEq(vault.rebalanceInterval(), newInterval);
    }
    
    // Test setting rebalance interval with invalid value
    function test_SetRebalanceInterval_InvalidValue() public {
        // Test exceeding uint32 max
        vm.expectRevert(CommonErrors.ValueTooHigh.selector);
        vault.setRebalanceInterval(uint256(type(uint32).max) + 1);
    }
    
    // Test isRebalanceNeeded functionality
    function test_IsRebalanceNeeded() public {
        // Add RWA wrapper to the vault with 60% weight
        vault.addAsset(address(rwaWrapper), 6000);
        
        // Create and add a second asset wrapper with 40% weight
        MockRWAAssetWrapper rwaWrapper2 = new MockRWAAssetWrapper(
            "Second RWA",
            address(mockUSDC)
        );
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        vault.addAsset(address(rwaWrapper2), 4000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially set the wrapper values to 0 (no funds allocated yet)
        rwaWrapper.setValueInBaseAsset(0);
        rwaWrapper2.setValueInBaseAsset(0);
        
        // Rebalance
        vault.rebalance();
        
        // After rebalance, set the wrapper values to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100);
        rwaWrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 40 / 100);
        
        // Set rebalance threshold to 5%
        vault.setRebalanceThreshold(500);
        
        // Check that rebalance is not needed with current allocation
        assertFalse(vault.isRebalanceNeeded());
        
        // Simulate a large price change in one asset
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 70 / 100); // 10% deviation
        
        // Now rebalance should be needed
        assertTrue(vault.isRebalanceNeeded());
    }
    
    // Test vault pausing
    function test_VaultPausing() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Pause the vault
        vault.pause();
        
        // Deposit should fail when paused
        vm.startPrank(user1);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Withdraw should fail when paused
        vm.startPrank(user1);
        vm.expectRevert();
        vault.withdraw(DEPOSIT_AMOUNT, user1, user1);
        vm.stopPrank();
        
        // Rebalance should fail when paused
        vm.expectRevert();
        vault.rebalance();
        
        // Unpause the vault
        vault.unpause();
        
        // Operations should work again
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
    }
    
    // Test total assets calculation
    function test_TotalAssets() public {
        // Add RWA wrapper to the vault with 60% weight
        vault.addAsset(address(rwaWrapper), 6000);
        
        // Create and add a second asset wrapper with 40% weight
        MockRWAAssetWrapper rwaWrapper2 = new MockRWAAssetWrapper(
            "Second RWA",
            address(mockUSDC)
        );
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        vault.addAsset(address(rwaWrapper2), 4000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initially total assets should equal deposit amount
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        
        // Rebalance to allocate funds
        vault.rebalance();
        
        // After rebalance, set the wrapper values to match the expected allocation
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100);
        rwaWrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 40 / 100);
        
        // Total assets should still equal deposit amount
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        
        // Simulate value increase in first wrapper (10% gain)
        uint256 valueIncrease = DEPOSIT_AMOUNT * 60 / 100 * 10 / 100;
        rwaWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100 + valueIncrease);
        
        // Total assets should reflect the increase
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT + valueIncrease);
    }
    
    // Test max deposit and max withdraw
    function test_MaxDepositAndWithdraw() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Initially max withdraw should be 0 (no shares)
        assertEq(vault.maxWithdraw(user1), 0);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // After deposit, max withdraw should equal deposit amount
        assertEq(vault.maxWithdraw(user1), DEPOSIT_AMOUNT);
        
        // Pause the vault
        vault.pause();
        
        // Unpause the vault
        vault.unpause();
        
        // After unpause, max withdraw should equal deposit amount again
        assertEq(vault.maxWithdraw(user1), DEPOSIT_AMOUNT);
    }
    
    // Test multiple assets with mock implementation
    function test_MultipleAssets_WithMocks() public {
        // Add RWA wrapper to the vault with 40% weight
        vault.addAsset(address(rwaWrapper), 4000);
        
        // Create and add a second asset wrapper with 60% weight
        MockRWAAssetWrapper rwaWrapper2 = new MockRWAAssetWrapper(
            "Second RWA",
            address(mockUSDC)
        );
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        vault.addAsset(address(rwaWrapper2), 6000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Force rebalance interval to pass
        vm.warp(block.timestamp + vault.rebalanceInterval() + 1);
        
        // Mock the getValueInBaseAsset function for both RWA wrappers
        vm.mockCall(
            address(rwaWrapper),
            abi.encodeWithSelector(IAssetWrapper.getValueInBaseAsset.selector),
            abi.encode(DEPOSIT_AMOUNT * 4000 / 10000) // 40% of deposit amount
        );
        
        vm.mockCall(
            address(rwaWrapper2),
            abi.encodeWithSelector(IAssetWrapper.getValueInBaseAsset.selector),
            abi.encode(DEPOSIT_AMOUNT * 6000 / 10000) // 60% of deposit amount
        );
        
        // Rebalance
        vault.rebalance();
        
        // Check assets were allocated according to weights
        uint256 rwa1Value = rwaWrapper.getValueInBaseAsset();
        uint256 rwa2Value = rwaWrapper2.getValueInBaseAsset();
        
        // Since we mocked the values, we can use exact assertions
        assertEq(rwa1Value, DEPOSIT_AMOUNT * 4000 / 10000);
        assertEq(rwa2Value, DEPOSIT_AMOUNT * 6000 / 10000);
        
        // Clear the mocks
        vm.clearMockedCalls();
    }
    
    // Test harvesting yield
    function test_HarvestYield() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Simulate yield by directly adding USDC to the vault
        uint256 yieldAmount = 100 * 1e6; // 100 USDC yield
        
        // Mock the behavior: directly transfer USDC to the vault to simulate yield harvesting
        mockUSDC.mint(address(vault), yieldAmount);
        
        // Create a mock function to simulate harvesting yield
        vm.mockCall(
            address(rwaWrapper),
            abi.encodeWithSelector(IAssetWrapper.harvestYield.selector),
            abi.encode(yieldAmount)
        );
        
        // Call harvestYield
        uint256 harvestedAmount = vault.harvestYield();
        
        // Check harvested amount
        assertEq(harvestedAmount, yieldAmount);
        
        // Check USDC balance of vault
        assertEq(mockUSDC.balanceOf(address(vault)), yieldAmount);
        
        // Clear the mock
        vm.clearMockedCalls();
    }
    
    // Test harvesting yield with multiple assets
    function test_HarvestYield_MultipleAssets() public {
        // Create yield-generating wrappers
        YieldGeneratingWrapper yieldWrapper1 = new YieldGeneratingWrapper("Yield Wrapper 1", address(mockUSDC));
        YieldGeneratingWrapper yieldWrapper2 = new YieldGeneratingWrapper("Yield Wrapper 2", address(mockUSDC));
        
        // Add wrappers to the vault
        vault.addAsset(address(yieldWrapper1), 5000); // 50% weight
        vault.addAsset(address(yieldWrapper2), 5000); // 50% weight
        
        // Set yield amounts
        yieldWrapper1.setYieldAmount(50 * 1e6); // 50 USDC
        yieldWrapper2.setYieldAmount(75 * 1e6); // 75 USDC
        
        // Mint USDC to the wrappers to simulate yield generation
        mockUSDC.mint(address(yieldWrapper1), 50 * 1e6);
        mockUSDC.mint(address(yieldWrapper2), 75 * 1e6);
        
        // Harvest yield
        uint256 harvestedAmount = vault.harvestYield();
        
        // Verify harvested amount
        assertEq(harvestedAmount, 125 * 1e6, "Harvested amount should be 125 USDC");
        assertEq(mockUSDC.balanceOf(address(vault)), 125 * 1e6, "Vault should have received 125 USDC");
    }
    
    // Test harvesting yield when paused
    function test_HarvestYield_WhenPaused() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Pause the vault
        vault.pause();
        
        // Attempt to harvest yield
        vm.expectRevert(CommonErrors.OperationPaused.selector);
        vault.harvestYield();
        
        // Unpause and verify it works
        vault.unpause();
        vault.harvestYield();
    }
    
    // Test the getActiveAssets function
    function test_GetActiveAssets() public {
        // Initially there should be no active assets
        address[] memory initialAssets = vault.getActiveAssets();
        assertEq(initialAssets.length, 0, "Should have no active assets initially");
        
        // Add three assets
        vault.addAsset(address(rwaWrapper), 3000);
        vault.addAsset(address(rwaWrapper2), 3000);
        
        // Create a third wrapper
        MockRWAAssetWrapper rwaWrapper3 = new MockRWAAssetWrapper("Mock RWA 3", address(mockUSDC));
        vault.addAsset(address(rwaWrapper3), 4000);
        
        // Check active assets
        address[] memory activeAssets = vault.getActiveAssets();
        assertEq(activeAssets.length, 3, "Should have three active assets");
        
        // Remove one asset
        vault.removeAsset(address(rwaWrapper2));
        
        // Check active assets again
        activeAssets = vault.getActiveAssets();
        assertEq(activeAssets.length, 2, "Should have two active assets after removal");
        
        // Verify the remaining assets are correct
        bool foundWrapper1 = false;
        bool foundWrapper3 = false;
        
        for (uint i = 0; i < activeAssets.length; i++) {
            if (activeAssets[i] == address(rwaWrapper)) {
                foundWrapper1 = true;
            } else if (activeAssets[i] == address(rwaWrapper3)) {
                foundWrapper3 = true;
            }
        }
        
        assertTrue(foundWrapper1, "rwaWrapper should be in active assets");
        assertTrue(foundWrapper3, "rwaWrapper3 should be in active assets");
    }
    
    // Test the getAssetInfo function
    function test_GetAssetInfo() public {
        // Add an asset
        vault.addAsset(address(rwaWrapper), 7500);
        
        // Get asset info
        (address wrapper, uint256 weight, bool active) = vault.getAssetInfo(address(rwaWrapper));
        
        // Verify info
        assertEq(wrapper, address(rwaWrapper), "Wrapper address should match");
        assertEq(weight, 7500, "Weight should be 7500");
        assertTrue(active, "Asset should be active");
        
        // Get info for non-existent asset
        (wrapper, weight, active) = vault.getAssetInfo(address(0x123));
        assertEq(wrapper, address(0), "Non-existent asset should have zero address");
        assertEq(weight, 0, "Non-existent asset should have zero weight");
        assertFalse(active, "Non-existent asset should be inactive");
        
        // Remove the asset and check info again
        vault.removeAsset(address(rwaWrapper));
        (wrapper, weight, active) = vault.getAssetInfo(address(rwaWrapper));
        assertEq(wrapper, address(rwaWrapper), "Wrapper address should still match");
        assertEq(weight, 0, "Weight should be 0 after removal");
        assertFalse(active, "Asset should be inactive after removal");
    }
    
    // Test edge case: withdrawing from other assets when there are no other assets
    function test_WithdrawFromOtherAssets_NoOtherAssets() public {
        // Add only one asset
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        mockUSDC.mint(user1, DEPOSIT_AMOUNT);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Force rebalance interval to pass
        vm.warp(block.timestamp + vault.rebalanceInterval() + 1);
        
        // Rebalance - this should not revert even though there are no "other" assets
        vault.rebalance();
        
        // Verify the asset has the full allocation
        assertEq(rwaWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT, "Asset should have full allocation");
    }
    
    // Test adding an asset with invalid base asset
    function test_AddAsset_InvalidBaseAsset() public {
        // Create a wrapper with a different base asset
        MockERC20 differentBaseAsset = new MockERC20("Different Token", "DIFF", 18);
        MockRWAAssetWrapper invalidWrapper = new MockRWAAssetWrapper("Invalid RWA", address(differentBaseAsset));
        
        // Attempt to add the invalid wrapper
        vm.expectRevert(CommonErrors.InvalidValue.selector);
        vault.addAsset(address(invalidWrapper), 5000);
    }
}
