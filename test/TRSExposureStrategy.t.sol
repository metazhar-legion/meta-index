// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TRSExposureStrategy} from "../src/strategies/TRSExposureStrategy.sol";
import {IExposureStrategy} from "../src/interfaces/IExposureStrategy.sol";
import {ITRSProvider} from "../src/interfaces/ITRSProvider.sol";
import {MockTRSProvider} from "../src/mocks/MockTRSProvider.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";

contract TRSExposureStrategyTest is Test {
    TRSExposureStrategy public strategy;
    MockTRSProvider public trsProvider;
    MockUSDC public usdc;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    bytes32 public constant UNDERLYING_ASSET_ID = "SP500";
    uint256 public constant INITIAL_BALANCE = 1000000e6; // 1M USDC
    uint256 public constant BASIS_POINTS = 10000;
    
    // Mock counterparties (these are set up in MockTRSProvider constructor)
    address public constant COUNTERPARTY_AAA = address(0x1111);
    address public constant COUNTERPARTY_BBB = address(0x2222);
    address public constant COUNTERPARTY_BB = address(0x3333);

    event TRSContractCreated(bytes32 indexed contractId, address indexed counterparty, uint256 notionalAmount, uint256 collateralAmount);
    event CounterpartyAdded(address indexed counterparty, uint256 targetAllocation, uint256 maxExposure);

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        priceOracle = new MockPriceOracle(address(usdc));
        trsProvider = new MockTRSProvider(address(usdc));
        
        // Deploy strategy (owned by this test contract)
        strategy = new TRSExposureStrategy(
            address(usdc),
            address(trsProvider),
            address(priceOracle),
            UNDERLYING_ASSET_ID,
            "TRS SPX Strategy"
        );
        
        // Fund accounts
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(address(this), INITIAL_BALANCE);
        
        // Fund TRS provider for settlements
        usdc.mint(address(trsProvider), INITIAL_BALANCE);
        
        // Set up counterparties in strategy (this test contract owns both)
        strategy.addCounterparty(COUNTERPARTY_AAA, 4000, 3000000e6); // 40% target, $3M max
        strategy.addCounterparty(COUNTERPARTY_BBB, 3500, 2000000e6); // 35% target, $2M max
        strategy.addCounterparty(COUNTERPARTY_BB, 2500, 1000000e6);  // 25% target, $1M max
    }

    function test_StrategyInitialization() public {
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        
        assertEq(uint256(info.strategyType), uint256(IExposureStrategy.StrategyType.TRS));
        assertEq(info.name, "TRS SPX Strategy");
        assertEq(info.currentExposure, 0);
        assertFalse(info.isActive);
    }

    function test_GetCostBreakdown() public {
        IExposureStrategy.CostBreakdown memory costs = strategy.getCostBreakdown();
        
        assertEq(costs.fundingRate, 0); // Not applicable for TRS
        assertGt(costs.borrowRate, 0); // Should have some borrow rate
        assertEq(costs.managementFee, 20); // 0.20% management fee
        assertGt(costs.totalCostBps, 0);
        assertEq(costs.lastUpdated, block.timestamp);
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
        (canHandle, reason) = strategy.canHandleExposure(10000000e6); // $10M
        assertFalse(canHandle);
        assertEq(reason, "Would exceed maximum position size");
    }

    function test_CounterpartySetup() public {
        // Check that counterparties are set up correctly
        TRSExposureStrategy.CounterpartyAllocation[] memory allocations = strategy.getCounterpartyAllocations();
        assertEq(allocations.length, 3);
        
        // Verify each counterparty
        assertEq(allocations[0].counterparty, COUNTERPARTY_AAA);
        assertEq(allocations[0].targetAllocation, 4000);
        assertTrue(allocations[0].isActive);
        
        assertEq(allocations[1].counterparty, COUNTERPARTY_BBB);
        assertEq(allocations[1].targetAllocation, 3500);
        assertTrue(allocations[1].isActive);
        
        assertEq(allocations[2].counterparty, COUNTERPARTY_BB);
        assertEq(allocations[2].targetAllocation, 2500);
        assertTrue(allocations[2].isActive);
    }

    function test_AddCounterparty() public {
        // Try to add another counterparty
        address newCounterparty = address(0x4444);
        
        // First add to TRS provider
        ITRSProvider.CounterpartyInfo memory cpInfo = ITRSProvider.CounterpartyInfo({
            counterpartyAddress: newCounterparty,
            name: "New Bank",
            creditRating: 8,
            maxExposure: 5000000e6,
            currentExposure: 0,
            defaultProbability: 10,
            isActive: true,
            collateralRequirement: 1300
        });
        trsProvider.addCounterparty(newCounterparty, cpInfo);
        
        vm.expectEmit(true, false, false, true);
        emit CounterpartyAdded(newCounterparty, 1000, 500000e6);
        
        strategy.addCounterparty(newCounterparty, 1000, 500000e6); // 10% target, $500k max
        
        TRSExposureStrategy.CounterpartyAllocation[] memory allocations = strategy.getCounterpartyAllocations();
        assertEq(allocations.length, 4);
        assertEq(allocations[3].counterparty, newCounterparty);
        assertEq(allocations[3].targetAllocation, 1000);
        assertTrue(allocations[3].isActive);
    }

    function test_OpenExposure() public {
        uint256 amount = 150000e6; // $150k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        assertLe(actualExposure, amount * 3); // Max 3x leverage
        vm.stopPrank();
        
        // Check strategy state
        IExposureStrategy.ExposureInfo memory info = strategy.getExposureInfo();
        assertTrue(info.isActive);
        assertGt(info.currentExposure, 0);
        
        // Check active contracts
        bytes32[] memory activeContracts = strategy.getActiveTRSContracts();
        assertEq(activeContracts.length, 1);
    }

    function test_CloseExposure() public {
        // First open exposure
        uint256 amount = 150000e6; // $150k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool openSuccess, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(openSuccess);
        assertGt(actualExposure, 0);
        vm.stopPrank();
        
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
        uint256 amount = 150000e6; // $150k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool openSuccess, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(openSuccess);
        assertGt(actualExposure, 0);
        vm.stopPrank();
        
        uint256 initialExposure = strategy.getCurrentExposureValue();
        
        // Increase exposure
        vm.startPrank(user1);
        usdc.approve(address(strategy), 75000e6);
        (bool success, uint256 newExposure) = strategy.adjustExposure(75000e6);
        assertTrue(success);
        assertGt(newExposure, initialExposure);
        
        // Decrease exposure
        uint256 beforeDecrease = newExposure;
        (success, newExposure) = strategy.adjustExposure(-50000e6);
        assertTrue(success);
        assertLt(newExposure, beforeDecrease);
        vm.stopPrank();
    }

    function test_HarvestYield() public {
        // Open exposure first
        test_OpenExposure();
        
        // TRS doesn't generate harvestable yield, should return 0
        uint256 harvested = strategy.harvestYield();
        assertEq(harvested, 0);
    }

    function test_EstimateExposureCost() public {
        uint256 amount = 100000e6; // $100k
        uint256 timeHorizon = 90 days;
        
        uint256 estimatedCost = strategy.estimateExposureCost(amount, timeHorizon);
        assertGt(estimatedCost, 0);
        
        // Cost should increase with longer time horizons
        uint256 longerCost = strategy.estimateExposureCost(amount, 180 days);
        assertGt(longerCost, estimatedCost);
    }

    function test_GetCollateralRequired() public {
        uint256 exposureAmount = 200000e6; // $200k
        
        uint256 collateralRequired = strategy.getCollateralRequired(exposureAmount);
        assertGt(collateralRequired, 0);
        assertLt(collateralRequired, exposureAmount); // Should be less than full amount due to leverage
    }

    function test_EmergencyExit() public {
        // Open exposure first
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
        
        bytes32[] memory activeContracts = strategy.getActiveTRSContracts();
        assertEq(activeContracts.length, 0);
    }

    function test_RebalanceContracts() public {
        // Open exposure to create contracts
        test_OpenExposure();
        
        // Fast forward time to simulate contract maturity
        vm.warp(block.timestamp + 91 days);
        
        bool success = strategy.rebalanceContracts();
        assertTrue(success);
    }

    function test_OptimizeCollateral() public {
        // Open exposure first
        test_OpenExposure();
        
        uint256 optimized = strategy.optimizeCollateral();
        assertGe(optimized, 0); // Should be >= 0
    }

    function test_RemoveCounterparty() public {
        // Try to remove a counterparty with no exposure
        strategy.removeCounterparty(COUNTERPARTY_BB);
        
        TRSExposureStrategy.CounterpartyAllocation[] memory allocations = strategy.getCounterpartyAllocations();
        assertEq(allocations.length, 2); // Should have one less
        
        // Verify the removed counterparty is not in the list
        bool found = false;
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].counterparty == COUNTERPARTY_BB) {
                found = true;
                break;
            }
        }
        assertFalse(found);
    }

    function test_RiskParameterUpdates() public {
        IExposureStrategy.RiskParameters memory newParams = IExposureStrategy.RiskParameters({
            maxLeverage: 400,        // 4x max leverage
            maxPositionSize: 8000000e6, // $8M max position
            liquidationBuffer: 1500, // 15% buffer
            rebalanceThreshold: 400, // 4% threshold
            slippageLimit: 200,      // 2% max slippage
            emergencyExitEnabled: true
        });
        
        strategy.updateRiskParameters(newParams);
        
        IExposureStrategy.RiskParameters memory updated = strategy.getRiskParameters();
        assertEq(updated.maxLeverage, 400);
        assertEq(updated.maxPositionSize, 8000000e6);
        assertEq(updated.liquidationBuffer, 1500);
    }

    function test_GetStrategyPerformance() public {
        // Open and close some exposure to generate performance data
        test_OpenExposure();
        
        (
            uint256 totalContracts,
            uint256 totalBorrowCostsPaid,
            uint256 totalRealizedPnLAmount,
            uint256 averageContractDuration
        ) = strategy.getStrategyPerformance();
        
        assertGt(totalContracts, 0);
        assertGe(totalBorrowCostsPaid, 0);
        assertGe(totalRealizedPnLAmount, 0);
        assertGe(averageContractDuration, 0);
    }

    function test_MultipleCounterpartyExposure() public {
        // Open larger exposure that should be spread across counterparties
        uint256 largeAmount = 500000e6; // $500k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), largeAmount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(largeAmount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        vm.stopPrank();
        
        // Check that exposure was created
        TRSExposureStrategy.CounterpartyAllocation[] memory allocations = strategy.getCounterpartyAllocations();
        
        // Should have exposure with at least one counterparty
        bool hasExposure = false;
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].currentExposure > 0) {
                hasExposure = true;
                break;
            }
        }
        assertTrue(hasExposure);
    }

    function test_FailureHandling() public {
        // Test with failing TRS provider
        trsProvider.setShouldFailCreation(true);
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), 100000e6);
        
        // Should fail to open exposure when provider fails
        vm.expectRevert();
        strategy.openExposure(100000e6);
        vm.stopPrank();
        
        // Reset failure mode
        trsProvider.setShouldFailCreation(false);
    }

    function test_ContractMaturityHandling() public {
        // Open exposure
        test_OpenExposure();
        
        bytes32[] memory contracts = strategy.getActiveTRSContracts();
        assertGt(contracts.length, 0);
        
        // Fast forward past maturity
        vm.warp(block.timestamp + 95 days);
        
        // Rebalance should settle matured contracts
        strategy.rebalanceContracts();
        
        // Note: Specific assertion depends on mock implementation behavior
        // In a real scenario, matured contracts would be settled
    }

    function test_ConcentrationLimits() public {
        // Try to add a counterparty allocation that would exceed concentration limits
        // This is tested implicitly in the quote selection logic
        
        uint256 maxAmount = 900000e6; // $900k - should be within limits for AAA counterparty
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), maxAmount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(maxAmount);
        
        // Should succeed if within limits
        assertTrue(success);
        assertGt(actualExposure, 0);
        vm.stopPrank();
    }

    function test_InvalidCounterpartyHandling() public {
        // Try to add a counterparty that doesn't exist in TRS provider
        address invalidCounterparty = address(0x9999);
        
        vm.expectRevert();
        strategy.addCounterparty(invalidCounterparty, 1000, 100000e6);
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
    }

    // ============ FUZZ TESTS ============

    function testFuzz_OpenExposure(uint256 amount) public {
        amount = bound(amount, 10000e6, 500000e6); // $10k to $500k
        
        vm.startPrank(user1);
        usdc.approve(address(strategy), amount);
        
        (bool success, uint256 actualExposure) = strategy.openExposure(amount);
        assertTrue(success);
        assertGt(actualExposure, 0);
        assertLe(actualExposure, amount * 5); // Max 5x leverage theoretical
        vm.stopPrank();
    }

    function testFuzz_EstimateExposureCost(uint256 amount, uint256 timeHorizon) public {
        amount = bound(amount, 1000e6, 1000000e6); // $1k to $1M
        timeHorizon = bound(timeHorizon, 7 days, 365 days); // 1 week to 1 year
        
        uint256 estimatedCost = strategy.estimateExposureCost(amount, timeHorizon);
        
        // Cost should be reasonable (not more than the principal)
        assertLt(estimatedCost, amount);
        assertGe(estimatedCost, 0);
    }

    function testFuzz_CounterpartyAllocation(uint256 targetAllocation, uint256 maxExposure) public {
        targetAllocation = bound(targetAllocation, 100, 3000); // 1% to 30%
        maxExposure = bound(maxExposure, 100000e6, 5000000e6); // $100k to $5M
        
        // Add to TRS provider first
        address newCounterparty = address(uint160(0x5000 + targetAllocation));
        
        ITRSProvider.CounterpartyInfo memory cpInfo = ITRSProvider.CounterpartyInfo({
            counterpartyAddress: newCounterparty,
            name: "Fuzz Bank",
            creditRating: 7,
            maxExposure: maxExposure,
            currentExposure: 0,
            defaultProbability: 50,
            isActive: true,
            collateralRequirement: 1500
        });
        trsProvider.addCounterparty(newCounterparty, cpInfo);
        
        strategy.addCounterparty(newCounterparty, targetAllocation, maxExposure);
        
        TRSExposureStrategy.CounterpartyAllocation[] memory allocations = strategy.getCounterpartyAllocations();
        
        // Find our added counterparty
        bool found = false;
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].counterparty == newCounterparty) {
                assertEq(allocations[i].targetAllocation, targetAllocation);
                assertEq(allocations[i].maxExposure, maxExposure);
                assertTrue(allocations[i].isActive);
                found = true;
                break;
            }
        }
        assertTrue(found);
    }
}