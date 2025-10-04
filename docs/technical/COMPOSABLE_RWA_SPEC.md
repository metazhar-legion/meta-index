# Composable RWA Exposure Strategy Specification

## Executive Summary

This specification details the refactor of the Web3 Index Fund's RWA exposure system from a single perpetuals-based approach to a composable, multi-strategy architecture. The new system enables dynamic optimization of RWA exposure through multiple methods (TRS, Perpetuals, Direct Tokens) with integrated yield strategies for enhanced capital efficiency.

## Current Architecture Analysis

### Existing Implementation Limitations
1. **Single Strategy Dependency**: Current `RWAAssetWrapper` is tightly coupled to perpetuals via `RWASyntheticSP500`
2. **Fixed Allocation**: 20/80 split between RWA/yield is static and not optimizable
3. **No Cost Optimization**: Cannot dynamically switch between exposure methods based on funding rates/costs
4. **Limited Composability**: Yield strategies are separate from RWA exposure strategies
5. **Inflexible Rebalancing**: Cannot optimize for different market conditions

### Key Components to Refactor
- `RWAAssetWrapper.sol` - Make strategy-agnostic
- `RWASyntheticSP500.sol` - Convert to one of many exposure strategies
- `PerpetualRouter.sol` - Enhance for multi-strategy support
- Yield strategy integration patterns
- Rebalancing logic with cost optimization

## New Composable Architecture

### Core Design Principles
1. **Strategy Composability**: RWA bundles can combine multiple exposure and yield strategies
2. **Dynamic Optimization**: Real-time cost analysis drives strategy selection
3. **Capital Efficiency**: Leveraged exposure strategies enable higher yield allocation
4. **Modular Design**: Easy addition of new exposure methods and yield strategies
5. **Risk Management**: Comprehensive controls across all strategy combinations

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     IndexFundVaultV2                            │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                 ComposableRWABundle                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ ExposureStrategy│  │ ExposureStrategy│  │ ExposureStrategy│ │
│  │   (Primary)     │  │   (Secondary)   │  │   (Backup)      │ │
│  │                 │  │                 │  │                 │ │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │ │
│  │ │YieldStrategy│ │  │ │YieldStrategy│ │  │ │YieldStrategy│ │ │
│  │ │  Bundle     │ │  │ │  Bundle     │ │  │ │  Bundle     │ │ │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                 StrategyOptimizer                                │
│  • Cost Analysis Engine                                         │
│  • Risk Assessment                                              │
│  • Performance Tracking                                         │
│  • Rebalancing Logic                                            │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components Specification

### 1. IExposureStrategy Interface

```solidity
// src/interfaces/IExposureStrategy.sol
interface IExposureStrategy {
    enum StrategyType {
        PERPETUAL,
        TRS,
        DIRECT_TOKEN,
        SYNTHETIC_TOKEN,
        OPTIONS
    }

    struct ExposureInfo {
        StrategyType strategyType;
        string name;
        address underlyingAsset;
        uint256 leverage;
        uint256 collateralRatio;
        uint256 currentExposure;
        uint256 maxCapacity;
        uint256 currentCost; // funding rate, fees, etc.
        uint256 riskScore;
        bool isActive;
    }

    struct CostBreakdown {
        uint256 fundingRate;    // For perpetuals
        uint256 borrowRate;     // For TRS
        uint256 managementFee;  // Protocol fees
        uint256 slippageCost;   // Estimated slippage
        uint256 totalCostBps;   // Total cost in basis points
    }

    function getExposureInfo() external view returns (ExposureInfo memory);
    function getCostBreakdown() external view returns (CostBreakdown memory);
    function estimateExposureCost(uint256 amount, uint256 timeHorizon) external view returns (uint256);
    
    function openExposure(uint256 amount) external returns (bool success, uint256 actualExposure);
    function closeExposure(uint256 amount) external returns (bool success, uint256 actualClosed);
    function adjustExposure(int256 delta) external returns (bool success);
    
    function getCurrentExposureValue() external view returns (uint256);
    function getCollateralRequired(uint256 exposureAmount) external view returns (uint256);
    function getLiquidationPrice() external view returns (uint256);
    
    function harvestYield() external returns (uint256 harvested);
    function emergencyExit() external returns (uint256 recovered);
}
```

### 2. ComposableRWABundle Contract

```solidity
// src/ComposableRWABundle.sol
contract ComposableRWABundle is IAssetWrapper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct StrategyAllocation {
        IExposureStrategy strategy;
        uint256 targetAllocation;  // Basis points
        uint256 currentAllocation; // Basis points
        uint256 maxAllocation;     // Risk limit
        bool isPrimary;
        bool isActive;
    }

    struct YieldStrategyBundle {
        IYieldStrategy[] strategies;
        uint256[] allocations;
        uint256 totalYieldCapital;
        uint256 leverageRatio; // How much we can allocate due to leveraged exposure
    }

    // State variables
    IERC20 public baseAsset;
    IPriceOracle public priceOracle;
    StrategyOptimizer public optimizer;
    
    StrategyAllocation[] public exposureStrategies;
    YieldStrategyBundle public yieldBundle;
    
    uint256 public totalTargetExposure;
    uint256 public totalAllocatedCapital;
    uint256 public lastOptimization;
    uint256 public optimizationInterval = 1 hours;
    
    // Risk management
    uint256 public maxLeverage = 300; // 3x
    uint256 public maxStrategyCount = 5;
    uint256 public rebalanceThreshold = 500; // 5%
    bool public emergencyMode = false;

    // Events
    event StrategyAdded(address indexed strategy, uint256 targetAllocation, bool isPrimary);
    event StrategyRemoved(address indexed strategy);
    event AllocationAdjusted(address indexed strategy, uint256 oldAllocation, uint256 newAllocation);
    event StrategyOptimized(uint256 totalCostSaved, uint256 timestamp);
    event EmergencyModeActivated(string reason);
    event YieldBundleUpdated(uint256 totalYieldCapital, uint256 leverageRatio);

    function addExposureStrategy(
        IExposureStrategy strategy,
        uint256 targetAllocation,
        uint256 maxAllocation,
        bool isPrimary
    ) external onlyOwner;

    function removeExposureStrategy(address strategy) external onlyOwner;
    
    function updateYieldBundle(
        IYieldStrategy[] calldata strategies,
        uint256[] calldata allocations
    ) external onlyOwner;

    function optimizeAllocations() external returns (bool success);
    function rebalanceStrategies() external returns (bool success);
    
    // Implement IAssetWrapper interface
    function allocateCapital(uint256 amount) external override returns (bool);
    function withdrawCapital(uint256 amount) external override returns (uint256);
    function getValueInBaseAsset() external view override returns (uint256);
    function harvestYield() external override returns (uint256);
}
```

### 3. Strategy Optimizer

```solidity
// src/StrategyOptimizer.sol
contract StrategyOptimizer is Ownable {
    struct OptimizationParams {
        uint256 gasThreshold;      // Minimum gas cost savings to justify rebalance
        uint256 minCostSaving;     // Minimum cost saving in basis points
        uint256 maxSlippage;       // Maximum acceptable slippage
        uint256 timeHorizon;       // Optimization time horizon (seconds)
        uint256 riskPenalty;       // Risk penalty factor
    }

    struct StrategyScore {
        address strategy;
        uint256 costScore;         // Lower is better
        uint256 riskScore;         // Lower is better
        uint256 liquidityScore;    // Higher is better
        uint256 totalScore;        // Weighted composite score
        bool isRecommended;
    }

    OptimizationParams public params;
    IPriceOracle public priceOracle;
    
    // Historical tracking for trend analysis
    mapping(address => uint256[]) public historicalCosts;
    mapping(address => uint256) public lastCostUpdate;

    function analyzeStrategies(
        IExposureStrategy[] calldata strategies,
        uint256 targetExposure,
        uint256 timeHorizon
    ) external view returns (StrategyScore[] memory scores);

    function calculateOptimalAllocation(
        IExposureStrategy[] calldata strategies,
        uint256 totalCapital,
        uint256 targetExposure
    ) external view returns (uint256[] memory allocations);

    function shouldRebalance(
        StrategyAllocation[] calldata current,
        uint256[] calldata optimal
    ) external view returns (bool shouldRebalance, uint256 expectedSaving);

    function getRebalanceInstructions(
        StrategyAllocation[] calldata current,
        uint256[] calldata optimal
    ) external pure returns (RebalanceInstruction[] memory instructions);
}
```

## Specific Strategy Implementations

### 1. Enhanced Perpetual Strategy

```solidity
// src/strategies/EnhancedPerpetualStrategy.sol
contract EnhancedPerpetualStrategy is IExposureStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPerpetualRouter public perpetualRouter;
    IYieldStrategy[] public yieldStrategies;
    uint256[] public yieldAllocations;
    
    bytes32 public marketId;
    uint256 public leverage;
    uint256 public collateralRatio;
    bytes32 public activePositionId;
    
    // Enhanced features
    uint256 public fundingRateThreshold = 100; // 1% funding rate threshold
    uint256 public autoHedgeRatio = 5000; // 50% auto-hedge when funding is negative
    bool public dynamicLeverageEnabled = true;
    
    struct FundingHistory {
        int256 rate;
        uint256 timestamp;
    }
    
    FundingHistory[] public fundingHistory;
    uint256 public maxHistoryLength = 100;

    function openExposure(uint256 amount) external override returns (bool success, uint256 actualExposure) {
        // Calculate optimal leverage based on current funding rates
        uint256 optimalLeverage = calculateOptimalLeverage();
        
        // Open perpetual position
        uint256 collateralNeeded = (amount * collateralRatio) / BASIS_POINTS;
        uint256 yieldCapital = amount - collateralNeeded;
        
        // Open position with calculated leverage
        activePositionId = perpetualRouter.openPosition(
            marketId,
            int256(amount * optimalLeverage / 100),
            optimalLeverage,
            collateralNeeded
        );
        
        // Allocate remaining capital to yield strategies
        _allocateToYieldStrategies(yieldCapital);
        
        return (true, amount * optimalLeverage / 100);
    }

    function calculateOptimalLeverage() public view returns (uint256) {
        if (!dynamicLeverageEnabled) return leverage;
        
        int256 currentFunding = perpetualRouter.getFundingRate(marketId);
        
        // Reduce leverage if funding is expensive
        if (currentFunding > int256(fundingRateThreshold)) {
            return leverage * 80 / 100; // Reduce by 20%
        } else if (currentFunding < -int256(fundingRateThreshold)) {
            return leverage * 120 / 100; // Increase by 20%
        }
        
        return leverage;
    }

    function _allocateToYieldStrategies(uint256 amount) internal {
        uint256 remaining = amount;
        
        for (uint256 i = 0; i < yieldStrategies.length && remaining > 0; i++) {
            uint256 allocation = (amount * yieldAllocations[i]) / BASIS_POINTS;
            if (allocation > remaining) allocation = remaining;
            
            if (allocation > 0) {
                baseAsset.approve(address(yieldStrategies[i]), allocation);
                yieldStrategies[i].deposit(allocation);
                remaining -= allocation;
            }
        }
    }

    function getCostBreakdown() external view override returns (CostBreakdown memory) {
        int256 fundingRate = perpetualRouter.getFundingRate(marketId);
        
        return CostBreakdown({
            fundingRate: fundingRate >= 0 ? uint256(fundingRate) : 0,
            borrowRate: 0,
            managementFee: 10, // 0.1% management fee
            slippageCost: _estimateSlippage(),
            totalCostBps: _calculateTotalCost(fundingRate)
        });
    }

    function _estimateSlippage() internal view returns (uint256) {
        // Implement slippage estimation based on position size and liquidity
        return 5; // 0.05% estimated slippage
    }

    function _calculateTotalCost(int256 fundingRate) internal view returns (uint256) {
        uint256 totalCost = 15; // Base costs: 0.1% management + 0.05% slippage
        
        if (fundingRate > 0) {
            totalCost += uint256(fundingRate);
        }
        
        return totalCost;
    }
}
```

### 2. Total Return Swap (TRS) Strategy

```solidity
// src/strategies/TotalReturnSwapStrategy.sol
contract TotalReturnSwapStrategy is IExposureStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct TRSContract {
        address counterparty;
        bytes32 underlyingAssetId;
        uint256 notionalAmount;
        uint256 leverage;
        uint256 collateralPosted;
        uint256 borrowRate;
        uint256 startTime;
        uint256 maturityTime;
        bool isActive;
    }

    ITRSProvider public trsProvider;
    IYieldStrategy[] public yieldStrategies;
    uint256[] public yieldAllocations;
    
    TRSContract public activeTRS;
    uint256 public maxMaturity = 90 days;
    uint256 public minMaturity = 7 days;
    
    // Risk management
    uint256 public maxCounterpartyExposure = 1000000e6; // $1M USDC
    mapping(address => uint256) public counterpartyExposure;
    mapping(address => uint256) public counterpartyRating; // 1-10 scale

    function openExposure(uint256 amount) external override returns (bool success, uint256 actualExposure) {
        // Find best TRS provider
        (address bestCounterparty, uint256 bestRate) = _findBestTRSProvider(amount);
        
        require(bestCounterparty != address(0), "No suitable counterparty");
        require(counterpartyExposure[bestCounterparty] + amount <= maxCounterpartyExposure, "Counterparty limit");
        
        uint256 collateralNeeded = _calculateCollateralRequirement(amount, leverage);
        uint256 yieldCapital = amount - collateralNeeded;
        
        // Create TRS contract
        activeTRS = TRSContract({
            counterparty: bestCounterparty,
            underlyingAssetId: bytes32("SP500-USD"),
            notionalAmount: amount * leverage / 100,
            leverage: leverage,
            collateralPosted: collateralNeeded,
            borrowRate: bestRate,
            startTime: block.timestamp,
            maturityTime: block.timestamp + _calculateOptimalMaturity(bestRate),
            isActive: true
        });
        
        // Post collateral
        baseAsset.approve(address(trsProvider), collateralNeeded);
        trsProvider.postCollateral(activeTRS.counterparty, collateralNeeded);
        
        // Allocate remaining capital to yield strategies
        _allocateToYieldStrategies(yieldCapital);
        
        counterpartyExposure[bestCounterparty] += amount;
        
        return (true, amount * leverage / 100);
    }

    function _findBestTRSProvider(uint256 amount) internal view returns (address, uint256) {
        // Query multiple TRS providers for best rates
        // Implementation would integrate with real TRS markets
        return (address(0x1234), 200); // 2% borrow rate
    }

    function _calculateOptimalMaturity(uint256 borrowRate) internal view returns (uint256) {
        // Optimize maturity based on yield curve and funding costs
        if (borrowRate < 100) { // < 1%
            return maxMaturity; // Lock in good rates longer
        } else if (borrowRate > 500) { // > 5%
            return minMaturity; // Keep short to re-negotiate quickly
        }
        return 30 days; // Default 30 days
    }

    function getCostBreakdown() external view override returns (CostBreakdown memory) {
        return CostBreakdown({
            fundingRate: 0,
            borrowRate: activeTRS.borrowRate,
            managementFee: 15, // 0.15% management fee
            slippageCost: 10, // 0.1% estimated slippage
            totalCostBps: activeTRS.borrowRate + 25 // Total: borrow rate + management + slippage
        });
    }

    function rolloverTRS() external onlyOwner returns (bool) {
        require(activeTRS.isActive, "No active TRS");
        require(block.timestamp >= activeTRS.maturityTime - 1 days, "Too early to rollover");
        
        // Find new best rate
        (address newCounterparty, uint256 newRate) = _findBestTRSProvider(activeTRS.notionalAmount);
        
        // If significantly better, rollover
        if (newRate + 50 < activeTRS.borrowRate) { // 0.5% improvement threshold
            _closeTRS();
            uint256 collateralReturned = activeTRS.collateralPosted;
            _openNewTRS(newCounterparty, newRate, collateralReturned);
            return true;
        }
        
        return false;
    }
}
```

### 3. Direct Token Strategy

```solidity
// src/strategies/DirectTokenStrategy.sol
contract DirectTokenStrategy is IExposureStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public rwaToken; // e.g., tokenized Real Estate, Gold, etc.
    IYieldStrategy[] public yieldStrategies;
    uint256[] public yieldAllocations;
    
    uint256 public tokenAllocation = 8000; // 80% to RWA token
    uint256 public yieldAllocation = 2000; // 20% to yield strategies
    
    // Liquidity management
    uint256 public liquidityBuffer = 500; // 5% liquidity buffer
    uint256 public maxSlippageToleranceBps = 200; // 2%
    IDEXRouter public dexRouter;

    function openExposure(uint256 amount) external override returns (bool success, uint256 actualExposure) {
        uint256 tokenAmount = (amount * tokenAllocation) / BASIS_POINTS;
        uint256 yieldAmount = amount - tokenAmount;
        
        // Buy RWA tokens via DEX
        uint256 expectedTokens = _getExpectedTokenAmount(tokenAmount);
        uint256 minTokens = expectedTokens * (BASIS_POINTS - maxSlippageToleranceBps) / BASIS_POINTS;
        
        baseAsset.approve(address(dexRouter), tokenAmount);
        uint256 actualTokens = dexRouter.swapExactTokensForTokens(
            tokenAmount,
            minTokens,
            address(baseAsset),
            address(rwaToken)
        );
        
        // Calculate actual exposure value
        uint256 tokenValue = _getTokenValue(actualTokens);
        
        // Allocate to yield strategies
        _allocateToYieldStrategies(yieldAmount);
        
        return (true, tokenValue);
    }

    function closeExposure(uint256 amount) external override returns (bool success, uint256 actualClosed) {
        uint256 totalValue = getCurrentExposureValue();
        uint256 ratio = (amount * BASIS_POINTS) / totalValue;
        
        // Calculate token amount to sell
        uint256 tokenBalance = rwaToken.balanceOf(address(this));
        uint256 tokensToSell = (tokenBalance * ratio) / BASIS_POINTS;
        
        // Sell tokens via DEX
        uint256 minBaseAsset = _getExpectedBaseAmount(tokensToSell);
        minBaseAsset = minBaseAsset * (BASIS_POINTS - maxSlippageToleranceBps) / BASIS_POINTS;
        
        rwaToken.approve(address(dexRouter), tokensToSell);
        uint256 baseReceived = dexRouter.swapExactTokensForTokens(
            tokensToSell,
            minBaseAsset,
            address(rwaToken),
            address(baseAsset)
        );
        
        // Withdraw from yield strategies proportionally
        uint256 yieldWithdrawn = _withdrawFromYieldStrategies(ratio);
        
        return (true, baseReceived + yieldWithdrawn);
    }

    function getCostBreakdown() external view override returns (CostBreakdown memory) {
        uint256 slippageCost = _estimateSlippage();
        uint256 managementFee = 10; // 0.1%
        
        return CostBreakdown({
            fundingRate: 0,
            borrowRate: 0,
            managementFee: managementFee,
            slippageCost: slippageCost,
            totalCostBps: managementFee + slippageCost
        });
    }

    function _getExpectedTokenAmount(uint256 baseAmount) internal view returns (uint256) {
        return dexRouter.getAmountsOut(baseAmount, address(baseAsset), address(rwaToken));
    }

    function _getTokenValue(uint256 tokenAmount) internal view returns (uint256) {
        uint256 tokenPrice = priceOracle.getPrice(address(rwaToken));
        return (tokenAmount * tokenPrice) / 10**18;
    }

    function _estimateSlippage() internal view returns (uint256) {
        // Estimate slippage based on liquidity and trade size
        return 50; // 0.5% estimated slippage
    }
}
```

## Updated Test Framework

### Integration Tests
```solidity
// test/ComposableRWABundle.t.sol
contract ComposableRWABundleTest is Test {
    function test_MultiStrategyAllocation() public {
        // Test allocation across perpetual, TRS, and direct token strategies
    }
    
    function test_DynamicOptimization() public {
        // Test strategy switching based on funding rate changes
    }
    
    function test_YieldStrategyIntegration() public {
        // Test yield strategies with leveraged exposure
    }
    
    function test_RiskManagementLimits() public {
        // Test all risk management controls
    }
    
    function test_EmergencyModeActivation() public {
        // Test emergency procedures
    }
}
```

### Backtest Framework Updates
```solidity
// backtesting/ComposableRWABacktester.sol
contract ComposableRWABacktester {
    struct StrategyPerformance {
        address strategy;
        uint256 totalReturn;
        uint256 volatility;
        uint256 maxDrawdown;
        uint256 sharpeRatio;
        uint256 averageCost;
        uint256 rebalanceCount;
    }
    
    function runMultiStrategyBacktest(
        uint256 startTime,
        uint256 endTime,
        uint256 initialCapital,
        ComposableRWABundle bundle
    ) external returns (StrategyPerformance[] memory performance);
    
    function simulateMarketConditions(
        uint256 timestamp,
        int256 fundingRate,
        uint256 volatility,
        int256 priceMovement
    ) external;
    
    function analyzeCostEfficiency(
        StrategyPerformance[] memory strategies
    ) external pure returns (uint256 optimalAllocation);
}
```

## Security Enhancements

### 1. Multi-Layered Risk Management
- **Strategy Level**: Individual position limits, leverage caps
- **Bundle Level**: Total exposure limits, correlation analysis
- **Vault Level**: Aggregate risk metrics, liquidity requirements

### 2. Oracle Security
- Multiple price feeds for each strategy
- Deviation checks between strategies
- Circuit breakers for extreme price movements

### 3. Smart Contract Security
- Timelock for critical parameter changes
- Multi-signature for strategy additions
- Emergency pause functionality
- Formal verification for core logic

## Implementation Roadmap

### Phase 1: Core Infrastructure (4-6 weeks)
1. Implement `IExposureStrategy` interface
2. Develop `ComposableRWABundle` contract
3. Create `StrategyOptimizer` contract
4. Basic test coverage

### Phase 2: Strategy Implementations (6-8 weeks)
1. Enhanced Perpetual Strategy
2. TRS Strategy (with mock providers)
3. Direct Token Strategy
4. Comprehensive testing

### Phase 3: Optimization & Risk Management (4-6 weeks)
1. Dynamic rebalancing logic
2. Risk management systems
3. Performance monitoring
4. Security audits

### Phase 4: Integration & Deployment (2-4 weeks)
1. Vault integration
2. Frontend updates
3. Documentation
4. Mainnet deployment

## Areas for Enhancement

### Architecture Improvements
1. **Modular Yield Strategies**: Separate yield strategy optimization from exposure strategies
2. **Cross-Chain Support**: Enable RWA exposure across multiple chains
3. **Advanced Analytics**: Real-time performance attribution and risk decomposition
4. **Governance Integration**: DAO voting on strategy parameters and additions

### Security Enhancements
1. **Formal Verification**: Mathematical proofs for critical functions
2. **Insurance Integration**: Protocol insurance for strategy failures
3. **MEV Protection**: Front-running protection for strategy switches
4. **Upgrade Patterns**: Safe upgrade mechanisms for strategy contracts

### Performance Optimizations
1. **Gas Optimization**: Batch operations and efficient storage patterns
2. **Prediction Models**: ML-based cost prediction for strategy optimization
3. **Liquidity Management**: Advanced liquidity planning and provisioning
4. **Arbitrage Detection**: Automated arbitrage opportunities between strategies

This specification provides a comprehensive framework for implementing composable RWA exposure strategies while maintaining security, efficiency, and flexibility. The modular design enables easy extension and optimization as new RWA exposure methods become available.