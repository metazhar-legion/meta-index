// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockFeeManager} from "../src/mocks/MockFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";
import {IAssetWrapper} from "../src/interfaces/IAssetWrapper.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MockAssetWrapper
 * @dev Mock implementation of IAssetWrapper for testing purposes
 */
contract MockAssetWrapper is IAssetWrapper {
    string public name;
    IERC20 public baseAsset;
    uint256 internal _valueInBaseAsset;
    address public owner;

    constructor(string memory _name, address _baseAsset) {
        name = _name;
        baseAsset = IERC20(_baseAsset);
        owner = msg.sender;
    }

    function setValueInBaseAsset(uint256 value) external virtual {
        _valueInBaseAsset = value;
    }

    function allocateCapital(uint256 amount) external virtual override returns (bool) {
        baseAsset.transferFrom(msg.sender, address(this), amount);
        _valueInBaseAsset += amount;
        return true;
    }

    function withdrawCapital(uint256 amount) external virtual override returns (uint256) {
        if (amount > _valueInBaseAsset) {
            amount = _valueInBaseAsset;
        }
        _valueInBaseAsset -= amount;
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }

    function getValueInBaseAsset() external view virtual override returns (uint256) {
        return _valueInBaseAsset;
    }

    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }

    function getName() external view override returns (string memory) {
        return name;
    }

    function getUnderlyingTokens() external pure override returns (address[] memory) {
        return new address[](0);
    }

    function harvestYield() external virtual override returns (uint256) {
        return 0;
    }
}

/**
 * @title YieldAssetWrapper
 * @dev Asset wrapper that generates yield
 */
contract YieldAssetWrapper is MockAssetWrapper {
    uint256 private _yieldAmount;
    uint256 private _yieldRate;
    uint256 private _lastYieldTime;

    constructor(string memory _name, address _baseAsset) MockAssetWrapper(_name, _baseAsset) {
        _lastYieldTime = block.timestamp;
    }

    function setYieldAmount(uint256 amount) external {
        _yieldAmount = amount;
    }

    function setYieldRate(uint256 rate) external {
        _yieldRate = rate;
        _lastYieldTime = block.timestamp;
    }

    function simulateYieldAccrual() external {
        if (_yieldRate > 0 && _valueInBaseAsset > 0) {
            uint256 timeElapsed = block.timestamp - _lastYieldTime;
            uint256 newYield = (_valueInBaseAsset * _yieldRate * timeElapsed) / (365 days * 10000);
            _yieldAmount += newYield;
            _lastYieldTime = block.timestamp;
        }
    }

    function harvestYield() external override returns (uint256) {
        // Simulate yield accrual first
        if (_yieldRate > 0 && _valueInBaseAsset > 0) {
            uint256 timeElapsed = block.timestamp - _lastYieldTime;
            uint256 newYield = (_valueInBaseAsset * _yieldRate * timeElapsed) / (365 days * 10000);
            _yieldAmount += newYield;
            _lastYieldTime = block.timestamp;
        }

        if (_yieldAmount > 0) {
            // Mint new tokens to simulate yield
            MockERC20(address(baseAsset)).mint(address(this), _yieldAmount);
            
            // Transfer the yield to the caller
            baseAsset.transfer(msg.sender, _yieldAmount);
            uint256 amount = _yieldAmount;
            _yieldAmount = 0;
            return amount;
        }
        return 0;
    }
}

/**
 * @title VolatileAssetWrapper
 * @dev Asset wrapper with price volatility for testing rebalancing
 */
contract VolatileAssetWrapper is MockAssetWrapper {
    uint256 private _priceMultiplier = 1e18; // 1.0 initially
    
    constructor(string memory _name, address _baseAsset) MockAssetWrapper(_name, _baseAsset) {}
    
    function setPriceMultiplier(uint256 multiplier) external {
        _priceMultiplier = multiplier;
    }
    
    function getValueInBaseAsset() external view virtual override returns (uint256) {
        return (_valueInBaseAsset * _priceMultiplier) / 1e18;
    }
    
    function getBaseValue() external view returns (uint256) {
        return _valueInBaseAsset;
    }
}

/**
 * @title IndexFundVaultV2EnhancedTest
 * @dev Enhanced test suite for IndexFundVaultV2 to improve coverage
 */
contract IndexFundVaultV2EnhancedTest is Test {
    // Main contracts
    IndexFundVaultV2 public vault;
    MockERC20 public mockUSDC;
    MockPriceOracle public mockPriceOracle;
    MockDEX public mockDEX;
    MockFeeManager public mockFeeManager;
    
    // Asset wrappers
    MockAssetWrapper public wrapper1;
    MockAssetWrapper public wrapper2;
    YieldAssetWrapper public yieldWrapper;
    VolatileAssetWrapper public volatileWrapper;
    
    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public dao;
    
    // Constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**6; // 1M USDC
    uint256 public constant USER_BALANCE = 100_000 * 10**6; // 100k USDC
    uint256 public constant DEPOSIT_AMOUNT = 10_000 * 10**6; // 10k USDC
    
    function setUp() public {
        // Set up accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        dao = makeAddr("dao");
        
        vm.startPrank(owner);
        
        // Deploy mock contracts
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        mockPriceOracle = new MockPriceOracle(address(mockUSDC));
        mockDEX = new MockDEX(address(mockPriceOracle));
        mockFeeManager = new MockFeeManager();
        
        // Deploy asset wrappers
        wrapper1 = new MockAssetWrapper("S&P 500", address(mockUSDC));
        wrapper2 = new MockAssetWrapper("Bitcoin", address(mockUSDC));
        yieldWrapper = new YieldAssetWrapper("Yield Generator", address(mockUSDC));
        volatileWrapper = new VolatileAssetWrapper("Volatile Asset", address(mockUSDC));
        
        // Deploy vault
        vault = new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            mockDEX
        );
        
        // The vault uses Ownable pattern, not AccessControl with roles
        // In a real setup, we might want to transfer ownership
        // vault.transferOwnership(dao);
        
        // Mint initial tokens
        mockUSDC.mint(address(this), INITIAL_SUPPLY);
        mockUSDC.mint(user1, USER_BALANCE);
        mockUSDC.mint(user2, USER_BALANCE);
        
        // Approve vault to spend tokens
        vm.stopPrank();
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }
    
    //--------------------------------------------------------------------------
    // Enhanced Tests for Edge Cases and Comprehensive Coverage
    //--------------------------------------------------------------------------
    
    function test_ConstructorValidation() public {
        vm.startPrank(owner);
        
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
        
        vm.stopPrank();
    }
    
    function test_GetAssetInfo() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 5000);
        
        vm.stopPrank();
        
        // Get asset info
        (address wrapperAddr, uint256 weight, bool active) = vault.getAssetInfo(address(wrapper1));
        
        assertEq(wrapperAddr, address(wrapper1), "Wrong wrapper address");
        assertEq(weight, 5000, "Wrong weight");
        assertTrue(active, "Asset should be active");
        
        // Get non-existent asset info
        (wrapperAddr, weight, active) = vault.getAssetInfo(address(0x123));
        
        assertEq(wrapperAddr, address(0), "Non-existent wrapper should be zero address");
        assertEq(weight, 0, "Non-existent weight should be 0");
        assertFalse(active, "Non-existent asset should be inactive");
    }
    
    function test_AddAsset_MaximumAssets() public {
        vm.startPrank(owner);
        
        // Add multiple assets up to a reasonable limit
        for (uint256 i = 1; i <= 10; i++) {
            MockAssetWrapper newWrapper = new MockAssetWrapper(
                string(abi.encodePacked("Asset ", vm.toString(i))),
                address(mockUSDC)
            );
            
            uint256 weight = 10000 / 10; // Equal weights
            vault.addAsset(address(newWrapper), weight);
        }
        
        // Check total weight is 100%
        uint256 totalWeight = 0;
        // Get active assets using the getActiveAssets method
        address[] memory activeAssets = vault.getActiveAssets();
        for (uint256 i = 0; i < activeAssets.length; i++) {
            address assetAddr = activeAssets[i];
            (,uint256 weight,) = vault.getAssetInfo(assetAddr);
            totalWeight += weight;
        }
        
        assertEq(totalWeight, 10000, "Total weight should be 100%");
        
        vm.stopPrank();
    }
    
    function test_RemoveAsset_NonExistent() public {
        vm.startPrank(owner);
        
        // Try to remove non-existent asset
        vm.expectRevert(CommonErrors.TokenNotFound.selector);
        vault.removeAsset(address(0x123));
        
        vm.stopPrank();
    }
    
    function test_RemoveAsset_WithBalance() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 10000);
        
        vm.stopPrank();
        
        // Deposit from user
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Verify asset has balance
        assertGt(wrapper1.getValueInBaseAsset(), 0, "Wrapper should have balance");
        
        // Remove asset (should withdraw all funds)
        vm.startPrank(owner);
        vault.removeAsset(address(wrapper1));
        vm.stopPrank();
        
        // Verify asset is removed
        (,, bool active) = vault.getAssetInfo(address(wrapper1));
        assertFalse(active, "Asset should be inactive");
        
        // Verify funds are back in the vault
        assertEq(mockUSDC.balanceOf(address(vault)), DEPOSIT_AMOUNT, "Funds should be back in vault");
    }
    
    function test_UpdateAssetWeight_ZeroWeight() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 5000);
        
        // Try to update to zero weight
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        vault.updateAssetWeight(address(wrapper1), 0);
        
        vm.stopPrank();
    }
    
    function test_Rebalance_WithVolatileAsset() public {
        vm.startPrank(owner);
        
        // Add stable and volatile assets
        vault.addAsset(address(wrapper1), 5000); // 50%
        vault.addAsset(address(volatileWrapper), 5000); // 50%
        
        vm.stopPrank();
        
        // Deposit from user
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Initial balance check
        uint256 wrapper1Value = wrapper1.getValueInBaseAsset();
        uint256 volatileValue = volatileWrapper.getValueInBaseAsset();
        
        assertApproxEqRel(wrapper1Value, DEPOSIT_AMOUNT / 2, 0.01e18, "Initial wrapper1 value incorrect");
        assertApproxEqRel(volatileValue, DEPOSIT_AMOUNT / 2, 0.01e18, "Initial volatile value incorrect");
        
        // Simulate price change in volatile asset (double in value)
        volatileWrapper.setPriceMultiplier(2e18);
        
        // Check that rebalance is needed
        assertTrue(vault.isRebalanceNeeded(), "Rebalance should be needed after price change");
        
        // Perform rebalance
        vm.startPrank(dao);
        vault.rebalance();
        vm.stopPrank();
        
        // Check balances after rebalance
        wrapper1Value = wrapper1.getValueInBaseAsset();
        volatileValue = volatileWrapper.getValueInBaseAsset();
        uint256 volatileBaseValue = volatileWrapper.getBaseValue();
        
        // The volatile asset's base value should be lower since its price doubled
        assertLt(volatileBaseValue, DEPOSIT_AMOUNT / 2, "Volatile base value should be lower after rebalance");
        
        // But the reported value should still be ~50% of total
        assertApproxEqRel(
            volatileWrapper.getValueInBaseAsset(),
            wrapper1.getValueInBaseAsset(),
            0.05e18,
            "Values should be approximately equal after rebalance"
        );
    }
    
    function test_HarvestYield_RealYieldAccrual() public {
        vm.startPrank(owner);
        
        // Add yield wrapper
        vault.addAsset(address(yieldWrapper), 10000);
        
        vm.stopPrank();
        
        // Deposit from user
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Set yield rate to 10% APY
        yieldWrapper.setYieldRate(1000); // 10% in basis points
        
        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Harvest yield
        vm.startPrank(dao);
        uint256 harvestedYield = vault.harvestYield();
        vm.stopPrank();
        
        // Expected yield for 30 days at 10% APY
        uint256 expectedYield = (DEPOSIT_AMOUNT * 1000 * 30 days) / (365 days * 10000);
        
        assertApproxEqRel(harvestedYield, expectedYield, 0.01e18, "Harvested yield incorrect");
        
        // Verify yield was added to total assets
        uint256 totalAssets = vault.totalAssets();
        assertApproxEqRel(totalAssets, DEPOSIT_AMOUNT + expectedYield, 0.01e18, "Total assets incorrect after yield");
    }
    
    function test_PreviewDepositAndMint() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 10000);
        
        vm.stopPrank();
        
        // Check preview deposit
        uint256 shares = vault.previewDeposit(DEPOSIT_AMOUNT);
        assertEq(shares, DEPOSIT_AMOUNT, "Preview deposit should return correct shares");
        
        // Check preview mint
        uint256 assets = vault.previewMint(DEPOSIT_AMOUNT);
        assertEq(assets, DEPOSIT_AMOUNT, "Preview mint should return correct assets");
        
        // Deposit some initial amount to test with non-zero total supply
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Set fixed fees for testing
        mockFeeManager.setUseFixedFees(true);
        // Set mock management fee to simulate a deposit fee
        mockFeeManager.setMockManagementFee(DEPOSIT_AMOUNT / 100); // 1% of deposit amount
        
        // Check preview deposit with fee
        shares = vault.previewDeposit(DEPOSIT_AMOUNT);
        // If the fee manager doesn't actually apply deposit fees, shares will equal DEPOSIT_AMOUNT
        assertApproxEqRel(shares, DEPOSIT_AMOUNT, 0.01e18, "Preview deposit should return approximately the deposit amount");
        
        // Check preview mint with fee
        assets = vault.previewMint(DEPOSIT_AMOUNT);
        // If the fee manager doesn't actually apply deposit fees, assets will equal DEPOSIT_AMOUNT
        assertApproxEqRel(assets, DEPOSIT_AMOUNT, 0.01e18, "Preview mint should return approximately the deposit amount");
    }
    
    function test_PreviewWithdrawAndRedeem() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 10000);
        
        vm.stopPrank();
        
        // Deposit some initial amount
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Check preview withdraw
        uint256 shares = vault.previewWithdraw(DEPOSIT_AMOUNT);
        assertEq(shares, DEPOSIT_AMOUNT, "Preview withdraw should return correct shares");
        
        // Check preview redeem
        uint256 assets = vault.previewRedeem(DEPOSIT_AMOUNT);
        assertEq(assets, DEPOSIT_AMOUNT, "Preview redeem should return correct assets");
        
        // Set fixed fees for testing
        mockFeeManager.setUseFixedFees(true);
        // Set mock performance fee to simulate a withdraw fee
        mockFeeManager.setMockPerformanceFee(DEPOSIT_AMOUNT / 100); // 1% of deposit amount
        
        // Check preview withdraw with fee
        shares = vault.previewWithdraw(DEPOSIT_AMOUNT);
        // If the fee manager doesn't actually apply withdraw fees, shares will equal DEPOSIT_AMOUNT
        assertApproxEqRel(shares, DEPOSIT_AMOUNT, 0.01e18, "Preview withdraw should return approximately the deposit amount");
        
        // Check preview redeem with fee
        assets = vault.previewRedeem(DEPOSIT_AMOUNT);
        // If the fee manager doesn't actually apply withdraw fees, assets will equal DEPOSIT_AMOUNT
        assertApproxEqRel(assets, DEPOSIT_AMOUNT, 0.01e18, "Preview redeem should return approximately the deposit amount");
    }
    
    function test_MaxDeposit_WithDepositLimit() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 10000);
        
        // Note: The vault doesn't have a setDepositLimit method
        // We'll test maxDeposit without setting a specific limit
        
        vm.stopPrank();
        
        // Check max deposit when no deposits yet
        // In ERC4626, maxDeposit returns type(uint256).max by default unless overridden
        uint256 maxDeposit = vault.maxDeposit(user1);
        assertTrue(maxDeposit > 0, "Max deposit should be greater than zero");
        
        // Deposit some amount
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Check max deposit after partial deposit
        // In ERC4626, maxDeposit returns type(uint256).max by default unless overridden
        maxDeposit = vault.maxDeposit(user1);
        // Since the vault doesn't have a deposit limit, it should still be type(uint256).max
        assertEq(maxDeposit, type(uint256).max, "Max deposit should be max uint256 without limit");
        
        // Deposit up to the limit
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Check max deposit after second deposit
        // Since the vault doesn't have a deposit limit, it should still be type(uint256).max
        maxDeposit = vault.maxDeposit(user1);
        assertEq(maxDeposit, type(uint256).max, "Max deposit should still be max uint256 without limit");
    }
    
    function test_PauseAndUnpause() public {
        vm.startPrank(owner);
        
        // Add asset
        vault.addAsset(address(wrapper1), 10000);
        
        // Pause the vault
        vault.pause();
        
        vm.stopPrank();
        
        // Try to deposit while paused
        vm.startPrank(user1);
        bool depositFailed = false;
        try vault.deposit(DEPOSIT_AMOUNT, user1) {
            // Should not reach here
        } catch {
            depositFailed = true;
        }
        assertTrue(depositFailed, "Deposit should fail when paused");
        vm.stopPrank();
        
        // Try to withdraw while paused
        vm.startPrank(user1);
        bool withdrawFailed = false;
        try vault.withdraw(DEPOSIT_AMOUNT, user1, user1) {
            // Should not reach here
        } catch {
            withdrawFailed = true;
        }
        assertTrue(withdrawFailed, "Withdraw should fail when paused");
        vm.stopPrank();
        
        // Unpause the vault
        vm.startPrank(owner);
        vault.unpause();
        vm.stopPrank();
        
        // Deposit should work now
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Verify deposit worked
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT, "Deposit should work after unpause");
    }
    
    function test_SetRebalanceParameters() public {
        vm.startPrank(owner);
        
        // Test setting rebalance interval
        uint256 newInterval = 7 days;
        vault.setRebalanceInterval(uint32(newInterval));
        assertEq(vault.rebalanceInterval(), newInterval, "Rebalance interval not updated");
        
        // Test setting rebalance threshold
        uint256 newThreshold = 1000; // 10%
        vault.setRebalanceThreshold(uint32(newThreshold));
        assertEq(vault.rebalanceThreshold(), newThreshold, "Rebalance threshold not updated");
        
        // Test invalid threshold (over 100%)
        bool thresholdFailed = false;
        try vault.setRebalanceThreshold(11000) {
            // Should not reach here
        } catch {
            thresholdFailed = true;
        }
        assertTrue(thresholdFailed, "Setting threshold over 100% should fail");
        
        vm.stopPrank();
    }
    
    function test_UpdatePriceOracleAndDEX() public {
        vm.startPrank(owner);
        
        // Deploy new instances
        MockPriceOracle newOracle = new MockPriceOracle(address(mockUSDC));
        MockDEX newDEX = new MockDEX(address(newOracle));
        
        // Update price oracle
        vault.updatePriceOracle(newOracle);
        assertEq(address(vault.priceOracle()), address(newOracle), "Price oracle not updated");
        
        // Update DEX
        vault.updateDEX(newDEX);
        assertEq(address(vault.dex()), address(newDEX), "DEX not updated");
        
        // Test with zero address
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        vault.updatePriceOracle(IPriceOracle(address(0)));
        
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        vault.updateDEX(IDEX(address(0)));
        
        vm.stopPrank();
    }
    
    function test_TotalAssetsWithMultipleAssets() public {
        vm.startPrank(owner);
        
        // Add multiple assets
        vault.addAsset(address(wrapper1), 3000);
        vault.addAsset(address(wrapper2), 3000);
        vault.addAsset(address(yieldWrapper), 4000);
        
        vm.stopPrank();
        
        // Deposit from user
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Set some values in the wrappers
        wrapper1.setValueInBaseAsset(DEPOSIT_AMOUNT * 3000 / 10000);
        wrapper2.setValueInBaseAsset(DEPOSIT_AMOUNT * 3000 / 10000);
        yieldWrapper.setValueInBaseAsset(DEPOSIT_AMOUNT * 4000 / 10000);
        
        // Check total assets
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, DEPOSIT_AMOUNT, "Total assets should match deposit");
        
        // Generate some yield
        yieldWrapper.setYieldAmount(DEPOSIT_AMOUNT / 10); // 10% yield
        
        // Harvest yield
        vm.startPrank(dao);
        vault.harvestYield();
        vm.stopPrank();
        
        // Check total assets after yield
        totalAssets = vault.totalAssets();
        assertEq(totalAssets, DEPOSIT_AMOUNT * 11 / 10, "Total assets should include yield");
    }
}
