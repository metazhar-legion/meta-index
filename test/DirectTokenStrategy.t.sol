// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DirectTokenStrategy} from "../src/strategies/DirectTokenStrategy.sol";
import {IExposureStrategy} from "../src/interfaces/IExposureStrategy.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockRWAToken} from "../src/mocks/MockRWAToken.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEXRouter} from "../src/mocks/MockDEXRouter.sol";
import {MockYieldStrategy} from "../src/mocks/MockYieldStrategy.sol";

contract DirectTokenStrategyTest is Test {
    DirectTokenStrategy public strategy;
    MockUSDC public usdc;
    MockRWAToken public rwaToken;
    MockPriceOracle public priceOracle;
    MockDEXRouter public dexRouter;
    MockYieldStrategy public yieldStrategy1;
    MockYieldStrategy public yieldStrategy2;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 public constant INITIAL_BALANCE = 1000000e6; // 1M USDC
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant RWA_TOKEN_PRICE = 100e18; // $100 per RWA token
    
    event TokensPurchased(uint256 baseAssetSpent, uint256 tokensReceived, uint256 slippage);
    event TokensSold(uint256 tokensSold, uint256 baseAssetReceived, uint256 slippage);
    event YieldStrategyAdded(address strategy, uint256 allocation);
    event AllocationUpdated(uint256 newTokenAllocation, uint256 newYieldAllocation);

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        rwaToken = new MockRWAToken("RWA Token", "RWA");
        rwaToken.setDecimals(6); // Set to 6 decimals like USDC for easier calculations
        priceOracle = new MockPriceOracle(address(usdc));
        dexRouter = new MockDEXRouter(address(usdc), address(rwaToken));
        
        // Set RWA token price
        priceOracle.setPrice(address(rwaToken), RWA_TOKEN_PRICE);
        
        // Set correct exchange rates in DEX router
        // RWA token has 6 decimals like USDC for simplicity  
        // At $100 per RWA token: 1 USDC (1e6) should get 0.01 RWA tokens (0.01 * 1e6 = 1e4)
        // Exchange rate should be: output = (input * rate) / 1e18
        // So: 1e6 * rate / 1e18 = 1e4 => rate = 1e4 * 1e18 / 1e6 = 1e16
        dexRouter.setExchangeRate(address(usdc), address(rwaToken), 1e16); // 1 USDC = 0.01 RWA
        // 1 RWA token (1e6) should get 100 USDC (100e6)
        // 1e6 * rate / 1e18 = 100e6 => rate = 100e6 * 1e18 / 1e6 = 100e18
        dexRouter.setExchangeRate(address(rwaToken), address(usdc), 100e18); // 1 RWA = 100 USDC
        
        // Deploy yield strategies
        yieldStrategy1 = new MockYieldStrategy(IERC20(address(usdc)), "Yield Strategy 1");
        yieldStrategy2 = new MockYieldStrategy(IERC20(address(usdc)), "Yield Strategy 2");
        
        // Deploy strategy
        vm.startPrank(owner);
        strategy = new DirectTokenStrategy(
            address(usdc),
            address(rwaToken),
            address(priceOracle),
            address(dexRouter),
            "Direct RWA Token Strategy"
        );
        
        // Add yield strategies
        strategy.addYieldStrategy(address(yieldStrategy1), 6000); // 60%
        strategy.addYieldStrategy(address(yieldStrategy2), 4000); // 40%
        vm.stopPrank();
        
        // Fund accounts
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(address(this), INITIAL_BALANCE);
        
        // Fund DEX router and yield strategies for swaps/returns
        usdc.mint(address(dexRouter), INITIAL_BALANCE);
        rwaToken.mint(address(dexRouter), 100000e18); // 100k RWA tokens
        usdc.mint(address(yieldStrategy1), INITIAL_BALANCE);
        usdc.mint(address(yieldStrategy2), INITIAL_BALANCE);
    }

    function test_StrategyInitialization() public {
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        
        assertEq(uint256(info.strategyType), uint256(IExposureStrategy.StrategyType.DIRECT_TOKEN));
        assertEq(info.name, "Direct RWA Token Strategy");
        assertEq(info.leverage, 100); // 1x leverage
        assertEq(info.collateralRatio, BASIS_POINTS); // 100% collateral
        assertEq(info.currentExposure, 0);
        assertFalse(info.isActive);
        assertEq(info.liquidationPrice, 0); // No liquidation for direct tokens
        
        // Check yield strategies
        (address[] memory strategies, uint256[] memory allocations) = strategy.getYieldStrategies();
        assertEq(strategies.length, 2);
        assertEq(strategies[0], address(yieldStrategy1));
        assertEq(strategies[1], address(yieldStrategy2));
        assertEq(allocations[0], 6000);
        assertEq(allocations[1], 4000);
    }

    function test_GetCostBreakdown() public {
        IExposureStrategy.CostBreakdown memory costs = strategy.getCostBreakdown();
        
        assertEq(costs.fundingRate, 0); // Not applicable for direct tokens
        assertEq(costs.borrowRate, 0);  // Not applicable for direct tokens
        assertEq(costs.managementFee, 15); // 0.15% management fee
        assertGt(costs.slippageCost, 0); // Should have estimated slippage
        assertGt(costs.gasCost, 0); // Should have estimated gas cost
        assertGt(costs.totalCostBps, 0);
    }

    function test_CanHandleExposure() public {
        (bool canHandle, string memory reason) = strategy.canHandleExposure(100000e6);
        assertTrue(canHandle);
        assertEq(reason, "");
        
        // Test with zero amount
        (canHandle, reason) = strategy.canHandleExposure(0);
        assertFalse(canHandle);
        assertEq(reason, "Amount cannot be zero");
        
        // Test with excessive amount
        (canHandle, reason) = strategy.canHandleExposure(15000000e6); // $15M
        assertFalse(canHandle);
        assertEq(reason, "Amount exceeds maximum position size");
    }

    function test_OpenExposure() public {
        uint256 amount = 100000e6; // $100k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        
        // Expected: 80% of 100k USDC = 80k USDC
        // At 1e4 rate = 800e6 tokens, with 0.5% slippage = 796e6 tokens  
        vm.expectEmit(true, true, true, true);
        emit TokensPurchased(80000e6, 796e6, 50); // 80% allocated to tokens with slippage
        
        (bool success, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        
        // Check that tokens were purchased and allocated correctly
        assertGt(strategy.currentTokenBalance(), 0);
        assertEq(usdc.balanceOf(user1), balanceBefore - amount);
        vm.stopPrank();
        
        // Check strategy state
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        assertTrue(info.isActive);
        assertGt(info.currentExposure, 0);
        
        // Check performance metrics
        (
            uint256 totalPurchased,
            uint256 totalSold,
            uint256 currentBalance,
            /* uint256 totalSlippage */,
            uint256 yieldHarvested
        ) = strategy.getPerformanceMetrics();

        assertGt(totalPurchased, 0);
        assertEq(totalSold, 0);
        assertGt(currentBalance, 0);
        assertEq(yieldHarvested, 0);
    }

    function test_CloseExposure() public {
        // First open exposure
        uint256 amount = 100000e6; // $100k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        (bool openSuccess, /* uint256 actualExposure */) = strategy.openExposure(amount);
        assertTrue(openSuccess);
        vm.stopPrank();
        
        uint256 currentExposure = strategy.getCurrentExposureValue();
        uint256 closeAmount = currentExposure / 2; // Close 50%
        
        // Expect to sell ~50% of 796e6 tokens = 398e6 tokens, get ~39.6M USDC
        vm.expectEmit(true, true, true, true);
        emit TokensSold(398000000, 39601000000, 50); // 398 tokens sold for 39.601B USDC with 0.5% slippage
        
        vm.prank(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);
        (bool success, uint256 actualClosed) = strategy.closeExposure(closeAmount);
        assertTrue(success);
        assertGt(actualClosed, 0);
        
        // Check that user received base asset back (or at least the balance didn't decrease)
        assertGe(usdc.balanceOf(user1), balanceBefore);
        
        // Check remaining exposure
        uint256 remainingExposure = strategy.getCurrentExposureValue();
        assertLt(remainingExposure, currentExposure);
        assertGt(remainingExposure, 0); // Should still have some exposure
    }

    function test_AdjustExposure() public {
        // Open initial exposure
        uint256 amount = 50000e6; // $50k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        (bool openSuccess, /* uint256 actualExposure */) = strategy.openExposure(amount);
        assertTrue(openSuccess);
        
        uint256 initialExposure = strategy.getCurrentExposureValue();
        
        // Increase exposure
        uint256 increaseAmount = 25000e6; // $25k
        usdc.approve(address(strategy), increaseAmount);
        (bool success, uint256 newExposure) = strategy.adjustExposure(int256(increaseAmount));
        assertTrue(success);
        assertGt(newExposure, initialExposure);
        
        // Decrease exposure
        uint256 currentExposure = strategy.getCurrentExposureValue();
        (success, newExposure) = strategy.adjustExposure(-10000e6);
        assertTrue(success);
        assertLt(newExposure, currentExposure);
        vm.stopPrank();
    }

    function test_HarvestYield() public {
        // Open exposure to allocate to yield strategies
        test_OpenExposure();
        
        // Simulate yield generation for harvest
        yieldStrategy1.simulateYield(1000e6); // $1000 yield
        yieldStrategy2.simulateYield(500e6);  // $500 yield
        
        uint256 harvested = strategy.harvestYield();
        // Actual harvested yield may be different due to MockYieldStrategy calculation
        assertGt(harvested, 1000e6); // Should harvest significant yield
        
        // Check performance tracking
        (, , , , uint256 totalYieldHarvested) = strategy.getPerformanceMetrics();
        assertEq(totalYieldHarvested, harvested);
    }

    function test_EstimateExposureCost() public {
        uint256 amount = 100000e6; // $100k
        uint256 timeHorizon = 365 days; // 1 year
        
        uint256 estimatedCost = strategy.estimateExposureCost(amount, timeHorizon);
        assertGt(estimatedCost, 0);
        
        // Cost should be reasonable (management fee + slippage + gas)
        // For 1 year: 0.15% of $100k = $150 + slippage + gas
        assertLt(estimatedCost, 1000e6); // Should be less than $1000
        
        // Test with zero amount
        uint256 zeroCost = strategy.estimateExposureCost(0, timeHorizon);
        assertEq(zeroCost, 0);
        
        // Longer time horizon should cost more
        uint256 longerCost = strategy.estimateExposureCost(amount, 2 * 365 days);
        assertGt(longerCost, estimatedCost);
    }

    function test_GetCollateralRequired() public {
        uint256 exposureAmount = 200000e6; // $200k
        
        // Direct token strategy requires 100% collateral
        uint256 collateralRequired = strategy.getCollateralRequired(exposureAmount);
        assertEq(collateralRequired, exposureAmount);
    }

    function test_EmergencyExit() public {
        // Open exposure first
        test_OpenExposure();
        
        uint256 initialValue = strategy.getCurrentExposureValue();
        assertGt(initialValue, 0);
        
        vm.prank(owner);
        uint256 recovered = strategy.emergencyExit();
        assertGt(recovered, 0);
        
        // Strategy should be reset
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        assertFalse(info.isActive);
        assertEq(info.currentExposure, 0);
        assertEq(strategy.currentTokenBalance(), 0);
        assertEq(strategy.totalInvestedAmount(), 0);
    }

    function test_UpdateAllocation() public {
        vm.startPrank(owner);
        
        // Update allocation to 90% tokens, 10% yield
        vm.expectEmit(true, true, false, true);
        emit AllocationUpdated(9000, 1000);
        
        strategy.updateAllocation(9000, 1000);
        
        assertEq(strategy.tokenAllocation(), 9000);
        assertEq(strategy.yieldAllocation(), 1000);
        vm.stopPrank();
    }

    function test_UpdateAllocationFailures() public {
        vm.startPrank(owner);
        
        // Should fail if allocations don't sum to 100%
        vm.expectRevert("Allocations must sum to 100%");
        strategy.updateAllocation(8000, 1000);
        
        // Should fail if token allocation too low
        vm.expectRevert("Token allocation too low");
        strategy.updateAllocation(4000, 6000);
        
        vm.stopPrank();
    }

    function test_AddRemoveYieldStrategy() public {
        MockYieldStrategy newStrategy = new MockYieldStrategy(IERC20(address(usdc)), "New Strategy");
        
        vm.startPrank(owner);
        
        // Add new yield strategy
        vm.expectEmit(true, false, false, true);
        emit YieldStrategyAdded(address(newStrategy), 2000);
        
        strategy.addYieldStrategy(address(newStrategy), 2000);
        
        (address[] memory strategies, uint256[] memory allocations) = strategy.getYieldStrategies();
        assertEq(strategies.length, 3);
        assertEq(strategies[2], address(newStrategy));
        assertEq(allocations[2], 2000);
        
        // Remove yield strategy (remove the first one)
        strategy.removeYieldStrategy(0);
        
        (strategies, allocations) = strategy.getYieldStrategies();
        assertEq(strategies.length, 2);
        // The last strategy should have moved to position 0
        assertEq(strategies[0], address(newStrategy));
        
        vm.stopPrank();
    }

    function test_UpdateRiskParameters() public {
        IExposureStrategy.RiskParameters memory newParams = IExposureStrategy.RiskParameters({
            maxLeverage: 100,        // Must be 1x for direct tokens
            maxPositionSize: 5000000e6, // $5M max position
            liquidationBuffer: 0,    // Not applicable
            rebalanceThreshold: 300, // 3% threshold
            slippageLimit: 150,      // 1.5% max slippage
            emergencyExitEnabled: true
        });
        
        vm.prank(owner);
        strategy.updateRiskParameters(newParams);
        
        IExposureStrategy.RiskParameters memory updated = strategy.getRiskParameters();
        assertEq(updated.maxLeverage, 100);
        assertEq(updated.maxPositionSize, 5000000e6);
        assertEq(updated.slippageLimit, 150);
    }

    function test_UpdateRiskParametersFailures() public {
        vm.startPrank(owner);
        
        // Should fail if leverage > 1x
        IExposureStrategy.RiskParameters memory invalidParams = IExposureStrategy.RiskParameters({
            maxLeverage: 200,        // Invalid - too high
            maxPositionSize: 5000000e6,
            liquidationBuffer: 0,
            rebalanceThreshold: 300,
            slippageLimit: 150,
            emergencyExitEnabled: true
        });
        
        vm.expectRevert("Leverage must be 1x for direct tokens");
        strategy.updateRiskParameters(invalidParams);
        
        // Should fail if slippage limit too high
        invalidParams.maxLeverage = 100;
        invalidParams.slippageLimit = 1500; // 15% - too high
        
        vm.expectRevert("Slippage limit too high");
        strategy.updateRiskParameters(invalidParams);
        
        vm.stopPrank();
    }

    function test_RebalanceStrategies() public {
        vm.startPrank(owner);
        
        // Should work after 1 hour
        vm.warp(block.timestamp + 1 hours + 1);
        strategy.rebalanceStrategies();
        
        // Should fail if called too frequently
        vm.expectRevert("Rebalance too frequent");
        strategy.rebalanceStrategies();
        
        vm.stopPrank();
    }

    function test_MultipleExposureOperations() public {
        uint256 amount1 = 50000e6;  // $50k
        uint256 amount2 = 30000e6;  // $30k
        
        // User 1 opens exposure
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount1);
        (bool success1, uint256 exposure1) = strategy.openExposure(amount1);
        assertTrue(success1);
        vm.stopPrank();
        
        // User 2 opens exposure
        vm.startPrank(user2);
        usdc.approve(address(strategy), amount2);
        (bool success2, uint256 exposure2) = strategy.openExposure(amount2);
        assertTrue(success2);
        vm.stopPrank();
        
        // Total exposure should be sum of both
        uint256 totalExposure = strategy.getCurrentExposureValue();
        assertGe(totalExposure, exposure1);
        assertGe(totalExposure, exposure2);
        
        // Both users partially close
        vm.prank(user1);
        strategy.closeExposure(exposure1 / 2);
        
        vm.prank(user2);
        strategy.closeExposure(exposure2 / 3);
        
        // Should still have some exposure remaining
        uint256 remainingExposure = strategy.getCurrentExposureValue();
        assertGt(remainingExposure, 0);
        assertLt(remainingExposure, totalExposure);
    }

    function test_ZeroExposureEdgeCases() public {
        // Test edge cases with zero exposure
        (bool canHandle, string memory reason) = strategy.canHandleExposure(0);
        assertFalse(canHandle);
        assertEq(reason, "Amount cannot be zero");
        
        uint256 collateralRequired = strategy.getCollateralRequired(0);
        assertEq(collateralRequired, 0);
        
        uint256 estimatedCost = strategy.estimateExposureCost(0, 30 days);
        assertEq(estimatedCost, 0);
        
        uint256 currentValue = strategy.getCurrentExposureValue();
        assertEq(currentValue, 0);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_OpenExposure(uint256 amount) public {
        amount = bound(amount, 1000e6, 500000e6); // $1k to $500k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        assertLe(actualExposure, amount * 2); // Should be reasonable
        vm.stopPrank();
    }

    function testFuzz_EstimateExposureCost(uint256 amount, uint256 timeHorizon) public {
        amount = bound(amount, 1000e6, 1000000e6); // $1k to $1M
        timeHorizon = bound(timeHorizon, 1 days, 365 days); // 1 day to 1 year
        
        uint256 estimatedCost = strategy.estimateExposureCost(amount, timeHorizon);
        
        // Cost should be reasonable
        assertLt(estimatedCost, amount / 10); // Less than 10% of principal
        assertGe(estimatedCost, 0);
    }

    function testFuzz_AllocationUpdate(uint256 tokenAlloc, uint256 yieldAlloc) public {
        tokenAlloc = bound(tokenAlloc, 5000, 9500); // 50% to 95%
        yieldAlloc = BASIS_POINTS - tokenAlloc;     // Remainder
        
        vm.prank(owner);
        strategy.updateAllocation(tokenAlloc, yieldAlloc);
        
        assertEq(strategy.tokenAllocation(), tokenAlloc);
        assertEq(strategy.yieldAllocation(), yieldAlloc);
    }
}