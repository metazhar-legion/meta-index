// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CapitalAllocationManager} from "../src/CapitalAllocationManager.sol";
import {ICapitalAllocationManager} from "../src/interfaces/ICapitalAllocationManager.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {IRWASyntheticToken} from "../src/interfaces/IRWASyntheticToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/**
 * @title BasicMockYieldStrategy
 * @dev A simple mock yield strategy for testing
 */
contract BasicMockYieldStrategy is ERC20, IYieldStrategy {
    IERC20 public baseAsset;
    uint256 public totalDeposited;
    bool public shouldRevert;
    
    constructor(address _baseAsset) ERC20("Mock Yield Strategy", "MYS") {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
    
    function deposit(uint256 amount) external returns (uint256 shares) {
        if (shouldRevert) revert("Deposit reverted");
        
        baseAsset.transferFrom(msg.sender, address(this), amount);
        shares = amount; // 1:1 for simplicity
        _mint(msg.sender, shares);
        totalDeposited += amount;
        return shares;
    }
    
    function withdraw(uint256 shares) external returns (uint256 amount) {
        if (shouldRevert) revert("Withdraw reverted");
        
        amount = shares; // 1:1 for simplicity
        _burn(msg.sender, shares);
        totalDeposited -= amount;
        baseAsset.transfer(msg.sender, amount);
        return amount;
    }
    
    function getValueOfShares(uint256 shares) public view returns (uint256) {
        return shares; // 1:1 for simplicity
    }
    
    function getTotalValue() public view returns (uint256) {
        return totalDeposited;
    }
    
    function getCurrentAPY() external pure returns (uint256) {
        return 500; // 5% APY
    }
    
    function getStrategyInfo() external view returns (IYieldStrategy.StrategyInfo memory) {
        return IYieldStrategy.StrategyInfo({
            name: "Mock Yield Strategy",
            asset: address(baseAsset),
            totalDeposited: totalDeposited,
            currentValue: totalDeposited,
            apy: 500,
            lastUpdated: block.timestamp,
            active: true,
            risk: 3
        });
    }
    
    function harvestYield() external pure returns (uint256) {
        return 0; // No yield for simplicity
    }
}

/**
 * @title BasicMockRWAToken
 * @dev A simple mock RWA token for testing
 */
contract BasicMockRWAToken is ERC20 {
    IERC20 public baseAsset;
    uint256 public price = 1e18; // 1:1 initially
    bool public shouldRevert;
    
    constructor(address _baseAsset) ERC20("Mock RWA Token", "MRWA") {
        baseAsset = IERC20(_baseAsset);
    }
    
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
    
    function setPrice(uint256 _price) external {
        price = _price;
    }
    
    function mint(address to, uint256 amount) external returns (bool) {
        if (shouldRevert) revert("Mint reverted");
        
        baseAsset.transferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        return true;
    }
    
    function burn(address from, uint256 amount) external returns (bool) {
        if (shouldRevert) revert("Burn reverted");
        
        require(balanceOf(from) >= amount, "Insufficient balance");
        _burn(from, amount);
        baseAsset.transfer(msg.sender, amount);
        return true;
    }
    
    function getCurrentPrice() external view returns (uint256) {
        return price;
    }
    
    function getAssetInfo() external view returns (IRWASyntheticToken.AssetInfo memory) {
        return IRWASyntheticToken.AssetInfo({
            name: "Mock RWA",
            symbol: "MRWA",
            assetType: IRWASyntheticToken.AssetType.OTHER,
            oracle: address(0),
            lastPrice: price,
            lastUpdated: block.timestamp,
            marketId: bytes32(0),
            isActive: true
        });
    }
    
    function updatePrice() external pure returns (bool) {
        return true;
    }
}

/**
 * @title CapitalAllocationManagerBasicSecurityTest
 * @dev Basic security tests for the CapitalAllocationManager
 */
contract CapitalAllocationManagerBasicSecurityTest is Test {
    CapitalAllocationManager public manager;
    MockToken public baseAsset;
    BasicMockYieldStrategy public yieldStrategy1;
    BasicMockYieldStrategy public yieldStrategy2;
    BasicMockRWAToken public rwaToken1;
    BasicMockRWAToken public rwaToken2;
    
    address public owner = address(1);
    address public user = address(2);
    address public attacker = address(3);
    
    uint256 public constant BASIS_POINTS = 10000;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy base asset
        baseAsset = new MockToken("Base Asset", "BASE", 18);
        
        // Deploy CapitalAllocationManager
        manager = new CapitalAllocationManager(address(baseAsset));
        
        // Deploy yield strategies
        yieldStrategy1 = new BasicMockYieldStrategy(address(baseAsset));
        yieldStrategy2 = new BasicMockYieldStrategy(address(baseAsset));
        
        // Deploy RWA tokens
        rwaToken1 = new BasicMockRWAToken(address(baseAsset));
        rwaToken2 = new BasicMockRWAToken(address(baseAsset));
        
        // Mint base asset to manager
        baseAsset.mint(address(manager), 1_000_000 * 10**18);
        
        // Mint base asset to attacker
        baseAsset.mint(attacker, 1_000_000 * 10**18);
        
        // Pre-approve tokens for tests
        vm.stopPrank();
        vm.startPrank(address(manager));
        baseAsset.approve(address(yieldStrategy1), type(uint256).max);
        baseAsset.approve(address(yieldStrategy2), type(uint256).max);
        baseAsset.approve(address(rwaToken1), type(uint256).max);
        baseAsset.approve(address(rwaToken2), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(owner);
        vm.stopPrank();
    }
    
    // Test basic allocation functionality
    function test_BasicAllocation() public {
        vm.startPrank(owner);
        
        // Add yield strategy and RWA token
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        manager.addRWAToken(address(rwaToken1), 10000);
        
        // Set allocation to 40% RWA, 50% yield, 10% buffer
        manager.setAllocation(4000, 5000, 1000);
        
        // Rebalance
        manager.rebalance();
        
        // Verify allocations
        uint256 totalValue = manager.getTotalValue();
        uint256 rwaValue = manager.getRWAValue();
        uint256 yieldValue = manager.getYieldValue();
        uint256 bufferValue = manager.getLiquidityBufferValue();
        
        // Allow for small rounding errors
        assertApproxEqRel(rwaValue, totalValue * 4000 / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(yieldValue, totalValue * 5000 / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(bufferValue, totalValue * 1000 / BASIS_POINTS, 0.01e18);
        
        vm.stopPrank();
    }
    
    // Test error handling for failed strategy operations
    function test_FailedStrategyOperations() public {
        vm.startPrank(owner);
        
        // Add yield strategy
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        
        // Set allocation to 0% RWA, 90% yield, 10% buffer
        manager.setAllocation(0, 9000, 1000);
        
        // Initial rebalance should succeed
        manager.rebalance();
        
        // Make strategy operations fail
        yieldStrategy1.setShouldRevert(true);
        
        // Rebalance should handle failures gracefully
        manager.rebalance();
        
        // Reset strategy behavior
        yieldStrategy1.setShouldRevert(false);
        
        vm.stopPrank();
    }
    
    // Test error handling for failed RWA token operations
    function test_FailedRWAOperations() public {
        vm.startPrank(owner);
        
        // Add RWA token
        manager.addRWAToken(address(rwaToken1), 10000);
        
        // Set allocation to 90% RWA, 0% yield, 10% buffer
        manager.setAllocation(9000, 0, 1000);
        
        // Initial rebalance should succeed
        manager.rebalance();
        
        // Make RWA operations fail
        rwaToken1.setShouldRevert(true);
        
        // Rebalance should handle failures gracefully
        manager.rebalance();
        
        // Reset RWA behavior
        rwaToken1.setShouldRevert(false);
        
        vm.stopPrank();
    }
    
    // Test access control
    function test_AccessControl() public {
        vm.startPrank(attacker);
        
        // Try to call owner-only functions
        vm.expectRevert();
        manager.setAllocation(3000, 6000, 1000);
        
        vm.expectRevert();
        manager.addYieldStrategy(address(yieldStrategy1), 5000);
        
        vm.expectRevert();
        manager.updateYieldStrategy(address(yieldStrategy1), 7000);
        
        vm.expectRevert();
        manager.removeYieldStrategy(address(yieldStrategy1));
        
        vm.expectRevert();
        manager.addRWAToken(address(rwaToken1), 5000);
        
        vm.expectRevert();
        manager.updateRWAToken(address(rwaToken1), 7000);
        
        vm.expectRevert();
        manager.removeRWAToken(address(rwaToken1));
        
        vm.expectRevert();
        manager.rebalance();
        
        vm.stopPrank();
    }
    
    // Test multiple strategy allocation
    function test_MultipleStrategyAllocation() public {
        vm.startPrank(owner);
        
        // Add multiple yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 7000);
        manager.addYieldStrategy(address(yieldStrategy2), 3000);
        
        // Set allocation to 0% RWA, 90% yield, 10% buffer
        manager.setAllocation(0, 9000, 1000);
        
        // Rebalance
        manager.rebalance();
        
        // Verify strategy allocations
        uint256 yieldValue = manager.getYieldValue();
        uint256 strategy1Value = yieldStrategy1.getTotalValue();
        uint256 strategy2Value = yieldStrategy2.getTotalValue();
        
        // Allow for small rounding errors
        assertApproxEqRel(strategy1Value, yieldValue * 7000 / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(strategy2Value, yieldValue * 3000 / BASIS_POINTS, 0.01e18);
        
        vm.stopPrank();
    }
    
    // Test multiple RWA token allocation
    function test_MultipleRWAAllocation() public {
        vm.startPrank(owner);
        
        // Add multiple RWA tokens
        manager.addRWAToken(address(rwaToken1), 6000);
        manager.addRWAToken(address(rwaToken2), 4000);
        
        // Set allocation to 90% RWA, 0% yield, 10% buffer
        manager.setAllocation(9000, 0, 1000);
        
        // Rebalance
        manager.rebalance();
        
        // Verify RWA allocations
        uint256 rwaValue = manager.getRWAValue();
        uint256 token1Value = rwaToken1.balanceOf(address(manager)) * rwaToken1.getCurrentPrice() / 1e18;
        uint256 token2Value = rwaToken2.balanceOf(address(manager)) * rwaToken2.getCurrentPrice() / 1e18;
        
        // Allow for small rounding errors
        assertApproxEqRel(token1Value, rwaValue * 6000 / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(token2Value, rwaValue * 4000 / BASIS_POINTS, 0.01e18);
        
        vm.stopPrank();
    }
    
    // Test extreme allocation changes
    function test_ExtremeAllocationChanges() public {
        vm.startPrank(owner);
        
        // Add yield strategy and RWA token
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        manager.addRWAToken(address(rwaToken1), 10000);
        
        // Initial allocation: 50% RWA, 40% yield, 10% buffer
        manager.setAllocation(5000, 4000, 1000);
        manager.rebalance();
        
        // Extreme change: 0% RWA, 90% yield, 10% buffer
        manager.setAllocation(0, 9000, 1000);
        manager.rebalance();
        
        // Verify all RWA tokens were withdrawn
        assertEq(manager.getRWAValue(), 0);
        
        // Extreme change: 90% RWA, 0% yield, 10% buffer
        manager.setAllocation(9000, 0, 1000);
        manager.rebalance();
        
        // Verify all yield strategies were withdrawn
        assertEq(manager.getYieldValue(), 0);
        
        vm.stopPrank();
    }
    
    // Test with very small allocations
    function test_VerySmallAllocations() public {
        vm.startPrank(owner);
        
        // Add yield strategy and RWA token with minimum allocation (1 basis point = 0.01%)
        manager.addYieldStrategy(address(yieldStrategy1), 1);
        manager.addRWAToken(address(rwaToken1), 1);
        
        // Set allocation with minimum values
        manager.setAllocation(1, 1, 9998);
        
        // Rebalance
        manager.rebalance();
        
        // Verify small allocations were handled correctly
        uint256 totalValue = manager.getTotalValue();
        uint256 rwaValue = manager.getRWAValue();
        uint256 yieldValue = manager.getYieldValue();
        
        // For very small allocations, we might have rounding to zero
        // Just verify they're not negative or unreasonably large
        assertTrue(rwaValue <= totalValue * 1 / BASIS_POINTS + 1);
        assertTrue(yieldValue <= totalValue * 1 / BASIS_POINTS + 1);
        
        vm.stopPrank();
    }
    
    // Fuzz test for allocation percentages
    function testFuzz_AllocationPercentages(
        uint256 rwaPercentage,
        uint256 yieldPercentage,
        uint256 bufferPercentage
    ) public {
        // Bound the values to reasonable ranges
        rwaPercentage = bound(rwaPercentage, 0, BASIS_POINTS);
        yieldPercentage = bound(yieldPercentage, 0, BASIS_POINTS);
        bufferPercentage = bound(bufferPercentage, 0, BASIS_POINTS);
        
        // Skip if percentages don't sum to 100%
        if (rwaPercentage + yieldPercentage + bufferPercentage != BASIS_POINTS) {
            return;
        }
        
        vm.startPrank(owner);
        
        // Add yield strategy and RWA token
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        manager.addRWAToken(address(rwaToken1), 10000);
        
        // Set allocation with fuzzed percentages
        bool success = manager.setAllocation(rwaPercentage, yieldPercentage, bufferPercentage);
        assertTrue(success);
        
        // Rebalance
        manager.rebalance();
        
        // Verify allocations
        uint256 totalValue = manager.getTotalValue();
        uint256 rwaValue = manager.getRWAValue();
        uint256 yieldValue = manager.getYieldValue();
        uint256 bufferValue = manager.getLiquidityBufferValue();
        
        // Allow for small rounding errors
        if (rwaPercentage > 0) {
            assertApproxEqRel(rwaValue, totalValue * rwaPercentage / BASIS_POINTS, 0.01e18);
        }
        if (yieldPercentage > 0) {
            assertApproxEqRel(yieldValue, totalValue * yieldPercentage / BASIS_POINTS, 0.01e18);
        }
        if (bufferPercentage > 0) {
            assertApproxEqRel(bufferValue, totalValue * bufferPercentage / BASIS_POINTS, 0.01e18);
        }
        
        vm.stopPrank();
    }
    
    // Fuzz test for strategy percentages
    function testFuzz_StrategyPercentages(uint256 strategy1Percentage) public {
        // Bound the value to reasonable range
        strategy1Percentage = bound(strategy1Percentage, 1, BASIS_POINTS);
        
        vm.startPrank(owner);
        
        // Add yield strategy with fuzzed percentage
        bool success = manager.addYieldStrategy(address(yieldStrategy1), strategy1Percentage);
        assertTrue(success);
        
        // If percentage is less than 100%, add another strategy
        if (strategy1Percentage < BASIS_POINTS) {
            uint256 strategy2Percentage = BASIS_POINTS - strategy1Percentage;
            success = manager.addYieldStrategy(address(yieldStrategy2), strategy2Percentage);
            assertTrue(success);
        }
        
        // Set allocation to focus on yield
        manager.setAllocation(0, 9000, 1000);
        
        // Rebalance
        manager.rebalance();
        
        // Verify strategy allocations
        uint256 yieldValue = manager.getYieldValue();
        uint256 strategy1Value = yieldStrategy1.getTotalValue();
        
        if (strategy1Percentage == BASIS_POINTS) {
            // If 100% allocation to strategy1, it should have all the yield value
            assertApproxEqRel(strategy1Value, yieldValue, 0.01e18);
        } else {
            // Otherwise, it should have its proportional share
            assertApproxEqRel(strategy1Value, yieldValue * strategy1Percentage / BASIS_POINTS, 0.01e18);
        }
        
        vm.stopPrank();
    }
}
