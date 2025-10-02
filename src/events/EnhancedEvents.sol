// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EnhancedEvents
 * @dev Enhanced event definitions with detailed monitoring data
 * @notice Quick-win improvement: Better events for monitoring and analytics
 */
library EnhancedEvents {
    
    // ============ STRATEGY OPERATION EVENTS ============
    
    event StrategyExposureOpened(
        address indexed strategy,
        address indexed user,
        uint256 indexed exposureId,
        uint256 amount,
        uint256 leverage,
        uint256 collateralUsed,
        uint256 timestamp,
        bytes32 transactionHash
    );
    
    event StrategyExposureClosed(
        address indexed strategy,
        address indexed user,
        uint256 indexed exposureId,
        uint256 amount,
        uint256 pnl, // Can be negative (stored as uint256 with sign bit)
        uint256 feesDeducted,
        uint256 timestamp,
        string closeReason
    );
    
    event StrategyExposureAdjusted(
        address indexed strategy,
        address indexed user,
        uint256 indexed exposureId,
        int256 deltaAmount, // Positive for increase, negative for decrease
        uint256 newTotalExposure,
        uint256 newLeverage,
        uint256 adjustmentCost,
        uint256 timestamp
    );
    
    event StrategyPerformanceUpdate(
        address indexed strategy,
        uint256 indexed reportId,
        uint256 totalValue,
        uint256 totalExposure,
        uint256 averageLeverage,
        int256 unrealizedPnL,
        uint256 riskScore,
        uint256 timestamp
    );

    // ============ ORACLE MONITORING EVENTS ============
    
    event OraclePriceUpdate(
        address indexed oracle,
        address indexed asset,
        uint256 indexed priceId,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 priceChange, // Absolute change
        uint256 priceChangePercentage, // In basis points
        uint256 timestamp,
        uint256 blockNumber
    );
    
    event OracleHealthStatusChanged(
        address indexed oracle,
        address indexed asset,
        bool isPrimaryHealthy,
        bool isFallbackHealthy,
        uint256 failureCount,
        uint256 lastSuccessfulUpdate,
        string healthSummary
    );
    
    event OracleFallbackActivated(
        address indexed asset,
        address primaryOracle,
        address fallbackOracle,
        uint256 primaryPrice,
        uint256 fallbackPrice,
        string activationReason,
        uint256 timestamp
    );
    
    event OracleCircuitBreakerTriggered(
        address indexed asset,
        address indexed oracle,
        string triggerReason,
        uint256 failureCount,
        uint256 priceDeviation,
        uint256 timestamp,
        address triggeredBy
    );

    // ============ SECURITY & PROTECTION EVENTS ============
    
    event FlashLoanProtectionTriggered(
        address indexed user,
        address indexed strategy,
        uint256 amount,
        string protectionType, // "same_block", "holding_period", "suspicious_pattern"
        uint256 blockNumber,
        uint256 timestamp,
        bytes32 patternHash
    );
    
    event MEVProtectionActivated(
        address indexed user,
        address indexed strategy,
        string mevType, // "sandwich", "frontrun", "backrun"
        uint256 detectedSlippage,
        uint256 expectedSlippage,
        uint256 priceImpact,
        uint256 timestamp
    );
    
    event SuspiciousActivityDetected(
        address indexed user,
        address indexed strategy,
        string activityType,
        uint256 activityScore, // 0-100 risk score
        uint256 patternCount,
        string detailsHash, // Hash of detailed pattern data
        uint256 timestamp
    );
    
    event SecurityParametersUpdated(
        address indexed strategy,
        string parameterType, // "flash_loan", "mev", "liquidation", etc.
        string parameterName,
        uint256 oldValue,
        uint256 newValue,
        address updatedBy,
        uint256 timestamp
    );

    // ============ LIQUIDATION & RISK EVENTS ============
    
    event LiquidationExecuted(
        bytes32 indexed positionId,
        address indexed strategy,
        address indexed liquidator,
        uint256 liquidatedAmount,
        uint256 collateralSeized,
        uint256 liquidatorReward,
        uint256 protocolPenalty,
        uint256 healthFactorBefore,
        uint256 healthFactorAfter,
        uint256 timestamp
    );
    
    event RiskThresholdBreached(
        address indexed strategy,
        bytes32 indexed positionId,
        string riskType, // "leverage", "concentration", "liquidity", "correlation"
        uint256 currentValue,
        uint256 threshold,
        uint256 severity, // 1-10 scale
        uint256 timestamp
    );
    
    event PositionHealthUpdate(
        bytes32 indexed positionId,
        address indexed strategy,
        uint256 healthFactor,
        uint256 collateralRatio,
        uint256 liquidationPrice,
        uint256 currentPrice,
        bool isLiquidatable,
        uint256 timestamp
    );
    
    event EmergencyActionTaken(
        address indexed strategy,
        string actionType, // "pause", "liquidate", "exit", "circuit_breaker"
        string reason,
        uint256 affectedAmount,
        address triggeredBy,
        uint256 timestamp
    );

    // ============ FEE COLLECTION & TREASURY EVENTS ============
    
    event FeesCollected(
        address indexed strategy,
        address indexed collector,
        uint256 managementFees,
        uint256 performanceFees,
        uint256 entryFees,
        uint256 exitFees,
        uint256 totalFeesCollected,
        uint256 strategyAUM,
        uint256 timestamp
    );
    
    event FeesDistributed(
        address indexed recipient,
        string recipientRole, // "treasury", "stakers", "team", "dao"
        uint256 amount,
        uint256 percentage,
        uint256 totalDistributed,
        uint256 timestamp
    );
    
    event PerformanceFeeCalculated(
        address indexed strategy,
        uint256 currentNAV,
        uint256 highWaterMark,
        uint256 performanceFee,
        uint256 performancePeriod,
        int256 totalReturn,
        uint256 timestamp
    );
    
    event TreasuryBalanceUpdate(
        uint256 totalBalance,
        uint256 managementFeePool,
        uint256 performanceFeePool,
        uint256 pendingDistribution,
        uint256 distributedAmount,
        uint256 timestamp
    );

    // ============ OPTIMIZATION & REBALANCING EVENTS ============
    
    event StrategyOptimizationExecuted(
        address indexed optimizer,
        uint256 indexed optimizationId,
        uint256 strategiesAnalyzed,
        uint256 strategiesRebalanced,
        uint256 totalCostSaving,
        uint256 expectedRiskReduction,
        uint256 gasUsed,
        uint256 timestamp
    );
    
    event AllocationRebalanced(
        address indexed strategy,
        uint256 oldAllocation,
        uint256 newAllocation,
        uint256 amountMoved,
        string rebalanceReason, // "cost_optimization", "risk_management", "capacity_limit"
        uint256 rebalanceCost,
        uint256 timestamp
    );
    
    event CapitalEfficiencyImproved(
        address indexed strategy,
        uint256 totalCapital,
        uint256 effectiveExposure,
        uint256 yieldGeneratingCapital,
        uint256 efficiencyRatio, // Basis points
        uint256 improvementDelta,
        uint256 timestamp
    );

    // ============ USER INTERACTION EVENTS ============
    
    event UserDeposit(
        address indexed user,
        address indexed strategy,
        uint256 indexed depositId,
        uint256 amount,
        uint256 sharesReceived,
        uint256 entryFee,
        uint256 totalUserShares,
        uint256 strategyTotalShares,
        uint256 timestamp
    );
    
    event UserWithdrawal(
        address indexed user,
        address indexed strategy,
        uint256 indexed withdrawalId,
        uint256 sharesRedeemed,
        uint256 amountReceived,
        uint256 exitFee,
        uint256 remainingUserShares,
        uint256 strategyTotalShares,
        uint256 timestamp
    );
    
    event UserRoleChanged(
        address indexed user,
        string oldRole, // "investor", "dao_member", "portfolio_manager", "composable_rwa_user"
        string newRole,
        address changedBy,
        uint256 timestamp
    );

    // ============ SYSTEM & GOVERNANCE EVENTS ============
    
    event ProtocolParameterUpdated(
        string indexed parameterCategory, // "fee", "risk", "oracle", "optimization"
        string parameterName,
        uint256 oldValue,
        uint256 newValue,
        address updatedBy,
        uint256 effectiveTimestamp,
        string changeReason
    );
    
    event GovernanceProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string proposalType, // "parameter_change", "strategy_addition", "emergency_action"
        string description,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 timestamp
    );
    
    event GovernanceVoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower,
        string reason,
        uint256 timestamp
    );
    
    event SystemUpgrade(
        address indexed oldImplementation,
        address indexed newImplementation,
        string upgradeType, // "minor", "major", "security", "emergency"
        uint256 affectedStrategies,
        address performedBy,
        uint256 timestamp
    );

    // ============ AUTOMATION & KEEPER EVENTS ============
    
    event AutomatedTaskExecuted(
        address indexed executor,
        string taskType, // "fee_collection", "rebalancing", "liquidation_check", "health_update"
        uint256 tasksCompleted,
        uint256 gasUsed,
        uint256 gasReimbursed,
        uint256 executionCost,
        uint256 timestamp
    );
    
    event KeeperPerformanceUpdate(
        address indexed keeper,
        uint256 tasksExecuted,
        uint256 successRate, // Basis points
        uint256 averageGasUsed,
        uint256 totalRewardsEarned,
        uint256 performanceScore,
        uint256 timestamp
    );
    
    // ============ ANALYTICS & REPORTING EVENTS ============
    
    event DailyMetricsSnapshot(
        uint256 indexed snapshotId,
        uint256 totalValueLocked,
        uint256 totalExposure,
        uint256 averageLeverage,
        uint256 totalFeesCollected,
        uint256 activeUsers,
        uint256 activeStrategies,
        int256 dailyPnL,
        uint256 timestamp
    );
    
    event StrategyBenchmarkUpdate(
        address indexed strategy,
        uint256 strategyReturn, // Basis points
        uint256 benchmarkReturn, // Basis points
        int256 alpha, // Strategy return - benchmark return
        uint256 volatility,
        uint256 sharpeRatio,
        uint256 maxDrawdown,
        uint256 timestamp
    );

    // ============ ERROR & WARNING EVENTS ============
    
    event SystemWarning(
        string indexed warningCategory,
        string warningType,
        string message,
        uint256 severity, // 1-5 scale
        address reportedBy,
        uint256 timestamp
    );
    
    event ErrorRecovered(
        string indexed errorType,
        string errorMessage,
        string recoveryAction,
        uint256 affectedAmount,
        address recoveredBy,
        uint256 timestamp
    );

    // ============ EVENT EMISSION HELPERS ============
    
    /**
     * @dev Emits a comprehensive strategy operation event
     */
    function emitStrategyOperation(
        address strategy,
        address user,
        string memory operationType,
        uint256 amount,
        uint256 leverage,
        uint256 fees
    ) internal {
        uint256 exposureId = uint256(keccak256(abi.encodePacked(strategy, user, block.timestamp)));
        
        if (keccak256(bytes(operationType)) == keccak256(bytes("open"))) {
            emit StrategyExposureOpened(
                strategy,
                user,
                exposureId,
                amount,
                leverage,
                fees,
                block.timestamp,
                blockhash(block.number - 1)
            );
        }
    }
    
    /**
     * @dev Emits a security event with risk scoring
     */
    function emitSecurityEvent(
        address user,
        address strategy,
        string memory eventType,
        uint256 riskScore,
        string memory details
    ) internal {
        emit SuspiciousActivityDetected(
            user,
            strategy,
            eventType,
            riskScore,
            1, // Pattern count
            details,
            block.timestamp
        );
    }
}