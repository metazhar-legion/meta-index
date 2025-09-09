// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFeeCollectionManager
 * @dev Interface for automated fee collection and distribution
 * @notice Defines the structure for fee management automation (scaffolding for future implementation)
 */
interface IFeeCollectionManager {
    
    // ============ STRUCTS ============
    
    /**
     * @dev Fee configuration for a strategy or protocol
     */
    struct FeeConfig {
        uint256 managementFeeRate;       // Annual management fee (basis points)
        uint256 performanceFeeRate;      // Performance fee (basis points)
        uint256 entryFeeRate;            // Entry fee (basis points)
        uint256 exitFeeRate;             // Exit fee (basis points)
        uint256 collectionInterval;      // How often fees are collected (seconds)
        uint256 lastCollection;          // Timestamp of last fee collection
        bool isActive;                   // Whether fee collection is active
    }
    
    /**
     * @dev Fee distribution configuration
     */
    struct FeeDistribution {
        address recipient;
        uint256 percentage;              // Percentage of fees (basis points)
        string role;                     // Role description (e.g., "treasury", "stakers")
    }
    
    /**
     * @dev Fee collection event data
     */
    struct FeeCollectionEvent {
        address strategy;
        uint256 managementFees;
        uint256 performanceFees;
        uint256 entryFees;
        uint256 exitFees;
        uint256 totalCollected;
        uint256 timestamp;
        address collector;
    }
    
    /**
     * @dev Treasury and fee pool status
     */
    struct TreasuryStatus {
        uint256 totalFeesCollected;
        uint256 totalFeesDistributed;
        uint256 pendingDistribution;
        uint256 managementFeesPool;
        uint256 performanceFeesPool;
        uint256 lastDistributionTime;
    }
    
    /**
     * @dev Performance metrics for fee calculation
     */
    struct PerformanceMetrics {
        uint256 currentValue;
        uint256 highWaterMark;
        uint256 lastPerformanceFeeTime;
        int256 totalReturn;              // Can be negative
        uint256 periodStart;
        bool hasPerformanceFee;
    }

    // ============ EVENTS ============
    
    event FeesCollected(
        address indexed strategy,
        uint256 managementFees,
        uint256 performanceFees,
        uint256 totalCollected,
        address collector
    );
    
    event FeesDistributed(
        address indexed recipient,
        uint256 amount,
        string role
    );
    
    event FeeConfigUpdated(
        address indexed strategy,
        FeeConfig config
    );
    
    event FeeDistributionUpdated(
        address indexed recipient,
        uint256 percentage,
        string role
    );
    
    event PerformanceFeeCalculated(
        address indexed strategy,
        uint256 currentValue,
        uint256 highWaterMark,
        uint256 performanceFee
    );
    
    event TreasuryDeposit(
        address indexed depositor,
        uint256 amount,
        string feeType
    );
    
    event EmergencyWithdrawal(
        address indexed recipient,
        uint256 amount,
        string reason
    );

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Gets fee configuration for a strategy
     * @param strategy Address of the strategy
     * @return config Fee configuration
     */
    function getFeeConfig(address strategy) external view returns (FeeConfig memory config);
    
    /**
     * @dev Gets fee distribution configuration
     * @return distributions Array of fee distribution configs
     */
    function getFeeDistributions() external view returns (FeeDistribution[] memory distributions);
    
    /**
     * @dev Gets treasury status
     * @return status Treasury status information
     */
    function getTreasuryStatus() external view returns (TreasuryStatus memory status);
    
    /**
     * @dev Calculates pending fees for a strategy
     * @param strategy Address of the strategy
     * @return managementFees Pending management fees
     * @return performanceFees Pending performance fees
     */
    function calculatePendingFees(address strategy) external view returns (uint256 managementFees, uint256 performanceFees);
    
    /**
     * @dev Gets performance metrics for a strategy
     * @param strategy Address of the strategy
     * @return metrics Performance metrics
     */
    function getPerformanceMetrics(address strategy) external view returns (PerformanceMetrics memory metrics);
    
    /**
     * @dev Checks if fees are ready for collection
     * @param strategy Address of the strategy
     * @return isReady True if fees should be collected
     * @return timeSinceLastCollection Time since last collection
     */
    function isFeesReadyForCollection(address strategy) external view returns (bool isReady, uint256 timeSinceLastCollection);
    
    /**
     * @dev Gets strategies that need fee collection
     * @return strategies Array of strategy addresses needing collection
     */
    function getStrategiesNeedingCollection() external view returns (address[] memory strategies);
    
    /**
     * @dev Estimates gas cost for fee collection
     * @param strategies Array of strategies to collect fees from
     * @return gasEstimate Estimated gas cost
     */
    function estimateCollectionGasCost(address[] calldata strategies) external view returns (uint256 gasEstimate);

    // ============ STATE-CHANGING FUNCTIONS ============
    
    /**
     * @dev Collects fees for a specific strategy
     * @param strategy Address of the strategy
     * @return managementFees Management fees collected
     * @return performanceFees Performance fees collected
     */
    function collectFees(address strategy) external returns (uint256 managementFees, uint256 performanceFees);
    
    /**
     * @dev Batch collects fees for multiple strategies
     * @param strategies Array of strategy addresses
     * @return totalCollected Total fees collected across all strategies
     */
    function batchCollectFees(address[] calldata strategies) external returns (uint256 totalCollected);
    
    /**
     * @dev Distributes collected fees to recipients
     * @return totalDistributed Total amount distributed
     */
    function distributeFees() external returns (uint256 totalDistributed);
    
    /**
     * @dev Updates high water mark for a strategy
     * @param strategy Address of the strategy
     * @param newValue New strategy value for high water mark calculation
     */
    function updateHighWaterMark(address strategy, uint256 newValue) external;
    
    /**
     * @dev Records entry fee for a user deposit
     * @param strategy Address of the strategy
     * @param user Address of the user
     * @param depositAmount Amount deposited
     * @return entryFee Fee charged
     */
    function recordEntryFee(address strategy, address user, uint256 depositAmount) external returns (uint256 entryFee);
    
    /**
     * @dev Records exit fee for a user withdrawal
     * @param strategy Address of the strategy
     * @param user Address of the user
     * @param withdrawAmount Amount withdrawn
     * @return exitFee Fee charged
     */
    function recordExitFee(address strategy, address user, uint256 withdrawAmount) external returns (uint256 exitFee);

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Sets fee configuration for a strategy
     * @param strategy Address of the strategy
     * @param config New fee configuration
     */
    function setFeeConfig(address strategy, FeeConfig calldata config) external;
    
    /**
     * @dev Updates fee distribution configuration
     * @param distributions New fee distribution configuration
     */
    function updateFeeDistribution(FeeDistribution[] calldata distributions) external;
    
    /**
     * @dev Adds a fee recipient
     * @param recipient Address of the recipient
     * @param percentage Percentage of fees (basis points)
     * @param role Role description
     */
    function addFeeRecipient(address recipient, uint256 percentage, string calldata role) external;
    
    /**
     * @dev Removes a fee recipient
     * @param recipient Address of the recipient to remove
     */
    function removeFeeRecipient(address recipient) external;
    
    /**
     * @dev Sets the treasury address
     * @param treasury New treasury address
     */
    function setTreasury(address treasury) external;
    
    /**
     * @dev Pauses fee collection
     */
    function pauseFeeCollection() external;
    
    /**
     * @dev Unpauses fee collection
     */
    function unpauseFeeCollection() external;

    // ============ EMERGENCY FUNCTIONS ============
    
    /**
     * @dev Emergency withdrawal from treasury (admin only)
     * @param recipient Address to receive funds
     * @param amount Amount to withdraw
     * @param reason Reason for emergency withdrawal
     */
    function emergencyWithdraw(address recipient, uint256 amount, string calldata reason) external;
    
    /**
     * @dev Emergency fee collection override
     * @param strategy Address of the strategy
     * @param amount Amount to collect as emergency fee
     * @param reason Reason for emergency collection
     */
    function emergencyCollectFees(address strategy, uint256 amount, string calldata reason) external;

    // ============ AUTOMATION FUNCTIONS ============
    
    /**
     * @dev Automated fee collection function (for keepers/bots)
     * @param maxStrategies Maximum number of strategies to process
     * @return strategiesProcessed Number of strategies processed
     * @return totalCollected Total fees collected
     */
    function performAutomatedCollection(uint256 maxStrategies) external returns (uint256 strategiesProcessed, uint256 totalCollected);
    
    /**
     * @dev Automated fee distribution function
     * @return totalDistributed Total amount distributed
     */
    function performAutomatedDistribution() external returns (uint256 totalDistributed);
    
    /**
     * @dev Claims gas reimbursement for automation tasks
     * @param automator Address of the automator
     * @param gasUsed Amount of gas used
     */
    function claimAutomationReimbursement(address automator, uint256 gasUsed) external;
}