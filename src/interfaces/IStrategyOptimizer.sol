// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IExposureStrategy.sol";

/**
 * @title IStrategyOptimizer
 * @dev Interface for optimizing allocation across multiple exposure strategies
 * @notice Provides cost analysis and allocation optimization for RWA exposure strategies
 */
interface IStrategyOptimizer {
    /**
     * @dev Parameters for optimization calculations
     */
    struct OptimizationParams {
        uint256 gasThreshold;           // Minimum gas cost savings to justify rebalance (wei)
        uint256 minCostSavingBps;      // Minimum cost saving in basis points
        uint256 maxSlippageBps;        // Maximum acceptable slippage (basis points)
        uint256 timeHorizon;           // Optimization time horizon (seconds)
        uint256 riskPenalty;           // Risk penalty factor (basis points)
        uint256 liquidityWeight;       // Weight for liquidity considerations (basis points)
        uint256 diversificationBonus;  // Bonus for diversification (basis points)
        bool enableEmergencyMode;      // Whether emergency mode optimizations are enabled
    }

    /**
     * @dev Scoring result for an individual strategy
     */
    struct StrategyScore {
        address strategy;
        uint256 costScore;             // Cost score (lower is better, basis points)
        uint256 riskScore;             // Risk score (lower is better, 1-100)
        uint256 liquidityScore;        // Liquidity score (higher is better, 1-100)
        uint256 reliabilityScore;      // Historical reliability score (1-100)
        uint256 capacityScore;         // Available capacity score (1-100)
        uint256 totalScore;            // Weighted composite score
        uint256 recommendedAllocation; // Recommended allocation (basis points)
        bool isRecommended;            // Whether this strategy is recommended for use
        string reasoning;              // Human-readable reasoning for the score
    }

    /**
     * @dev Instructions for rebalancing between strategies
     */
    struct RebalanceInstruction {
        address fromStrategy;          // Strategy to reduce allocation from (address(0) for new capital)
        address toStrategy;            // Strategy to increase allocation to
        uint256 amount;                // Amount to move (in base asset terms)
        uint256 priority;              // Execution priority (1 = highest)
        uint256 maxSlippageBps;        // Maximum acceptable slippage for this instruction
        bool isEmergency;              // Whether this is an emergency rebalance
        string reasoning;              // Reason for this instruction
    }

    /**
     * @dev Results of optimization analysis
     */
    struct OptimizationResult {
        StrategyScore[] strategyScores;
        uint256[] optimalAllocations;  // Optimal allocations in basis points
        uint256 expectedCostSaving;    // Expected annual cost saving (basis points)
        uint256 expectedRiskReduction; // Expected risk reduction (1-100)
        uint256 implementationCost;    // Cost to implement changes (in base asset)
        bool shouldRebalance;          // Whether rebalancing is recommended
        uint256 confidence;            // Confidence in recommendation (1-100)
        RebalanceInstruction[] instructions;
    }

    /**
     * @dev Historical performance tracking
     */
    struct PerformanceMetrics {
        uint256 totalReturnBps;        // Total return in basis points
        uint256 volatilityBps;         // Volatility in basis points
        uint256 maxDrawdownBps;        // Maximum drawdown in basis points
        uint256 sharpeRatio;           // Sharpe ratio (scaled by 10000)
        uint256 averageCostBps;        // Average cost in basis points
        uint256 successRate;           // Success rate percentage (0-10000)
        uint256 avgExecutionTime;      // Average execution time (seconds)
        uint256 reliabilityScore;      // Overall reliability score (1-100)
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets current optimization parameters
     * @return params The current optimization parameters
     */
    function getOptimizationParams() external view returns (OptimizationParams memory params);

    /**
     * @dev Analyzes multiple strategies and provides scores
     * @param strategies Array of strategy addresses to analyze
     * @param targetExposure Total target exposure amount
     * @param timeHorizon Time horizon for analysis (seconds)
     * @return scores Array of strategy scores
     */
    function analyzeStrategies(
        address[] calldata strategies,
        uint256 targetExposure,
        uint256 timeHorizon
    ) external view returns (StrategyScore[] memory scores);

    /**
     * @dev Calculates optimal allocation across strategies
     * @param strategies Array of strategy addresses
     * @param totalCapital Total capital available for allocation
     * @param targetExposure Target total exposure amount
     * @return result Complete optimization result
     */
    function calculateOptimalAllocation(
        address[] calldata strategies,
        uint256 totalCapital,
        uint256 targetExposure
    ) external view returns (OptimizationResult memory result);

    /**
     * @dev Determines if rebalancing is beneficial
     * @param currentAllocations Current allocations (basis points)
     * @param optimalAllocations Optimal allocations (basis points)
     * @param strategies Array of strategy addresses
     * @return shouldRebalance Whether rebalancing is recommended
     * @return expectedSaving Expected cost saving in basis points
     * @return implementationCost Cost to implement rebalancing
     */
    function shouldRebalance(
        uint256[] calldata currentAllocations,
        uint256[] calldata optimalAllocations,
        address[] calldata strategies
    ) external view returns (bool shouldRebalance, uint256 expectedSaving, uint256 implementationCost);

    /**
     * @dev Gets detailed rebalancing instructions
     * @param currentAllocations Current allocations (basis points)
     * @param optimalAllocations Optimal allocations (basis points)
     * @param strategies Array of strategy addresses
     * @param totalValue Total value being rebalanced
     * @return instructions Array of rebalancing instructions
     */
    function getRebalanceInstructions(
        uint256[] calldata currentAllocations,
        uint256[] calldata optimalAllocations,
        address[] calldata strategies,
        uint256 totalValue
    ) external view returns (RebalanceInstruction[] memory instructions);

    /**
     * @dev Gets historical performance metrics for strategies
     * @param strategies Array of strategy addresses
     * @param lookbackPeriod Period to analyze (seconds)
     * @return metrics Array of performance metrics
     */
    function getPerformanceMetrics(
        address[] calldata strategies,
        uint256 lookbackPeriod
    ) external view returns (PerformanceMetrics[] memory metrics);

    /**
     * @dev Estimates gas cost for a rebalancing operation
     * @param instructions Array of rebalancing instructions
     * @return gasEstimate Estimated gas cost in wei
     */
    function estimateRebalanceGasCost(
        RebalanceInstruction[] calldata instructions
    ) external view returns (uint256 gasEstimate);

    /**
     * @dev Checks if any strategy is in emergency state
     * @param strategies Array of strategy addresses to check
     * @return hasEmergency Whether any strategy requires emergency action
     * @return emergencyStrategies Array of strategies in emergency state
     */
    function checkEmergencyStates(
        address[] calldata strategies
    ) external view returns (bool hasEmergency, address[] memory emergencyStrategies);

    // ============ STATE-CHANGING FUNCTIONS ============

    /**
     * @dev Updates optimization parameters
     * @param newParams New optimization parameters
     */
    function updateOptimizationParams(OptimizationParams calldata newParams) external;

    /**
     * @dev Records strategy performance data
     * @param strategy Strategy address
     * @param returnBps Return achieved (basis points)
     * @param costBps Cost incurred (basis points)
     * @param executionTime Time taken for execution (seconds)
     * @param wasSuccessful Whether the operation was successful
     */
    function recordPerformance(
        address strategy,
        int256 returnBps,
        uint256 costBps,
        uint256 executionTime,
        bool wasSuccessful
    ) external;

    /**
     * @dev Updates strategy risk assessment
     * @param strategy Strategy address
     * @param newRiskScore New risk score (1-100)
     * @param reasoning Reason for the update
     */
    function updateRiskAssessment(
        address strategy,
        uint256 newRiskScore,
        string calldata reasoning
    ) external;

    /**
     * @dev Records a rebalancing operation outcome
     * @param instructions Instructions that were executed
     * @param actualCosts Actual costs incurred
     * @param actualSlippage Actual slippage experienced
     * @param wasSuccessful Whether the rebalancing was successful
     */
    function recordRebalanceOutcome(
        RebalanceInstruction[] calldata instructions,
        uint256[] calldata actualCosts,
        uint256[] calldata actualSlippage,
        bool wasSuccessful
    ) external;

    // ============ EVENTS ============

    event OptimizationParamsUpdated(OptimizationParams newParams);
    event StrategyAnalyzed(address indexed strategy, uint256 totalScore, bool isRecommended);
    event OptimalAllocationCalculated(address[] strategies, uint256[] allocations, uint256 expectedSaving);
    event RebalanceRecommended(uint256 expectedSaving, uint256 implementationCost, uint256 confidence);
    event PerformanceRecorded(address indexed strategy, int256 returnBps, uint256 costBps, bool wasSuccessful);
    event RiskAssessmentUpdated(address indexed strategy, uint256 oldScore, uint256 newScore, string reasoning);
    event EmergencyDetected(address indexed strategy, string reason);
    event RebalanceOutcomeRecorded(bool wasSuccessful, uint256 totalCost, uint256 totalSlippage);
}