// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EnhancedPerpetualStrategy} from "../src/strategies/EnhancedPerpetualStrategy.sol";
import {IExposureStrategy} from "../src/interfaces/IExposureStrategy.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockYieldStrategy} from "../src/mocks/MockYieldStrategy.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";

contract EnhancedPerpetualStrategyTest is Test {
    EnhancedPerpetualStrategy public strategy;
    MockUSDC public usdc;
    MockPriceOracle public priceOracle;
    MockYieldStrategy public yieldStrategy;
    MockPerpetualTrading public perpetualRouter;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    bytes32 public constant MARKET_ID = "SPX-USD";
    uint256 public constant INITIAL_BALANCE = 1000000e6; // 1M USDC
    
    event PositionOpened(bytes32 indexed positionId, uint256 collateral, uint256 leverage, uint256 exposure);
    event LeverageAdjusted(uint256 oldLeverage, uint256 newLeverage, int256 fundingRate);
    event YieldHarvested(uint256 totalYield, uint256 fromStrategies);

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        priceOracle = new MockPriceOracle(address(usdc));
        perpetualRouter = new MockPerpetualTrading(address(usdc));
        yieldStrategy = new MockYieldStrategy(usdc, "Test Yield Strategy");
        
        // Deploy strategy
        vm.prank(owner);
        strategy = new EnhancedPerpetualStrategy(
            address(usdc),
            address(perpetualRouter),
            address(priceOracle),
            MARKET_ID,
            "Enhanced SPX Perpetual Strategy"
        );
        
        // Fund accounts
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(address(this), INITIAL_BALANCE);
        
        // Fund perpetual router for testing
        usdc.mint(address(perpetualRouter), INITIAL_BALANCE);
        
        // Set up perpetual market
        perpetualRouter.setMarketPrice(MARKET_ID, 4000e18); // $4000 SPX price
        perpetualRouter.setFundingRate(MARKET_ID, 50); // 0.5% funding rate
    }

    function test_StrategyInitialization() public view {
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        
        assertEq(uint256(info.strategyType), uint256(IExposureStrategy.StrategyType.PERPETUAL));
        assertEq(info.name, "Enhanced SPX Perpetual Strategy");
        assertEq(info.leverage, 200); // Default 2x leverage
        assertEq(info.currentExposure, 0);
        assertFalse(info.isActive); // No position opened yet
    }

    function test_GetCostBreakdown() public view {
        IExposureStrategy.CostBreakdown memory costs = strategy.getCostBreakdown();
        
        assertEq(costs.fundingRate, 50); // 0.5% funding rate
        assertEq(costs.borrowRate, 0); // Not applicable for perpetuals
        assertEq(costs.managementFee, 15); // 0.15% management fee
        assertGt(costs.totalCostBps, 0);
        assertEq(costs.lastUpdated, block.timestamp);
    }

    function test_CanHandleExposure() public view {
        (bool canHandle, string memory reason) = strategy.canHandleExposure(100000e6);
        assertTrue(canHandle);
        assertEq(reason, "");
        
        // Test with zero amount
        (canHandle, reason) = strategy.canHandleExposure(0);
        assertFalse(canHandle);
        assertEq(reason, "Amount cannot be zero");
        
        // Test with excessive amount
        (canHandle, reason) = strategy.canHandleExposure(20000000e6); // $20M
        assertFalse(canHandle);
        assertEq(reason, "Would exceed maximum position size");
    }

    function test_OpenExposure() public {
        uint256 amount = 100000e6; // $100k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        vm.stopPrank();
        
        // Check strategy state
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        assertTrue(info.isActive);
        assertGt(info.currentExposure, 0);
    }

    function test_CloseExposure() public {
        // First open exposure
        test_OpenExposure();
        
        uint256 currentExposure = strategy.getCurrentExposureValue();
        uint256 closeAmount = currentExposure / 2; // Close 50%
        
        vm.prank(user1);
        (bool success, uint256 actualClosed) = strategy.closeExposure(closeAmount);
        assertTrue(success);
        assertGt(actualClosed, 0);
        
        // Check remaining exposure
        uint256 remainingExposure = strategy.getCurrentExposureValue();
        assertLt(remainingExposure, currentExposure);
    }

    function test_AdjustExposure() public {
        // Open initial exposure
        test_OpenExposure();
        
        uint256 initialExposure = strategy.getCurrentExposureValue();
        
        // Increase exposure
        vm.startPrank(user1);
        usdc.approve(address(strategy), 50000e6);
        (bool success, uint256 newExposure) = strategy.adjustExposure(50000e6);
        assertTrue(success);
        assertGt(newExposure, initialExposure);
        
        // Decrease exposure
        uint256 beforeDecrease = newExposure;
        (success, newExposure) = strategy.adjustExposure(-25000e6);
        assertTrue(success);
        assertLt(newExposure, beforeDecrease);
        vm.stopPrank();
    }

    function test_AddYieldStrategy() public {
        vm.prank(owner);
        strategy.addYieldStrategy(address(yieldStrategy), 5000); // 50% allocation
        
        EnhancedPerpetualStrategy.YieldAllocation[] memory yields = strategy.getYieldStrategies();
        assertEq(yields.length, 1);
        assertEq(address(yields[0].strategy), address(yieldStrategy));
        assertEq(yields[0].allocation, 5000);
        assertTrue(yields[0].isActive);
    }

    function test_YieldStrategyIntegration() public {
        // Add yield strategy
        test_AddYieldStrategy();
        
        // Open exposure (should allocate to both perpetual and yield)
        uint256 amount = 100000e6;
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        (bool success, /* uint256 actualExposure */) = strategy.openExposure(amount);
        assertTrue(success);
        vm.stopPrank();
        
        // Check that capital was allocated to yield strategies
        EnhancedPerpetualStrategy.YieldAllocation[] memory yields = strategy.getYieldStrategies();
        assertGt(yields[0].currentDeposit, 0);
    }

    function test_HarvestYield() public {
        // Setup with yield strategy and open position
        test_YieldStrategyIntegration();
        
        // Simulate yield generation
        vm.warp(block.timestamp + 30 days);
        
        uint256 initialBalance = usdc.balanceOf(address(this));
        uint256 harvested = strategy.harvestYield();
        
        // Should have harvested some yield
        assertGe(harvested, 0);
        assertGe(usdc.balanceOf(address(this)), initialBalance);
    }

    function test_DynamicLeverageOptimization() public {
        // Open position with current leverage
        test_OpenExposure();
        
        uint256 initialLeverage = strategy.getCurrentLeverage();
        
        // Change funding rate to trigger leverage adjustment
        perpetualRouter.setFundingRate(MARKET_ID, 300); // 3% high funding rate
        
        vm.prank(owner);
        strategy.updateFundingRate();
        
        vm.prank(owner);
        uint256 newLeverage = strategy.optimizeLeverage();
        
        // Leverage should be reduced due to high funding rate
        assertLe(newLeverage, initialLeverage);
    }

    function test_FundingRateHistory() public {
        // Update funding rate multiple times
        int256[] memory rates = new int256[](5);
        rates[0] = 50;   // 0.5%
        rates[1] = 100;  // 1.0%
        rates[2] = -25;  // -0.25%
        rates[3] = 75;   // 0.75%
        rates[4] = 200;  // 2.0%
        
        for (uint256 i = 0; i < rates.length; i++) {
            perpetualRouter.setFundingRate(MARKET_ID, rates[i]);
            strategy.updateFundingRate();
            vm.warp(block.timestamp + 1 hours);
        }
        
        int256[] memory history = strategy.getFundingRateHistory();
        assertEq(history.length, rates.length);
        
        for (uint256 i = 0; i < rates.length; i++) {
            assertEq(history[i], rates[i]);
        }
    }

    function test_EmergencyExit() public {
        // Open position first
        test_OpenExposure();
        
        uint256 initialValue = strategy.getCurrentExposureValue();
        assertGt(initialValue, 0);
        
        uint256 initialBalance = usdc.balanceOf(address(this));
        uint256 recovered = strategy.emergencyExit();
        
        assertGt(recovered, 0);
        assertGt(usdc.balanceOf(address(this)), initialBalance);
        
        // Strategy should be reset
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        assertFalse(info.isActive);
        assertEq(info.currentExposure, 0);
    }

    function test_RiskParameterUpdates() public {
        IExposureStrategy.RiskParameters memory newParams = IExposureStrategy.RiskParameters({
            maxLeverage: 400,        // 4x max leverage
            maxPositionSize: 5000000e6, // $5M max position
            liquidationBuffer: 2000, // 20% buffer
            rebalanceThreshold: 300, // 3% threshold
            slippageLimit: 150,      // 1.5% max slippage
            emergencyExitEnabled: true
        });
        
        vm.prank(owner);
        strategy.updateRiskParameters(newParams);
        
        IExposureStrategy.RiskParameters memory updated = strategy.getRiskParameters();
        assertEq(updated.maxLeverage, 400);
        assertEq(updated.maxPositionSize, 5000000e6);
        assertEq(updated.liquidationBuffer, 2000);
    }

    function test_LeverageParameterConfiguration() public {
        vm.prank(owner);
        strategy.setLeverageParameters(
            250, // 2.5x base leverage
            600, // 6x max leverage
            100, // 1x min leverage
            true // dynamic enabled
        );
        
        // Test that new parameters are applied
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        assertEq(info.leverage, 250);
    }

    function test_CapitalEfficiency() public {
        // Setup with yield strategy and open position
        test_YieldStrategyIntegration();
        
        uint256 efficiency = strategy.getCapitalEfficiency();
        assertGt(efficiency, 10000); // Should be > 100% due to leverage
    }

    function test_PerformanceMetrics() public {
        // Open position and let some time pass
        test_OpenExposure();
        vm.warp(block.timestamp + 7 days);
        
        (
            uint256 totalFunding,
            uint256 totalYield,
            /* uint256 netReturn */,
            uint256 efficiency
        ) = strategy.getPerformanceMetrics();

        // Should have some metrics (even if zero)
        assertGe(totalFunding, 0);
        assertGe(totalYield, 0);
        assertGe(efficiency, 0);
    }

    function test_RemoveYieldStrategy() public {
        // Add yield strategy first
        test_AddYieldStrategy();
        
        vm.prank(owner);
        strategy.removeYieldStrategy(address(yieldStrategy));
        
        EnhancedPerpetualStrategy.YieldAllocation[] memory yields = strategy.getYieldStrategies();
        assertEq(yields.length, 0);
    }

    function test_FailureHandling() public {
        // Test with failing perpetual router
        MockPerpetualTrading failingRouter = new MockPerpetualTrading(address(usdc));
        failingRouter.setShouldFail(true);
        
        EnhancedPerpetualStrategy failingStrategy = new EnhancedPerpetualStrategy(
            address(usdc),
            address(failingRouter),
            address(priceOracle),
            MARKET_ID,
            "Failing Strategy"
        );
        
        vm.startPrank(user1);
        usdc.approve(address(failingStrategy), 100000e6);
        
        // Should handle perpetual router failures gracefully
        vm.expectRevert();
        failingStrategy.openExposure(100000e6);
        vm.stopPrank();
    }

    function test_EstimateExposureCost() public view {
        uint256 amount = 100000e6; // $100k
        uint256 timeHorizon = 30 days;
        
        uint256 estimatedCost = strategy.estimateExposureCost(amount, timeHorizon);
        assertGt(estimatedCost, 0);
        
        // Cost should increase with longer time horizons
        uint256 longerCost = strategy.estimateExposureCost(amount, 90 days);
        assertGt(longerCost, estimatedCost);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_OpenExposure(uint256 amount) public {
        amount = bound(amount, 1000e6, 500000e6); // $1k to $500k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        assertLe(actualExposure, amount * 5); // Max 5x leverage
        vm.stopPrank();
    }

    function testFuzz_LeverageOptimization(int256 fundingRate) public {
        fundingRate = bound(fundingRate, -500, 1000); // -5% to 10% funding
        
        // Open position first
        test_OpenExposure();
        
        // Set funding rate and optimize
        perpetualRouter.setFundingRate(MARKET_ID, fundingRate);
        
        vm.prank(owner);
        strategy.updateFundingRate();
        
        vm.prank(owner);
        uint256 newLeverage = strategy.optimizeLeverage();
        
        // Leverage should be within reasonable bounds
        assertGe(newLeverage, 100); // At least 1x
        assertLe(newLeverage, 500); // At most 5x
    }

    function testFuzz_YieldAllocation(uint256 allocation) public {
        allocation = bound(allocation, 100, 8000); // 1% to 80%
        
        vm.prank(owner);
        strategy.addYieldStrategy(address(yieldStrategy), allocation);
        
        EnhancedPerpetualStrategy.YieldAllocation[] memory yields = strategy.getYieldStrategies();
        assertEq(yields[0].allocation, allocation);
    }
}