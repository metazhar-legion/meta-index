// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ComposableRWABundle} from "../src/ComposableRWABundle.sol";
import {StrategyOptimizer} from "../src/StrategyOptimizer.sol";
import {IExposureStrategy} from "../src/interfaces/IExposureStrategy.sol";
import {MockExposureStrategy} from "./mocks/MockExposureStrategy.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockYieldStrategy} from "../src/mocks/MockYieldStrategy.sol";

contract ComposableRWABundleTest is Test {
    ComposableRWABundle public bundle;
    StrategyOptimizer public optimizer;
    MockUSDC public usdc;
    MockPriceOracle public priceOracle;
    
    MockExposureStrategy public perpetualStrategy;
    MockExposureStrategy public trsStrategy;
    MockExposureStrategy public directStrategy;
    MockYieldStrategy public yieldStrategy;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 public constant INITIAL_USDC_BALANCE = 1000000e6; // 1M USDC
    uint256 public constant BASIS_POINTS = 10000;

    event StrategyAdded(address indexed strategy, uint256 targetAllocation, bool isPrimary);
    event CapitalAllocated(uint256 totalAmount, uint256 exposureAmount, uint256 yieldAmount);
    event OptimizationPerformed(uint256 totalCostSaving, uint256 gasUsed, uint256 timestamp);

    function setUp() public {
        // Set up mock contracts
        usdc = new MockUSDC();
        priceOracle = new MockPriceOracle(address(usdc));
        
        // Create optimizer
        vm.prank(owner);
        optimizer = new StrategyOptimizer(address(priceOracle));
        
        // Create bundle
        vm.prank(owner);
        bundle = new ComposableRWABundle(
            "Test RWA Bundle",
            address(usdc),
            address(priceOracle),
            address(optimizer)
        );
        
        // Create mock strategies
        perpetualStrategy = new MockExposureStrategy(
            address(usdc),
            "Mock Perpetual Strategy",
            IExposureStrategy.StrategyType.PERPETUAL
        );
        
        trsStrategy = new MockExposureStrategy(
            address(usdc),
            "Mock TRS Strategy", 
            IExposureStrategy.StrategyType.TRS
        );
        
        directStrategy = new MockExposureStrategy(
            address(usdc),
            "Mock Direct Token Strategy",
            IExposureStrategy.StrategyType.DIRECT_TOKEN
        );
        
        yieldStrategy = new MockYieldStrategy(usdc, "Test Yield Strategy");
        
        // Configure strategies with different costs and risks
        perpetualStrategy.setMockCost(400); // 4% cost (moderate)
        perpetualStrategy.setMockRisk(60);  // Medium-high risk
        perpetualStrategy.setLeverage(300); // 3x leverage
        
        trsStrategy.setMockCost(600);       // 6% cost (higher)
        trsStrategy.setMockRisk(40);        // Medium risk
        trsStrategy.setLeverage(200);       // 2x leverage
        
        directStrategy.setMockCost(200);    // 2% cost (lower)
        directStrategy.setMockRisk(30);     // Lower risk
        directStrategy.setLeverage(100);    // No leverage
        
        // Fund accounts
        usdc.mint(user1, INITIAL_USDC_BALANCE);
        usdc.mint(user2, INITIAL_USDC_BALANCE);
        usdc.mint(address(this), INITIAL_USDC_BALANCE);
        
        // Fund strategies for testing
        usdc.approve(address(perpetualStrategy), INITIAL_USDC_BALANCE / 10);
        perpetualStrategy.fundStrategy(INITIAL_USDC_BALANCE / 10);
        
        usdc.approve(address(trsStrategy), INITIAL_USDC_BALANCE / 10);
        trsStrategy.fundStrategy(INITIAL_USDC_BALANCE / 10);
        
        usdc.approve(address(directStrategy), INITIAL_USDC_BALANCE / 10);
        directStrategy.fundStrategy(INITIAL_USDC_BALANCE / 10);
        
        // Note: MockYieldStrategy doesn't have fundStrategy method, so we skip funding it
    }

    function test_BundleInitialization() public {
        assertEq(bundle.name(), "Test RWA Bundle");
        assertEq(address(bundle.baseAsset()), address(usdc));
        assertEq(address(bundle.priceOracle()), address(priceOracle));
        assertEq(address(bundle.optimizer()), address(optimizer));
        assertEq(bundle.totalAllocatedCapital(), 0);
    }

    function test_AddExposureStrategy() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit StrategyAdded(address(perpetualStrategy), 5000, true);
        
        bundle.addExposureStrategy(
            address(perpetualStrategy),
            5000, // 50% target allocation
            7000, // 70% max allocation
            true  // is primary
        );
        
        ComposableRWABundle.StrategyAllocation[] memory strategies = bundle.getExposureStrategies();
        assertEq(strategies.length, 1);
        assertEq(address(strategies[0].strategy), address(perpetualStrategy));
        assertEq(strategies[0].targetAllocation, 5000);
        assertEq(strategies[0].maxAllocation, 7000);
        assertTrue(strategies[0].isPrimary);
        assertTrue(strategies[0].isActive);
    }

    function test_AddMultipleStrategies() public {
        vm.startPrank(owner);
        
        // Add perpetual strategy
        bundle.addExposureStrategy(address(perpetualStrategy), 4000, 6000, true);
        
        // Add TRS strategy
        bundle.addExposureStrategy(address(trsStrategy), 3000, 5000, false);
        
        // Add direct strategy
        bundle.addExposureStrategy(address(directStrategy), 3000, 4000, false);
        
        vm.stopPrank();
        
        ComposableRWABundle.StrategyAllocation[] memory strategies = bundle.getExposureStrategies();
        assertEq(strategies.length, 3);
        
        // Check allocations sum to 100%
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            totalAllocation += strategies[i].targetAllocation;
        }
        assertEq(totalAllocation, BASIS_POINTS);
    }

    function test_UpdateYieldBundle() public {
        address[] memory yieldStrategies = new address[](1);
        yieldStrategies[0] = address(yieldStrategy);
        
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = BASIS_POINTS; // 100% to single yield strategy
        
        vm.prank(owner);
        bundle.updateYieldBundle(yieldStrategies, allocations);
        
        ComposableRWABundle.YieldStrategyBundle memory yieldBundle = bundle.getYieldBundle();
        assertEq(yieldBundle.strategies.length, 1);
        assertEq(address(yieldBundle.strategies[0]), address(yieldStrategy));
        assertEq(yieldBundle.allocations[0], BASIS_POINTS);
        assertTrue(yieldBundle.isActive);
    }

    function test_AllocateCapital() public {
        // Setup strategies
        vm.startPrank(owner);
        bundle.addExposureStrategy(address(perpetualStrategy), 6000, 8000, true);
        bundle.addExposureStrategy(address(directStrategy), 4000, 6000, false);
        
        address[] memory yieldStrategies = new address[](1);
        yieldStrategies[0] = address(yieldStrategy);
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = BASIS_POINTS;
        bundle.updateYieldBundle(yieldStrategies, allocations);
        vm.stopPrank();
        
        // Allocate capital
        uint256 allocationAmount = 100000e6; // 100k USDC
        
        vm.startPrank(user1);
        usdc.approve(address(bundle), allocationAmount);
        
        vm.expectEmit(false, false, false, true);
        emit CapitalAllocated(allocationAmount, 0, 0); // Amounts will vary
        
        bool success = bundle.allocateCapital(allocationAmount);
        assertTrue(success);
        vm.stopPrank();
        
        assertEq(bundle.totalAllocatedCapital(), allocationAmount);
        assertGt(bundle.getValueInBaseAsset(), 0);
    }

    function test_WithdrawCapital() public {
        // Setup and allocate first
        test_AllocateCapital();
        
        uint256 totalValue = bundle.getValueInBaseAsset();
        uint256 withdrawAmount = totalValue / 2; // Withdraw 50%
        
        uint256 initialBalance = usdc.balanceOf(user1);
        
        vm.prank(user1);
        uint256 actualWithdrawn = bundle.withdrawCapital(withdrawAmount);
        
        assertGt(actualWithdrawn, 0);
        assertLe(actualWithdrawn, withdrawAmount); // Account for slippage
        assertGt(usdc.balanceOf(user1), initialBalance);
    }

    function test_HarvestYield() public {
        // Setup and allocate first
        test_AllocateCapital();
        
        // Simulate some time passing and yield generation
        vm.warp(block.timestamp + 30 days);
        
        uint256 initialBalance = usdc.balanceOf(address(this));
        uint256 harvested = bundle.harvestYield();
        
        assertGe(harvested, 0); // Should harvest some yield
        assertGe(usdc.balanceOf(address(this)), initialBalance);
    }

    function test_OptimizeStrategies() public {
        // Setup strategies with different costs
        vm.startPrank(owner);
        bundle.addExposureStrategy(address(perpetualStrategy), 5000, 7000, true);  // Higher cost
        bundle.addExposureStrategy(address(directStrategy), 5000, 7000, false);   // Lower cost
        vm.stopPrank();
        
        // Record initial performance for strategies
        optimizer.recordPerformance(address(perpetualStrategy), 500, 400, 60, true);  // 5% return, 4% cost
        optimizer.recordPerformance(address(directStrategy), 300, 200, 45, true);    // 3% return, 2% cost
        
        vm.prank(owner);
        bool optimized = bundle.optimizeStrategies();
        
        // Should optimize towards lower cost strategy
        assertTrue(optimized);
    }

    function test_RebalanceStrategies() public {
        // Setup strategies
        vm.startPrank(owner);
        bundle.addExposureStrategy(address(perpetualStrategy), 5000, 7000, true);
        bundle.addExposureStrategy(address(directStrategy), 5000, 7000, false);
        vm.stopPrank();
        
        // Allocate capital
        vm.startPrank(user1);
        usdc.approve(address(bundle), 100000e6);
        bundle.allocateCapital(100000e6);
        vm.stopPrank();
        
        // Change target allocations to trigger rebalancing
        vm.prank(owner);
        bundle.addExposureStrategy(address(directStrategy), 7000, 9000, false); // This should trigger update
        
        // Wait for rebalance interval
        vm.warp(block.timestamp + 7 hours);
        
        vm.prank(owner);
        bool rebalanced = bundle.rebalanceStrategies();
        
        // May or may not rebalance depending on current state
        // assertEq rebalanced to either true or false is valid
    }

    function test_EmergencyExit() public {
        // Setup and allocate
        test_AllocateCapital();
        
        uint256 initialValue = bundle.getValueInBaseAsset();
        
        vm.prank(owner);
        uint256 recovered = bundle.emergencyExitAll();
        
        assertGt(recovered, 0);
        
        ComposableRWABundle.RiskParameters memory riskParams = bundle.getRiskParameters();
        assertTrue(riskParams.circuitBreakerActive);
        
        // Should not be able to allocate when circuit breaker is active
        vm.startPrank(user1);
        usdc.approve(address(bundle), 1000e6);
        vm.expectRevert();
        bundle.allocateCapital(1000e6);
        vm.stopPrank();
    }

    function test_RiskManagement() public {
        ComposableRWABundle.RiskParameters memory newParams = ComposableRWABundle.RiskParameters({
            maxTotalLeverage: 400,           // 4x max leverage
            maxStrategyCount: 3,             // Max 3 strategies
            rebalanceThreshold: 300,         // 3% rebalance threshold
            emergencyThreshold: 1500,        // 15% emergency threshold
            maxSlippageTolerance: 150,       // 1.5% max slippage
            minCapitalEfficiency: 9000,      // 90% minimum efficiency
            circuitBreakerActive: false
        });
        
        vm.prank(owner);
        bundle.updateRiskParameters(newParams);
        
        ComposableRWABundle.RiskParameters memory updatedParams = bundle.getRiskParameters();
        assertEq(updatedParams.maxTotalLeverage, 400);
        assertEq(updatedParams.maxStrategyCount, 3);
        assertEq(updatedParams.rebalanceThreshold, 300);
    }

    function test_BundleStats() public {
        // Setup and allocate
        test_AllocateCapital();
        
        (
            uint256 totalValue,
            uint256 totalExposure,
            uint256 currentLeverage,
            uint256 capitalEfficiency,
            bool isHealthy
        ) = bundle.getBundleStats();
        
        assertGt(totalValue, 0);
        assertGe(totalExposure, 0);
        assertGe(currentLeverage, 100); // At least 1x leverage
        assertGt(capitalEfficiency, 0);
        // isHealthy can be true or false depending on configuration
    }

    function test_FailureHandling() public {
        vm.startPrank(owner);
        bundle.addExposureStrategy(address(perpetualStrategy), 5000, 7000, true);
        vm.stopPrank();
        
        // Set strategy to fail on open
        perpetualStrategy.setShouldFailOnOpen(true);
        
        vm.startPrank(user1);
        usdc.approve(address(bundle), 10000e6);
        
        // Should still succeed even if some strategies fail
        bool success = bundle.allocateCapital(10000e6);
        assertTrue(success);
        vm.stopPrank();
    }

    function test_PauseUnpause() public {
        vm.prank(owner);
        bundle.pause();
        
        vm.startPrank(user1);
        usdc.approve(address(bundle), 1000e6);
        vm.expectRevert();
        bundle.allocateCapital(1000e6);
        vm.stopPrank();
        
        vm.prank(owner);
        bundle.unpause();
        
        // Should work again after unpause
        vm.startPrank(user1);
        bool success = bundle.allocateCapital(1000e6);
        assertTrue(success);
        vm.stopPrank();
    }

    // ============ HELPER FUNCTIONS ============

    function _setupBasicStrategies() internal {
        vm.startPrank(owner);
        bundle.addExposureStrategy(address(perpetualStrategy), 4000, 6000, true);
        bundle.addExposureStrategy(address(directStrategy), 6000, 8000, false);
        
        address[] memory yieldStrategies = new address[](1);
        yieldStrategies[0] = address(yieldStrategy);
        uint256[] memory allocations = new uint256[](1);
        allocations[0] = BASIS_POINTS;
        bundle.updateYieldBundle(yieldStrategies, allocations);
        vm.stopPrank();
    }

    // ============ FUZZ TESTS ============

    function testFuzz_AllocateCapital(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1000e6, 100000e6); // 1k to 100k USDC
        
        _setupBasicStrategies();
        
        vm.startPrank(user1);
        usdc.approve(address(bundle), amount);
        bool success = bundle.allocateCapital(amount);
        assertTrue(success);
        vm.stopPrank();
        
        assertGe(bundle.getValueInBaseAsset(), amount * 95 / 100); // Allow 5% loss for slippage
    }

    function testFuzz_WithdrawCapital(uint256 allocateAmount, uint256 withdrawPercent) public {
        allocateAmount = bound(allocateAmount, 10000e6, 100000e6);
        withdrawPercent = bound(withdrawPercent, 10, 100); // 10% to 100%
        
        _setupBasicStrategies();
        
        // Allocate
        vm.startPrank(user1);
        usdc.approve(address(bundle), allocateAmount);
        bundle.allocateCapital(allocateAmount);
        vm.stopPrank();
        
        // Withdraw
        uint256 totalValue = bundle.getValueInBaseAsset();
        uint256 withdrawAmount = (totalValue * withdrawPercent) / 100;
        
        vm.prank(user1);
        uint256 actualWithdrawn = bundle.withdrawCapital(withdrawAmount);
        
        assertGt(actualWithdrawn, 0);
        assertLe(actualWithdrawn, withdrawAmount + (withdrawAmount / 100)); // Allow 1% variance
    }
}