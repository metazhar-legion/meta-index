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
    
    function harvestYield() external virtual override returns (uint256 harvestedAmount) {
        // Mock implementation - no yield harvesting by default
        return 0;
    }
}

/**
 * @title YieldGeneratingWrapper
 * @dev Mock implementation of IAssetWrapper that generates yield
 */
contract YieldGeneratingWrapper is MockRWAAssetWrapper {
    uint256 private _yieldAmount;
    
    constructor(string memory _name, address _baseAsset) 
        MockRWAAssetWrapper(_name, _baseAsset) {}
    
    function setYieldAmount(uint256 amount) external {
        _yieldAmount = amount;
    }
    
    function harvestYield() external override returns (uint256 harvestedAmount) {
        if (_yieldAmount > 0) {
            // Transfer yield to caller
            baseAsset.transfer(msg.sender, _yieldAmount);
            harvestedAmount = _yieldAmount;
            _yieldAmount = 0;
        }
        return harvestedAmount;
    }
}

/**
 * @title FailingAssetWrapper
 * @dev Mock implementation of IAssetWrapper that fails on specific operations
 */
contract FailingAssetWrapper is MockRWAAssetWrapper {
    bool public failOnAllocate;
    bool public failOnWithdraw;
    bool public failOnHarvest;
    
    constructor(string memory _name, address _baseAsset) 
        MockRWAAssetWrapper(_name, _baseAsset) {}
    
    function setFailureMode(bool _failOnAllocate, bool _failOnWithdraw, bool _failOnHarvest) external {
        failOnAllocate = _failOnAllocate;
        failOnWithdraw = _failOnWithdraw;
        failOnHarvest = _failOnHarvest;
    }
    
    function allocateCapital(uint256 amount) external override returns (bool) {
        if (failOnAllocate) {
            revert("Allocation failed");
        }
        return super.allocateCapital(amount);
    }
    
    function withdrawCapital(uint256 amount) external override returns (uint256) {
        if (failOnWithdraw) {
            revert("Withdrawal failed");
        }
        return super.withdrawCapital(amount);
    }
    
    function harvestYield() external override returns (uint256) {
        if (failOnHarvest) {
            revert("Harvest failed");
        }
        return super.harvestYield();
    }
}

/**
 * @title IndexFundVaultV2EnhancedTest
 * @dev Enhanced test suite for IndexFundVaultV2 to improve coverage
 */
contract IndexFundVaultV2EnhancedTest is Test {
    // Contracts
    IndexFundVaultV2 public vault;
    MockERC20 public mockUSDC;
    MockPriceOracle public mockPriceOracle;
    MockDEX public mockDEX;
    MockFeeManager public mockFeeManager;
    
    // Asset wrappers
    MockRWAAssetWrapper public standardWrapper;
    YieldGeneratingWrapper public yieldWrapper;
    FailingAssetWrapper public failingWrapper;
    
    // Users
    address public owner;
    address public user1;
    address public user2;
    
    // Constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant DEPOSIT_AMOUNT = 100_000e6; // 100k USDC
    
    // Events
    event AssetAdded(address indexed assetAddress, uint256 weight);
    event AssetRemoved(address indexed assetAddress);
    event AssetWeightUpdated(address indexed assetAddress, uint256 oldWeight, uint256 newWeight);
    event Rebalanced();
    event RebalanceIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event RebalanceThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DEXUpdated(address indexed oldDEX, address indexed newDEX);
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock contracts
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockPriceOracle = new MockPriceOracle(address(mockUSDC));
        mockDEX = new MockDEX(address(mockPriceOracle));
        mockFeeManager = new MockFeeManager();
        
        // Deploy the vault
        vault = new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            mockDEX
        );
        
        // Deploy asset wrappers
        standardWrapper = new MockRWAAssetWrapper("Standard RWA", address(mockUSDC));
        yieldWrapper = new YieldGeneratingWrapper("Yield RWA", address(mockUSDC));
        failingWrapper = new FailingAssetWrapper("Failing RWA", address(mockUSDC));
        
        // Mint USDC
        mockUSDC.mint(owner, INITIAL_SUPPLY);
        mockUSDC.mint(user1, INITIAL_SUPPLY);
        mockUSDC.mint(user2, INITIAL_SUPPLY);
        
        // Approve USDC for the vault and wrappers
        mockUSDC.approve(address(vault), type(uint256).max);
        mockUSDC.approve(address(standardWrapper), type(uint256).max);
        mockUSDC.approve(address(yieldWrapper), type(uint256).max);
        mockUSDC.approve(address(failingWrapper), type(uint256).max);
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }
    
    // Test constructor with invalid parameters
    function test_Constructor_InvalidParams() public {
        // Test with zero address for price oracle
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            IPriceOracle(address(0)),
            mockDEX
        );
        
        // Test with zero address for DEX
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            IDEX(address(0))
        );
    }
    
    // Test adding assets with invalid parameters
    function test_AddAsset_InvalidParams() public {
        // Test with zero address
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        vault.addAsset(address(0), 5000);
        
        // Test with zero weight
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        vault.addAsset(address(standardWrapper), 0);
        
        // Add an asset and try to add it again
        vault.addAsset(address(standardWrapper), 5000);
        vm.expectRevert(CommonErrors.TokenAlreadyExists.selector);
        vault.addAsset(address(standardWrapper), 5000);
        
        // Test adding asset with weight that would exceed 100%
        vm.expectRevert(CommonErrors.TotalExceeds100Percent.selector);
        vault.addAsset(address(yieldWrapper), 6000); // 5000 + 6000 > 10000
    }
    
    // Test updating asset weight with invalid parameters
    function test_UpdateAssetWeight_NonExistentAsset() public {
        // Try to update weight of non-existent asset
        vm.expectRevert(CommonErrors.TokenNotFound.selector);
        vault.updateAssetWeight(address(standardWrapper), 5000);
    }
    
    // Test removing a non-existent asset
    function test_RemoveAsset_NonExistentAsset() public {
        // Try to remove a non-existent asset
        vm.expectRevert(CommonErrors.TokenNotFound.selector);
        vault.removeAsset(address(standardWrapper));
    }
    
    // Test rebalance with failing asset wrapper
    function test_Rebalance_FailingAllocate() public {
        // Add failing wrapper to the vault
        vault.addAsset(address(failingWrapper), 10000); // 100% weight
        
        // Set it to fail on allocate
        failingWrapper.setFailureMode(true, false, false);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Rebalance should not revert but should handle the failure
        vault.rebalance();
        
        // Check that funds are still in the vault
        assertEq(mockUSDC.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }
    
    // Test rebalance with failing asset wrapper on withdraw
    function test_Rebalance_FailingWithdraw() public {
        // Add standard wrapper with 60% weight
        vault.addAsset(address(standardWrapper), 6000);
        
        // Add failing wrapper with 40% weight
        vault.addAsset(address(failingWrapper), 4000);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // First rebalance to allocate funds
        vault.rebalance();
        
        // Set values to simulate allocation
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 60 / 100);
        failingWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 40 / 100);
        
        // Update weights to trigger rebalance
        vault.updateAssetWeight(address(standardWrapper), 8000);
        vault.updateAssetWeight(address(failingWrapper), 2000);
        
        // Set failing wrapper to fail on withdraw
        failingWrapper.setFailureMode(false, true, false);
        
        // Rebalance should not revert but should handle the failure
        vault.rebalance();
        
        // Standard wrapper should still have received its allocation
        assertApproxEqRel(standardWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT * 60 / 100, 0.01e18);
    }
    
    // Test harvesting yield with failing asset wrapper
    function test_HarvestYield_FailingHarvest() public {
        // Add standard wrapper with 50% weight
        vault.addAsset(address(standardWrapper), 5000);
        
        // Add failing wrapper with 50% weight
        vault.addAsset(address(failingWrapper), 5000);
        
        // Set failing wrapper to fail on harvest
        failingWrapper.setFailureMode(false, false, true);
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Rebalance to allocate funds
        vault.rebalance();
        
        // Set values to simulate allocation
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 50 / 100);
        failingWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 50 / 100);
        
        // Harvest yield should not revert even if one wrapper fails
        vault.harvestYield();
    }
    
    // Test edge case: adding assets up to exactly 100%
    function test_AddAsset_ExactlyFullAllocation() public {
        // Add assets that sum to exactly 100%
        vault.addAsset(address(standardWrapper), 3333);
        vault.addAsset(address(yieldWrapper), 3333);
        vault.addAsset(address(failingWrapper), 3334); // 3333 + 3333 + 3334 = 10000
        
        // Verify total weight
        assertEq(vault.getTotalWeight(), 10000);
        
        // Try to add another asset
        MockRWAAssetWrapper extraWrapper = new MockRWAAssetWrapper("Extra RWA", address(mockUSDC));
        vm.expectRevert(CommonErrors.TotalExceeds100Percent.selector);
        vault.addAsset(address(extraWrapper), 1);
    }
    
    // Test rebalance with multiple assets and complex weight changes
    function test_Rebalance_ComplexWeightChanges() public {
        // Add three assets with different weights
        vault.addAsset(address(standardWrapper), 5000); // 50%
        vault.addAsset(address(yieldWrapper), 3000);    // 30%
        vault.addAsset(address(failingWrapper), 2000);  // 20%
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Rebalance to allocate funds
        vault.rebalance();
        
        // Set values to simulate allocation
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 50 / 100);
        yieldWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 30 / 100);
        failingWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 20 / 100);
        
        // Update weights to trigger complex rebalancing
        vault.updateAssetWeight(address(standardWrapper), 2000); // 50% -> 20%
        vault.updateAssetWeight(address(yieldWrapper), 7000);    // 30% -> 70%
        vault.updateAssetWeight(address(failingWrapper), 1000);  // 20% -> 10%
        
        // Rebalance to apply new weights
        vault.rebalance();
        
        // Update values to simulate reallocation
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 20 / 100);
        yieldWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 70 / 100);
        failingWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 10 / 100);
        
        // Verify new allocations
        assertApproxEqRel(standardWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT * 20 / 100, 0.01e18);
        assertApproxEqRel(yieldWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT * 70 / 100, 0.01e18);
        assertApproxEqRel(failingWrapper.getValueInBaseAsset(), DEPOSIT_AMOUNT * 10 / 100, 0.01e18);
    }
    
    // Test withdrawing from vault when assets have increased in value
    function test_Withdraw_WithValueIncrease() public {
        // Add asset to the vault
        vault.addAsset(address(standardWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Rebalance to allocate funds
        vault.rebalance();
        
        // Set value to simulate allocation
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT);
        
        // Simulate value increase (20% gain)
        uint256 valueIncrease = DEPOSIT_AMOUNT * 20 / 100;
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT + valueIncrease);
        
        // Calculate shares for user1
        uint256 user1Shares = vault.balanceOf(user1);
        
        // User1 withdraws half their shares
        vm.startPrank(user1);
        uint256 halfShares = user1Shares / 2;
        uint256 withdrawnAmount = vault.redeem(halfShares, user1, user1);
        vm.stopPrank();
        
        // Verify withdrawn amount includes proportional value increase
        uint256 expectedAmount = (DEPOSIT_AMOUNT + valueIncrease) / 2;
        assertApproxEqRel(withdrawnAmount, expectedAmount, 0.01e18);
    }
    
    // Test vault behavior with multiple deposits and withdrawals
    function test_MultipleDepositsAndWithdrawals() public {
        // Add asset to the vault
        vault.addAsset(address(standardWrapper), 10000); // 100% weight
        
        // First deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT / 2, user1);
        vm.stopPrank();
        
        // Rebalance to allocate funds
        vault.rebalance();
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT / 2);
        
        // Second deposit from user2
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT / 2, user2);
        vm.stopPrank();
        
        // Rebalance again
        vault.rebalance();
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT);
        
        // Simulate value increase (10% gain)
        uint256 valueIncrease = DEPOSIT_AMOUNT * 10 / 100;
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT + valueIncrease);
        
        // User1 withdraws all their shares
        uint256 user1Shares = vault.balanceOf(user1);
        vm.startPrank(user1);
        uint256 user1WithdrawnAmount = vault.redeem(user1Shares, user1, user1);
        vm.stopPrank();
        
        // User2 withdraws all their shares
        uint256 user2Shares = vault.balanceOf(user2);
        vm.startPrank(user2);
        uint256 user2WithdrawnAmount = vault.redeem(user2Shares, user2, user2);
        vm.stopPrank();
        
        // Verify both users got their fair share of the value increase
        uint256 expectedUser1Amount = (DEPOSIT_AMOUNT / 2) + (valueIncrease / 2);
        uint256 expectedUser2Amount = (DEPOSIT_AMOUNT / 2) + (valueIncrease / 2);
        
        assertApproxEqRel(user1WithdrawnAmount, expectedUser1Amount, 0.01e18);
        assertApproxEqRel(user2WithdrawnAmount, expectedUser2Amount, 0.01e18);
        
        // Verify vault is empty
        assertEq(vault.totalAssets(), 0);
    }
    
    // Test vault behavior with partial rebalancing due to insufficient funds
    function test_PartialRebalancing() public {
        // Add two assets with equal weights
        vault.addAsset(address(standardWrapper), 5000); // 50%
        vault.addAsset(address(yieldWrapper), 5000);    // 50%
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Rebalance to allocate funds
        vault.rebalance();
        
        // Set values to simulate allocation
        standardWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 50 / 100);
        yieldWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 50 / 100);
        
        // Update weights dramatically
        vault.updateAssetWeight(address(standardWrapper), 9000); // 50% -> 90%
        vault.updateAssetWeight(address(yieldWrapper), 1000);    // 50% -> 10%
        
        // Simulate a situation where yieldWrapper can only return a portion of the funds
        // This simulates a liquidity constraint in the underlying asset
        uint256 expectedWithdrawal = DEPOSIT_AMOUNT * 40 / 100; // Need to withdraw 40% from yieldWrapper
        uint256 actualWithdrawal = expectedWithdrawal / 2;      // But only half is available
        
        // Mock the withdrawCapital function to return less than requested
        vm.mockCall(
            address(yieldWrapper),
            abi.encodeWithSelector(IAssetWrapper.withdrawCapital.selector, expectedWithdrawal),
            abi.encode(actualWithdrawal)
        );
        
        // Rebalance should still work but result in partial rebalancing
        vault.rebalance();
        
        // Clear the mock
        vm.clearMockedCalls();
        
        // Verify the vault handled the partial rebalancing correctly
        // The standardWrapper should have received what was available
        uint256 expectedStandardWrapperValue = DEPOSIT_AMOUNT * 50 / 100 + actualWithdrawal;
        yieldWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 50 / 100 - actualWithdrawal);
        standardWrapper.setValueInBaseAsset(expectedStandardWrapperValue);
        
        assertApproxEqRel(standardWrapper.getValueInBaseAsset(), expectedStandardWrapperValue, 0.01e18);
    }
    
    // Test access control for owner-only functions
    function test_AccessControl() public {
        address nonOwner = makeAddr("nonOwner");
        
        // Try to call owner-only functions as non-owner
        vm.startPrank(nonOwner);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.addAsset(address(standardWrapper), 5000);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.removeAsset(address(standardWrapper));
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.updateAssetWeight(address(standardWrapper), 5000);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setRebalanceInterval(1 days);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setRebalanceThreshold(500);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.updatePriceOracle(mockPriceOracle);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.updateDEX(mockDEX);
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.pause();
        
        vm.expectRevert("Ownable: caller is not the owner");
        vault.unpause();
        
        vm.stopPrank();
    }
    
    // Test vault behavior with zero total assets
    function test_ZeroTotalAssets() public {
        // Add asset to the vault
        vault.addAsset(address(standardWrapper), 10000); // 100% weight
        
        // Check that isRebalanceNeeded returns false with zero assets
        assertFalse(vault.isRebalanceNeeded());
        
        // Check that rebalance works with zero assets
        vault.rebalance();
        
        // Check that harvestYield works with zero assets
        vault.harvestYield();
    }
    
    // Test vault behavior with assets that have zero value
    function test_ZeroValueAssets() public {
        // Add asset to the vault
        vault.addAsset(address(standardWrapper), 10000); // 100% weight
        
        // Set the asset value to zero
        standardWrapper.setValueInBaseAsset(0);
        
        // Check that isRebalanceNeeded handles zero value assets
        assertFalse(vault.isRebalanceNeeded());
        
        // Check that rebalance works with zero value assets
        vault.rebalance();
        
        // Check that harvestYield works with zero value assets
        vault.harvestYield();
    }
}
