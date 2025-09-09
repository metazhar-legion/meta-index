// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidationManager
 * @dev Interface for automated liquidation management
 * @notice Defines the structure for liquidation automation (scaffolding for future implementation)
 */
interface ILiquidationManager {
    
    // ============ STRUCTS ============
    
    /**
     * @dev Liquidation parameters for a position
     */
    struct LiquidationParams {
        uint256 liquidationThreshold;    // Price threshold for liquidation (basis points)
        uint256 liquidationPenalty;      // Penalty fee for liquidation (basis points)
        uint256 liquidatorReward;        // Reward for liquidator (basis points)
        uint256 maxLiquidationSize;      // Maximum size per liquidation
        uint256 minCollateralRatio;     // Minimum collateral ratio to maintain
        bool isEnabled;                  // Whether liquidation is enabled
    }
    
    /**
     * @dev Position health information
     */
    struct PositionHealth {
        address strategy;
        bytes32 positionId;
        uint256 currentPrice;
        uint256 liquidationPrice;
        uint256 collateralRatio;
        uint256 healthFactor;           // Health factor (100 = 100%, below 100 = unhealthy)
        bool isLiquidatable;
        uint256 lastHealthCheck;
    }
    
    /**
     * @dev Liquidation event data
     */
    struct LiquidationEvent {
        bytes32 positionId;
        address strategy;
        address liquidator;
        uint256 liquidatedAmount;
        uint256 collateralRecovered;
        uint256 penalty;
        uint256 reward;
        uint256 timestamp;
    }
    
    /**
     * @dev Keeper configuration for automated liquidations
     */
    struct KeeperConfig {
        address keeper;
        uint256 gasReimbursement;       // Gas reimbursement per liquidation
        uint256 maxGasPrice;            // Maximum gas price for keeper operations
        uint256 checkInterval;          // Minimum interval between health checks
        bool isActive;
    }

    // ============ EVENTS ============
    
    event LiquidationTriggered(
        bytes32 indexed positionId,
        address indexed strategy,
        address indexed liquidator,
        uint256 liquidatedAmount,
        uint256 penalty,
        uint256 reward
    );
    
    event PositionHealthUpdated(
        bytes32 indexed positionId,
        address indexed strategy,
        uint256 healthFactor,
        bool isLiquidatable
    );
    
    event LiquidationParamsUpdated(
        address indexed strategy,
        LiquidationParams params
    );
    
    event KeeperAdded(address indexed keeper, KeeperConfig config);
    event KeeperRemoved(address indexed keeper);
    
    event EmergencyLiquidationExecuted(
        bytes32 indexed positionId,
        address indexed strategy,
        uint256 amount,
        string reason
    );

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Gets liquidation parameters for a strategy
     * @param strategy Address of the strategy
     * @return params Liquidation parameters
     */
    function getLiquidationParams(address strategy) external view returns (LiquidationParams memory params);
    
    /**
     * @dev Gets position health information
     * @param strategy Address of the strategy
     * @param positionId ID of the position
     * @return health Position health information
     */
    function getPositionHealth(address strategy, bytes32 positionId) external view returns (PositionHealth memory health);
    
    /**
     * @dev Checks if a position is liquidatable
     * @param strategy Address of the strategy
     * @param positionId ID of the position
     * @return isLiquidatable True if position can be liquidated
     * @return healthFactor Current health factor
     */
    function isPositionLiquidatable(address strategy, bytes32 positionId) external view returns (bool isLiquidatable, uint256 healthFactor);
    
    /**
     * @dev Gets all positions that need health checks
     * @return strategies Array of strategy addresses
     * @return positionIds Array of position IDs
     */
    function getPositionsNeedingHealthCheck() external view returns (address[] memory strategies, bytes32[] memory positionIds);
    
    /**
     * @dev Gets liquidatable positions across all strategies
     * @return liquidatablePositions Array of liquidatable positions
     */
    function getLiquidatablePositions() external view returns (PositionHealth[] memory liquidatablePositions);
    
    /**
     * @dev Estimates liquidation reward for a position
     * @param strategy Address of the strategy
     * @param positionId ID of the position
     * @param liquidationAmount Amount to liquidate
     * @return reward Estimated reward for liquidator
     * @return penalty Penalty to be paid
     */
    function estimateLiquidationReward(
        address strategy,
        bytes32 positionId,
        uint256 liquidationAmount
    ) external view returns (uint256 reward, uint256 penalty);

    // ============ STATE-CHANGING FUNCTIONS ============
    
    /**
     * @dev Executes liquidation for a position
     * @param strategy Address of the strategy
     * @param positionId ID of the position to liquidate
     * @param liquidationAmount Amount to liquidate
     * @return success Whether liquidation was successful
     * @return actualLiquidated Actual amount liquidated
     * @return reward Reward paid to liquidator
     */
    function executeLiquidation(
        address strategy,
        bytes32 positionId,
        uint256 liquidationAmount
    ) external returns (bool success, uint256 actualLiquidated, uint256 reward);
    
    /**
     * @dev Updates position health for a specific position
     * @param strategy Address of the strategy
     * @param positionId ID of the position
     * @return health Updated position health
     */
    function updatePositionHealth(address strategy, bytes32 positionId) external returns (PositionHealth memory health);
    
    /**
     * @dev Batch updates position health for multiple positions
     * @param strategies Array of strategy addresses
     * @param positionIds Array of position IDs
     */
    function batchUpdatePositionHealth(address[] calldata strategies, bytes32[] calldata positionIds) external;
    
    /**
     * @dev Emergency liquidation function (admin only)
     * @param strategy Address of the strategy
     * @param positionId ID of the position
     * @param reason Reason for emergency liquidation
     * @return recovered Amount recovered from liquidation
     */
    function emergencyLiquidation(
        address strategy,
        bytes32 positionId,
        string calldata reason
    ) external returns (uint256 recovered);

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Sets liquidation parameters for a strategy
     * @param strategy Address of the strategy
     * @param params New liquidation parameters
     */
    function setLiquidationParams(address strategy, LiquidationParams calldata params) external;
    
    /**
     * @dev Adds a keeper for automated liquidations
     * @param keeper Address of the keeper
     * @param config Keeper configuration
     */
    function addKeeper(address keeper, KeeperConfig calldata config) external;
    
    /**
     * @dev Removes a keeper
     * @param keeper Address of the keeper to remove
     */
    function removeKeeper(address keeper) external;
    
    /**
     * @dev Updates keeper configuration
     * @param keeper Address of the keeper
     * @param config New keeper configuration
     */
    function updateKeeperConfig(address keeper, KeeperConfig calldata config) external;

    // ============ KEEPER FUNCTIONS ============
    
    /**
     * @dev Checks and executes liquidations if needed (keeper function)
     * @param maxLiquidations Maximum number of liquidations to execute
     * @return liquidationsExecuted Number of liquidations executed
     */
    function performLiquidationCheck(uint256 maxLiquidations) external returns (uint256 liquidationsExecuted);
    
    /**
     * @dev Claims gas reimbursement for keeper operations
     * @param keeper Address of the keeper
     * @param gasUsed Amount of gas used
     */
    function claimGasReimbursement(address keeper, uint256 gasUsed) external;
}