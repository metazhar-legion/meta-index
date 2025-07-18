// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategyOptimizer} from "./interfaces/IStrategyOptimizer.sol";
import {IExposureStrategy} from "./interfaces/IExposureStrategy.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title StrategyOptimizer
 * @dev Optimizes allocation across multiple RWA exposure strategies
 * @notice Provides cost analysis, risk assessment, and allocation optimization
 */
contract StrategyOptimizer is IStrategyOptimizer, Ownable {
    using Math for uint256;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_STRATEGIES = 10;
    uint256 public constant PERFORMANCE_HISTORY_LENGTH = 100;

    // State variables
    OptimizationParams public optimizationParams;
    IPriceOracle public priceOracle;

    // Performance tracking
    mapping(address => uint256[]) private strategyReturns;
    mapping(address => uint256[]) private strategyCosts;
    mapping(address => uint256[]) private strategyExecutionTimes;
    mapping(address => bool[]) private strategySuccessHistory;
    mapping(address => uint256) public strategyRiskScores;
    mapping(address => uint256) public lastPerformanceUpdate;

    // Gas estimation
    uint256 public baseGasPerInstruction = 200000;
    uint256 public gasPerStrategySwitch = 150000;

    /**
     * @dev Constructor
     * @param _priceOracle Address of the price oracle
     */
    constructor(address _priceOracle) Ownable(msg.sender) {
        if (_priceOracle == address(0)) revert CommonErrors.ZeroAddress();
        
        priceOracle = IPriceOracle(_priceOracle);
        
        // Initialize default optimization parameters
        optimizationParams = OptimizationParams({
            gasThreshold: 0.001 ether,      // 0.001 ETH minimum gas savings
            minCostSavingBps: 10,           // 0.1% minimum cost saving
            maxSlippageBps: 200,            // 2% maximum slippage
            timeHorizon: 30 days,           // 30-day optimization horizon
            riskPenalty: 100,               // 1% risk penalty per risk point
            liquidityWeight: 500,           // 5% weight for liquidity
            diversificationBonus: 200,      // 2% bonus for diversification
            enableEmergencyMode: true       // Emergency mode enabled
        });
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets current optimization parameters
     * @return params The current optimization parameters
     */
    function getOptimizationParams() external view override returns (OptimizationParams memory params) {
        return optimizationParams;
    }

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
    ) external view override returns (StrategyScore[] memory scores) {
        if (strategies.length == 0) revert CommonErrors.EmptyArray();
        if (strategies.length > MAX_STRATEGIES) revert CommonErrors.ValueTooHigh();
        if (targetExposure == 0) revert CommonErrors.ValueTooLow();

        scores = new StrategyScore[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            scores[i] = _analyzeStrategy(strategies[i], targetExposure, timeHorizon);
        }

        return scores;
    }

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
    ) external view override returns (OptimizationResult memory result) {
        if (strategies.length == 0) revert CommonErrors.EmptyArray();
        if (totalCapital == 0 || targetExposure == 0) revert CommonErrors.ValueTooLow();

        // Get strategy scores
        StrategyScore[] memory scores = this.analyzeStrategies(strategies, targetExposure, optimizationParams.timeHorizon);
        
        // Calculate optimal allocations using a simplified optimization algorithm
        uint256[] memory allocations = _calculateOptimalAllocations(scores, totalCapital, targetExposure);
        
        // Calculate expected benefits
        (uint256 expectedCostSaving, uint256 expectedRiskReduction) = _calculateExpectedBenefits(scores, allocations);
        
        // Estimate implementation cost
        uint256 implementationCost = _estimateImplementationCost(strategies.length);
        
        // Determine if rebalancing is beneficial
        bool shouldRebalance = expectedCostSaving > optimizationParams.minCostSavingBps &&
                              implementationCost < optimizationParams.gasThreshold;

        result = OptimizationResult({
            strategyScores: scores,
            optimalAllocations: allocations,
            expectedCostSaving: expectedCostSaving,
            expectedRiskReduction: expectedRiskReduction,
            implementationCost: implementationCost,
            shouldRebalance: shouldRebalance,
            confidence: _calculateConfidence(scores),
            instructions: new RebalanceInstruction[](0) // Will be populated by getRebalanceInstructions
        });

        return result;
    }

    /**
     * @dev Determines if rebalancing is beneficial
     */
    function shouldRebalance(
        uint256[] calldata currentAllocations,
        uint256[] calldata optimalAllocations,
        address[] calldata strategies
    ) external view override returns (bool shouldRebalance, uint256 expectedSaving, uint256 implementationCost) {
        if (currentAllocations.length != optimalAllocations.length || 
            currentAllocations.length != strategies.length) {
            revert CommonErrors.InvalidValue();
        }

        // Calculate total deviation
        uint256 totalDeviation = 0;
        for (uint256 i = 0; i < currentAllocations.length; i++) {
            if (currentAllocations[i] > optimalAllocations[i]) {
                totalDeviation += currentAllocations[i] - optimalAllocations[i];
            } else {
                totalDeviation += optimalAllocations[i] - currentAllocations[i];
            }
        }

        // Estimate expected saving based on cost differences
        expectedSaving = _estimateRebalancingSaving(currentAllocations, optimalAllocations, strategies);
        
        // Estimate implementation cost
        implementationCost = _estimateImplementationCost(strategies.length);
        
        // Decide if rebalancing is worth it
        shouldRebalance = expectedSaving > optimizationParams.minCostSavingBps &&
                         totalDeviation > 500 && // 5% total deviation threshold
                         implementationCost < optimizationParams.gasThreshold;

        return (shouldRebalance, expectedSaving, implementationCost);
    }

    /**
     * @dev Gets detailed rebalancing instructions
     */
    function getRebalanceInstructions(
        uint256[] calldata currentAllocations,
        uint256[] calldata optimalAllocations,
        address[] calldata strategies,
        uint256 totalValue
    ) external view override returns (RebalanceInstruction[] memory instructions) {
        if (currentAllocations.length != optimalAllocations.length || 
            currentAllocations.length != strategies.length) {
            revert CommonErrors.InvalidValue();
        }

        // Count how many instructions we need
        uint256 instructionCount = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (currentAllocations[i] != optimalAllocations[i]) {
                instructionCount++;
            }
        }

        instructions = new RebalanceInstruction[](instructionCount);
        uint256 instructionIndex = 0;

        // Generate instructions for each strategy that needs rebalancing
        for (uint256 i = 0; i < strategies.length; i++) {
            if (currentAllocations[i] != optimalAllocations[i]) {
                uint256 amount;
                bool isIncrease = optimalAllocations[i] > currentAllocations[i];
                
                if (isIncrease) {
                    amount = ((optimalAllocations[i] - currentAllocations[i]) * totalValue) / BASIS_POINTS;
                } else {
                    amount = ((currentAllocations[i] - optimalAllocations[i]) * totalValue) / BASIS_POINTS;
                }

                instructions[instructionIndex] = RebalanceInstruction({
                    fromStrategy: isIncrease ? address(0) : strategies[i],
                    toStrategy: isIncrease ? strategies[i] : address(0),
                    amount: amount,
                    priority: _calculatePriority(strategies[i], isIncrease),
                    maxSlippageBps: optimizationParams.maxSlippageBps,
                    isEmergency: false,
                    reasoning: isIncrease ? "Increase allocation to lower cost strategy" : "Reduce allocation from higher cost strategy"
                });
                
                instructionIndex++;
            }
        }

        return instructions;
    }

    /**
     * @dev Gets historical performance metrics for strategies
     */
    function getPerformanceMetrics(
        address[] calldata strategies,
        uint256 lookbackPeriod
    ) external view override returns (PerformanceMetrics[] memory metrics) {
        metrics = new PerformanceMetrics[](strategies.length);
        
        for (uint256 i = 0; i < strategies.length; i++) {
            metrics[i] = _calculatePerformanceMetrics(strategies[i], lookbackPeriod);
        }
        
        return metrics;
    }

    /**
     * @dev Estimates gas cost for a rebalancing operation
     */
    function estimateRebalanceGasCost(
        RebalanceInstruction[] calldata instructions
    ) external view override returns (uint256 gasEstimate) {
        gasEstimate = baseGasPerInstruction;
        
        for (uint256 i = 0; i < instructions.length; i++) {
            gasEstimate += gasPerStrategySwitch;
            
            // Add extra gas for emergency operations
            if (instructions[i].isEmergency) {
                gasEstimate += 50000;
            }
        }
        
        return gasEstimate;
    }

    /**
     * @dev Checks if any strategy is in emergency state
     */
    function checkEmergencyStates(
        address[] calldata strategies
    ) external view override returns (bool hasEmergency, address[] memory emergencyStrategies) {
        uint256 emergencyCount = 0;
        
        // First pass: count emergencies
        for (uint256 i = 0; i < strategies.length; i++) {
            if (_isStrategyInEmergency(strategies[i])) {
                emergencyCount++;
            }
        }
        
        // Second pass: populate emergency strategies
        emergencyStrategies = new address[](emergencyCount);
        uint256 emergencyIndex = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            if (_isStrategyInEmergency(strategies[i])) {
                emergencyStrategies[emergencyIndex] = strategies[i];
                emergencyIndex++;
            }
        }
        
        hasEmergency = emergencyCount > 0;
        return (hasEmergency, emergencyStrategies);
    }

    // ============ STATE-CHANGING FUNCTIONS ============

    /**
     * @dev Updates optimization parameters
     */
    function updateOptimizationParams(OptimizationParams calldata newParams) external override onlyOwner {
        // Validate parameters
        if (newParams.minCostSavingBps > 1000) revert CommonErrors.ValueTooHigh(); // Max 10%
        if (newParams.maxSlippageBps > 1000) revert CommonErrors.ValueTooHigh(); // Max 10%
        if (newParams.timeHorizon < 1 hours || newParams.timeHorizon > 365 days) revert CommonErrors.ValueOutOfRange(newParams.timeHorizon, 1 hours, 365 days);
        
        optimizationParams = newParams;
        emit OptimizationParamsUpdated(newParams);
    }

    /**
     * @dev Records strategy performance data
     */
    function recordPerformance(
        address strategy,
        int256 returnBps,
        uint256 costBps,
        uint256 executionTime,
        bool wasSuccessful
    ) external override {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        
        // Store performance data (keep only latest N entries)
        _addToHistory(strategyReturns[strategy], uint256(returnBps >= 0 ? returnBps : 0));
        _addToHistory(strategyCosts[strategy], costBps);
        _addToHistory(strategyExecutionTimes[strategy], executionTime);
        _addToBoolHistory(strategySuccessHistory[strategy], wasSuccessful);
        
        lastPerformanceUpdate[strategy] = block.timestamp;
        
        emit PerformanceRecorded(strategy, returnBps, costBps, wasSuccessful);
    }

    /**
     * @dev Updates strategy risk assessment
     */
    function updateRiskAssessment(
        address strategy,
        uint256 newRiskScore,
        string calldata reasoning
    ) external override onlyOwner {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        if (newRiskScore > 100) revert CommonErrors.ValueTooHigh();
        
        uint256 oldScore = strategyRiskScores[strategy];
        strategyRiskScores[strategy] = newRiskScore;
        
        emit RiskAssessmentUpdated(strategy, oldScore, newRiskScore, reasoning);
    }

    /**
     * @dev Records a rebalancing operation outcome
     */
    function recordRebalanceOutcome(
        RebalanceInstruction[] calldata instructions,
        uint256[] calldata actualCosts,
        uint256[] calldata actualSlippage,
        bool wasSuccessful
    ) external override {
        if (instructions.length != actualCosts.length || 
            instructions.length != actualSlippage.length) {
            revert CommonErrors.InvalidValue();
        }
        
        uint256 totalCost = 0;
        uint256 totalSlippage = 0;
        
        for (uint256 i = 0; i < actualCosts.length; i++) {
            totalCost += actualCosts[i];
            totalSlippage += actualSlippage[i];
        }
        
        emit RebalanceOutcomeRecorded(wasSuccessful, totalCost, totalSlippage);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Analyzes a single strategy
     */
    function _analyzeStrategy(
        address strategy,
        uint256 targetExposure,
        uint256 timeHorizon
    ) internal view returns (StrategyScore memory score) {
        try IExposureStrategy(strategy).getExposureInfo() returns (IExposureStrategy.ExposureInfo memory info) {
            try IExposureStrategy(strategy).getCostBreakdown() returns (IExposureStrategy.CostBreakdown memory costs) {
                score.strategy = strategy;
                score.costScore = costs.totalCostBps;
                score.riskScore = info.riskScore;
                score.liquidityScore = _calculateLiquidityScore(info.maxCapacity, targetExposure);
                score.reliabilityScore = _calculateReliabilityScore(strategy);
                score.capacityScore = _calculateCapacityScore(info.currentExposure, info.maxCapacity, targetExposure);
                score.totalScore = _calculateTotalScore(score);
                score.isRecommended = score.totalScore >= 6000; // 60% threshold
                score.reasoning = _generateReasoning(score, info);
                
                emit StrategyAnalyzed(strategy, score.totalScore, score.isRecommended);
            } catch {
                // Strategy doesn't support cost breakdown
                score.strategy = strategy;
                score.isRecommended = false;
                score.reasoning = "Strategy does not support cost analysis";
            }
        } catch {
            // Strategy doesn't support exposure info
            score.strategy = strategy;
            score.isRecommended = false;
            score.reasoning = "Strategy does not implement required interfaces";
        }
        
        return score;
    }

    /**
     * @dev Calculates optimal allocations using a simplified algorithm
     */
    function _calculateOptimalAllocations(
        StrategyScore[] memory scores,
        uint256 totalCapital,
        uint256 targetExposure
    ) internal view returns (uint256[] memory allocations) {
        allocations = new uint256[](scores.length);
        
        // Simple allocation based on inverse cost scores
        uint256 totalInverseScore = 0;
        for (uint256 i = 0; i < scores.length; i++) {
            if (scores[i].isRecommended && scores[i].costScore > 0) {
                // Use inverse of cost score for allocation weight
                totalInverseScore += BASIS_POINTS / scores[i].costScore;
            }
        }
        
        if (totalInverseScore > 0) {
            for (uint256 i = 0; i < scores.length; i++) {
                if (scores[i].isRecommended && scores[i].costScore > 0) {
                    uint256 weight = (BASIS_POINTS / scores[i].costScore);
                    allocations[i] = (weight * BASIS_POINTS) / totalInverseScore;
                }
            }
        }
        
        return allocations;
    }

    /**
     * @dev Calculates expected benefits from optimization
     */
    function _calculateExpectedBenefits(
        StrategyScore[] memory scores,
        uint256[] memory allocations
    ) internal pure returns (uint256 expectedCostSaving, uint256 expectedRiskReduction) {
        uint256 weightedCost = 0;
        uint256 weightedRisk = 0;
        
        for (uint256 i = 0; i < scores.length; i++) {
            if (allocations[i] > 0) {
                weightedCost += (scores[i].costScore * allocations[i]) / BASIS_POINTS;
                weightedRisk += (scores[i].riskScore * allocations[i]) / BASIS_POINTS;
            }
        }
        
        // Simplified benefit calculation
        expectedCostSaving = weightedCost > 500 ? weightedCost - 500 : 0; // Assume 5% baseline cost
        expectedRiskReduction = weightedRisk < 50 ? 50 - weightedRisk : 0; // Assume 50 baseline risk
        
        return (expectedCostSaving, expectedRiskReduction);
    }

    /**
     * @dev Estimates implementation cost
     */
    function _estimateImplementationCost(uint256 strategyCount) internal view returns (uint256) {
        return baseGasPerInstruction + (strategyCount * gasPerStrategySwitch);
    }

    /**
     * @dev Calculates confidence level in the optimization
     */
    function _calculateConfidence(StrategyScore[] memory scores) internal pure returns (uint256) {
        uint256 totalRecommended = 0;
        uint256 avgScore = 0;
        
        for (uint256 i = 0; i < scores.length; i++) {
            if (scores[i].isRecommended) {
                totalRecommended++;
                avgScore += scores[i].totalScore;
            }
        }
        
        if (totalRecommended > 0) {
            avgScore = avgScore / totalRecommended;
            return Math.min(avgScore / 100, 100); // Convert to 0-100 scale
        }
        
        return 0;
    }

    /**
     * @dev Calculates liquidity score based on capacity
     */
    function _calculateLiquidityScore(uint256 maxCapacity, uint256 targetExposure) internal pure returns (uint256) {
        if (maxCapacity == 0) return 0;
        if (maxCapacity >= targetExposure * 2) return 100; // High liquidity
        if (maxCapacity >= targetExposure) return 75;      // Medium liquidity
        if (maxCapacity >= targetExposure / 2) return 50;  // Low liquidity
        return 25; // Very low liquidity
    }

    /**
     * @dev Calculates reliability score based on historical performance
     */
    function _calculateReliabilityScore(address strategy) internal view returns (uint256) {
        bool[] storage successHistory = strategySuccessHistory[strategy];
        if (successHistory.length == 0) return 50; // Default for new strategies
        
        uint256 successCount = 0;
        for (uint256 i = 0; i < successHistory.length; i++) {
            if (successHistory[i]) successCount++;
        }
        
        return (successCount * 100) / successHistory.length;
    }

    /**
     * @dev Calculates capacity score
     */
    function _calculateCapacityScore(
        uint256 currentExposure,
        uint256 maxCapacity,
        uint256 targetExposure
    ) internal pure returns (uint256) {
        if (maxCapacity == 0) return 0;
        
        uint256 availableCapacity = maxCapacity > currentExposure ? maxCapacity - currentExposure : 0;
        
        if (availableCapacity >= targetExposure) return 100;
        if (availableCapacity >= targetExposure * 75 / 100) return 75;
        if (availableCapacity >= targetExposure * 50 / 100) return 50;
        if (availableCapacity >= targetExposure * 25 / 100) return 25;
        return 0;
    }

    /**
     * @dev Calculates total score with weights
     */
    function _calculateTotalScore(StrategyScore memory score) internal view returns (uint256) {
        // Weights: cost 40%, risk 20%, liquidity 15%, reliability 15%, capacity 10%
        uint256 costComponent = (10000 - score.costScore) * 4000 / 10000; // Invert cost (lower cost = higher score)
        uint256 riskComponent = (100 - score.riskScore) * 2000 / 100;     // Invert risk (lower risk = higher score)
        uint256 liquidityComponent = score.liquidityScore * 1500 / 100;
        uint256 reliabilityComponent = score.reliabilityScore * 1500 / 100;
        uint256 capacityComponent = score.capacityScore * 1000 / 100;
        
        return costComponent + riskComponent + liquidityComponent + reliabilityComponent + capacityComponent;
    }

    /**
     * @dev Generates human-readable reasoning
     */
    function _generateReasoning(
        StrategyScore memory score,
        IExposureStrategy.ExposureInfo memory info
    ) internal pure returns (string memory) {
        if (!score.isRecommended) {
            if (score.costScore > 1000) return "High cost strategy";
            if (score.riskScore > 80) return "High risk strategy";
            if (score.capacityScore < 25) return "Insufficient capacity";
            return "Below recommendation threshold";
        }
        
        if (score.totalScore > 8000) return "Excellent strategy with low cost and risk";
        if (score.totalScore > 7000) return "Good strategy with competitive metrics";
        return "Acceptable strategy meeting minimum requirements";
    }

    /**
     * @dev Estimates saving from rebalancing
     */
    function _estimateRebalancingSaving(
        uint256[] calldata currentAllocations,
        uint256[] calldata optimalAllocations,
        address[] calldata strategies
    ) internal view returns (uint256) {
        // Simplified calculation based on cost differences
        uint256 currentWeightedCost = 0;
        uint256 optimalWeightedCost = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            try IExposureStrategy(strategies[i]).getCostBreakdown() returns (IExposureStrategy.CostBreakdown memory costs) {
                currentWeightedCost += (costs.totalCostBps * currentAllocations[i]) / BASIS_POINTS;
                optimalWeightedCost += (costs.totalCostBps * optimalAllocations[i]) / BASIS_POINTS;
            } catch {
                // Skip strategies that don't support cost breakdown
            }
        }
        
        return currentWeightedCost > optimalWeightedCost ? currentWeightedCost - optimalWeightedCost : 0;
    }

    /**
     * @dev Calculates priority for rebalancing instruction
     */
    function _calculatePriority(address strategy, bool isIncrease) internal view returns (uint256) {
        // Higher priority for emergency situations or high-benefit moves
        if (_isStrategyInEmergency(strategy)) return 1;
        if (isIncrease) return 2; // Prioritize moving to better strategies
        return 3; // Lower priority for moving away from strategies
    }

    /**
     * @dev Checks if strategy is in emergency state
     */
    function _isStrategyInEmergency(address strategy) internal view returns (bool) {
        try IExposureStrategy(strategy).getExposureInfo() returns (IExposureStrategy.ExposureInfo memory info) {
            // Check for emergency conditions
            if (!info.isActive) return true;
            if (info.riskScore > 90) return true;
            if (info.liquidationPrice > 0) {
                // Check if close to liquidation (this would need price oracle integration)
                return false; // Simplified for now
            }
        } catch {
            return true; // Strategy not responding is an emergency
        }
        
        return false;
    }

    /**
     * @dev Calculates performance metrics for a strategy
     */
    function _calculatePerformanceMetrics(
        address strategy,
        uint256 lookbackPeriod
    ) internal view returns (PerformanceMetrics memory metrics) {
        uint256[] storage returns_ = strategyReturns[strategy];
        uint256[] storage costs = strategyCosts[strategy];
        uint256[] storage executionTimes = strategyExecutionTimes[strategy];
        bool[] storage successHistory = strategySuccessHistory[strategy];
        
        if (returns_.length == 0) {
            // Return default metrics for strategies with no history
            return PerformanceMetrics({
                totalReturnBps: 0,
                volatilityBps: 0,
                maxDrawdownBps: 0,
                sharpeRatio: 0,
                averageCostBps: 0,
                successRate: 5000, // 50% default
                avgExecutionTime: 0,
                reliabilityScore: 50
            });
        }
        
        // Calculate average return
        uint256 totalReturn = 0;
        for (uint256 i = 0; i < returns_.length; i++) {
            totalReturn += returns_[i];
        }
        metrics.totalReturnBps = totalReturn / returns_.length;
        
        // Calculate average cost
        uint256 totalCost = 0;
        for (uint256 i = 0; i < costs.length; i++) {
            totalCost += costs[i];
        }
        metrics.averageCostBps = costs.length > 0 ? totalCost / costs.length : 0;
        
        // Calculate success rate
        uint256 successCount = 0;
        for (uint256 i = 0; i < successHistory.length; i++) {
            if (successHistory[i]) successCount++;
        }
        metrics.successRate = successHistory.length > 0 ? (successCount * BASIS_POINTS) / successHistory.length : 5000;
        
        // Calculate average execution time
        uint256 totalTime = 0;
        for (uint256 i = 0; i < executionTimes.length; i++) {
            totalTime += executionTimes[i];
        }
        metrics.avgExecutionTime = executionTimes.length > 0 ? totalTime / executionTimes.length : 0;
        
        // Simplified volatility and other metrics
        metrics.volatilityBps = 500; // 5% default volatility
        metrics.maxDrawdownBps = 1000; // 10% default max drawdown
        metrics.sharpeRatio = metrics.totalReturnBps > metrics.averageCostBps ? 
            ((metrics.totalReturnBps - metrics.averageCostBps) * 10000) / Math.max(metrics.volatilityBps, 1) : 0;
        metrics.reliabilityScore = Math.min(metrics.successRate / 100, 100);
        
        return metrics;
    }

    /**
     * @dev Adds value to history array, maintaining max length
     */
    function _addToHistory(uint256[] storage history, uint256 value) internal {
        history.push(value);
        if (history.length > PERFORMANCE_HISTORY_LENGTH) {
            // Remove first element by shifting all elements left
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history.pop();
        }
    }

    /**
     * @dev Adds boolean value to history array, maintaining max length
     */
    function _addToBoolHistory(bool[] storage history, bool value) internal {
        history.push(value);
        if (history.length > PERFORMANCE_HISTORY_LENGTH) {
            // Remove first element by shifting all elements left
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history.pop();
        }
    }

    /**
     * @dev Updates gas estimation parameters
     */
    function updateGasEstimation(
        uint256 _baseGasPerInstruction,
        uint256 _gasPerStrategySwitch
    ) external onlyOwner {
        baseGasPerInstruction = _baseGasPerInstruction;
        gasPerStrategySwitch = _gasPerStrategySwitch;
    }

    /**
     * @dev Updates price oracle
     */
    function updatePriceOracle(address _priceOracle) external onlyOwner {
        if (_priceOracle == address(0)) revert CommonErrors.ZeroAddress();
        priceOracle = IPriceOracle(_priceOracle);
    }
}