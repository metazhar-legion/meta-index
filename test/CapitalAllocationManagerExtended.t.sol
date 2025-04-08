// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CapitalAllocationManager} from "../src/CapitalAllocationManager.sol";
import {ICapitalAllocationManager} from "../src/interfaces/ICapitalAllocationManager.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {IRWASyntheticToken} from "../src/interfaces/IRWASyntheticToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

// Import existing mocks from CapitalAllocationManager.t.sol
import {MockYieldStrategy, MockRWASyntheticToken} from "./CapitalAllocationManager.t.sol";

// Malicious yield strategy that attempts reentrancy
contract ReentrantYieldStrategy is MockYieldStrategy {
    CapitalAllocationManager public target;
    bool public shouldReenter;
    
    constructor(address _baseAsset) MockYieldStrategy(_baseAsset) {}
    
    function setTarget(address _target) external {
        target = CapitalAllocationManager(_target);
    }
    
    function setShouldReenter(bool _shouldReenter) external {
        shouldReenter = _shouldReenter;
    }
    
    function deposit(uint256 amount) external override returns (uint256 shares) {
        baseAsset.transferFrom(msg.sender, address(this), amount);
        shares = amount; // 1:1 for simplicity
        _balances[msg.sender] += shares;
        totalShares += shares;
        totalValue += amount;
        
        // Attempt reentrancy attack
        if (shouldReenter && address(target) != address(0)) {
            target.rebalance();
        }
        
        return shares;
    }
    
    function withdraw(uint256 shares) external override returns (uint256 amount) {
        require(_balances[msg.sender] >= shares, "Insufficient shares");
        amount = (shares * totalValue) / totalShares;
        _balances[msg.sender] -= shares;
        totalShares -= shares;
        totalValue -= amount;
        baseAsset.transfer(msg.sender, amount);
        
        // Attempt reentrancy attack
        if (shouldReenter && address(target) != address(0)) {
            target.rebalance();
        }
        
        return amount;
    }
}

// Malicious RWA token that attempts reentrancy
contract ReentrantRWAToken is MockRWASyntheticToken {
    CapitalAllocationManager public target;
    bool public shouldReenter;
    
    constructor(address _baseAsset) MockRWASyntheticToken(_baseAsset) {}
    
    function setTarget(address _target) external {
        target = CapitalAllocationManager(_target);
    }
    
    function setShouldReenter(bool _shouldReenter) external {
        shouldReenter = _shouldReenter;
    }
    
    function mint(address to, uint256 amount) external override returns (bool) {
        baseAsset.transferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        
        // Attempt reentrancy attack
        if (shouldReenter && address(target) != address(0)) {
            target.rebalance();
        }
        
        return true;
    }
    
    function burn(address from, uint256 amount) external override returns (bool) {
        _burn(from, amount);
        baseAsset.transfer(msg.sender, amount);
        
        // Attempt reentrancy attack
        if (shouldReenter && address(target) != address(0)) {
            target.rebalance();
        }
        
        return true;
    }
}

// Mock ERC20 that can fail transfers
contract FailingERC20 is MockToken {
    bool public shouldFailTransfers;
    bool public shouldFailApprovals;
    bool public shouldFailTransferFroms;
    
    constructor(string memory name, string memory symbol, uint8 decimals) 
        MockToken(name, symbol, decimals) {}
    
    function setShouldFailTransfers(bool _shouldFail) external {
        shouldFailTransfers = _shouldFail;
    }
    
    function setShouldFailApprovals(bool _shouldFail) external {
        shouldFailApprovals = _shouldFail;
    }
    
    function setShouldFailTransferFroms(bool _shouldFail) external {
        shouldFailTransferFroms = _shouldFail;
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransfers) {
            return false;
        }
        return super.transfer(to, amount);
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        if (shouldFailApprovals) {
            return false;
        }
        return super.approve(spender, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransferFroms) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

contract CapitalAllocationManagerExtendedTest is Test {
    CapitalAllocationManager public manager;
    FailingERC20 public baseAsset;
    MockYieldStrategy public yieldStrategy1;
    MockYieldStrategy public yieldStrategy2;
    MockRWASyntheticToken public rwaToken1;
    MockRWASyntheticToken public rwaToken2;
    ReentrantYieldStrategy public reentrantStrategy;
    ReentrantRWAToken public reentrantToken;
    
    address public owner = address(1);
    address public user = address(2);
    address public attacker = address(3);
    
    uint256 public constant BASIS_POINTS = 10000;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy base asset
        baseAsset = new FailingERC20("Base Asset", "BASE", 18);
        
        // Deploy CapitalAllocationManager
        manager = new CapitalAllocationManager(address(baseAsset));
        
        // Deploy yield strategies
        yieldStrategy1 = new MockYieldStrategy(address(baseAsset));
        yieldStrategy2 = new MockYieldStrategy(address(baseAsset));
        
        // Deploy RWA tokens
        rwaToken1 = new MockRWASyntheticToken(address(baseAsset));
        rwaToken2 = new MockRWASyntheticToken(address(baseAsset));
        
        // Deploy malicious contracts
        reentrantStrategy = new ReentrantYieldStrategy(address(baseAsset));
        reentrantStrategy.setTarget(address(manager));
        
        reentrantToken = new ReentrantRWAToken(address(baseAsset));
        reentrantToken.setTarget(address(manager));
        
        // Mint base asset to manager
        baseAsset.mint(address(manager), 1_000_000 * 10**18);
        
        // Mint base asset to attacker
        baseAsset.mint(attacker, 1_000_000 * 10**18);
        
        vm.stopPrank();
    }
    
    // Test reentrancy protection with malicious yield strategy
    function test_ReentrancyProtectionYieldStrategy() public {
        vm.startPrank(owner);
        
        // Add the reentrant strategy
        manager.addYieldStrategy(address(reentrantStrategy), 10000);
        
        // Set allocation to 0% RWA, 90% yield, 10% buffer
        manager.setAllocation(0, 9000, 1000);
        
        // Enable reentrancy attack
        reentrantStrategy.setShouldReenter(true);
        
        // Attempt rebalance - should not be vulnerable to reentrancy
        manager.rebalance();
        
        // Verify state is consistent
        uint256 totalValue = manager.getTotalValue();
        uint256 yieldValue = manager.getYieldValue();
        uint256 bufferValue = manager.getLiquidityBufferValue();
        
        // Allow for small rounding errors
        assertApproxEqRel(yieldValue, totalValue * 9000 / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(bufferValue, totalValue * 1000 / BASIS_POINTS, 0.01e18);
        
        vm.stopPrank();
    }
    
    // Test reentrancy protection with malicious RWA token
    function test_ReentrancyProtectionRWAToken() public {
        vm.startPrank(owner);
        
        // Add the reentrant token
        manager.addRWAToken(address(reentrantToken), 10000);
        
        // Set allocation to 90% RWA, 0% yield, 10% buffer
        manager.setAllocation(9000, 0, 1000);
        
        // Enable reentrancy attack
        reentrantToken.setShouldReenter(true);
        
        // Attempt rebalance - should not be vulnerable to reentrancy
        manager.rebalance();
        
        // Verify state is consistent
        uint256 totalValue = manager.getTotalValue();
        uint256 rwaValue = manager.getRWAValue();
        uint256 bufferValue = manager.getLiquidityBufferValue();
        
        // Allow for small rounding errors
        assertApproxEqRel(rwaValue, totalValue * 9000 / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(bufferValue, totalValue * 1000 / BASIS_POINTS, 0.01e18);
        
        vm.stopPrank();
    }
    
    // Test handling of failed token transfers
    function test_FailedTokenTransfers() public {
        vm.startPrank(owner);
        
        // Add yield strategy
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        
        // Set allocation to 0% RWA, 90% yield, 10% buffer
        manager.setAllocation(0, 9000, 1000);
        
        // Make transfers fail
        baseAsset.setShouldFailTransfers(true);
        
        // Attempt rebalance - should handle failed transfers gracefully
        manager.rebalance();
        
        // Reset transfer behavior
        baseAsset.setShouldFailTransfers(false);
        
        vm.stopPrank();
    }
    
    // Test handling of failed token approvals
    function test_FailedTokenApprovals() public {
        vm.startPrank(owner);
        
        // Add yield strategy
        manager.addYieldStrategy(address(yieldStrategy1), 10000);
        
        // Set allocation to 0% RWA, 90% yield, 10% buffer
        manager.setAllocation(0, 9000, 1000);
        
        // Make approvals fail
        baseAsset.setShouldFailApprovals(true);
        
        // Attempt rebalance - should handle failed approvals gracefully
        manager.rebalance();
        
        // Reset approval behavior
        baseAsset.setShouldFailApprovals(false);
        
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
    
    // Test with zero percentage allocations
    function test_ZeroPercentageAllocations() public {
        vm.startPrank(owner);
        
        // Add yield strategies with 0% allocation (should fail)
        vm.expectRevert("Percentage must be positive");
        manager.addYieldStrategy(address(yieldStrategy1), 0);
        
        // Add RWA token with 0% allocation (should fail)
        vm.expectRevert("Percentage must be positive");
        manager.addRWAToken(address(rwaToken1), 0);
        
        // Add valid allocations
        manager.addYieldStrategy(address(yieldStrategy1), 5000);
        manager.addRWAToken(address(rwaToken1), 5000);
        
        // Update to 0% (should fail)
        vm.expectRevert("Percentage must be positive");
        manager.updateYieldStrategy(address(yieldStrategy1), 0);
        
        vm.expectRevert("Percentage must be positive");
        manager.updateRWAToken(address(rwaToken1), 0);
        
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
    
    // Test with very large number of strategies and tokens
    function test_LargeNumberOfStrategiesAndTokens() public {
        vm.startPrank(owner);
        
        // Add multiple yield strategies (10 in this case)
        uint256 strategyCount = 10;
        MockYieldStrategy[] memory strategies = new MockYieldStrategy[](strategyCount);
        
        for (uint256 i = 0; i < strategyCount; i++) {
            strategies[i] = new MockYieldStrategy(address(baseAsset));
            manager.addYieldStrategy(address(strategies[i]), 10000 / strategyCount);
        }
        
        // Add multiple RWA tokens (10 in this case)
        uint256 tokenCount = 10;
        MockRWASyntheticToken[] memory tokens = new MockRWASyntheticToken[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = new MockRWASyntheticToken(address(baseAsset));
            manager.addRWAToken(address(tokens[i]), 10000 / tokenCount);
        }
        
        // Set allocation
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
    
    // Test handling of inactive strategies and tokens during rebalance
    function test_InactiveStrategiesAndTokensDuringRebalance() public {
        vm.startPrank(owner);
        
        // Add yield strategies
        manager.addYieldStrategy(address(yieldStrategy1), 5000);
        manager.addYieldStrategy(address(yieldStrategy2), 5000);
        
        // Add RWA tokens
        manager.addRWAToken(address(rwaToken1), 5000);
        manager.addRWAToken(address(rwaToken2), 5000);
        
        // Set allocation
        manager.setAllocation(4000, 5000, 1000);
        
        // Initial rebalance
        manager.rebalance();
        
        // Remove one strategy and one token
        manager.removeYieldStrategy(address(yieldStrategy1));
        manager.removeRWAToken(address(rwaToken1));
        
        // Rebalance again
        manager.rebalance();
        
        // Verify only active strategies and tokens were used
        ICapitalAllocationManager.StrategyAllocation[] memory strategies = manager.getYieldStrategies();
        ICapitalAllocationManager.RWAAllocation[] memory tokens = manager.getRWATokens();
        
        assertEq(strategies.length, 1);
        assertEq(tokens.length, 1);
        
        vm.stopPrank();
    }
    
    // Test external attack vectors
    function test_ExternalAttackVectors() public {
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
        assertApproxEqRel(rwaValue, totalValue * rwaPercentage / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(yieldValue, totalValue * yieldPercentage / BASIS_POINTS, 0.01e18);
        assertApproxEqRel(bufferValue, totalValue * bufferPercentage / BASIS_POINTS, 0.01e18);
        
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
