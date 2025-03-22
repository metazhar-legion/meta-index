// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICapitalAllocationManager
 * @dev Interface for managing capital allocation between RWA synthetics and yield strategies
 */
interface ICapitalAllocationManager {
    /**
     * @dev Allocation structure for tracking capital distribution
     */
    struct Allocation {
        uint256 rwaPercentage;         // Percentage allocated to RWA synthetics (in basis points)
        uint256 yieldPercentage;       // Percentage allocated to yield strategies (in basis points)
        uint256 liquidityBufferPercentage; // Percentage kept as liquidity buffer (in basis points)
        uint256 lastRebalanced;        // Timestamp of last rebalance
    }

    /**
     * @dev Strategy allocation structure
     */
    struct StrategyAllocation {
        address strategy;      // Address of the yield strategy
        uint256 percentage;    // Percentage allocation within yield portion (in basis points)
        bool active;           // Whether this allocation is active
    }

    /**
     * @dev RWA allocation structure
     */
    struct RWAAllocation {
        address rwaToken;      // Address of the RWA synthetic token
        uint256 percentage;    // Percentage allocation within RWA portion (in basis points)
        bool active;           // Whether this allocation is active
    }

    /**
     * @dev Sets the overall allocation percentages
     * @param rwaPercentage Percentage for RWA synthetics (in basis points)
     * @param yieldPercentage Percentage for yield strategies (in basis points)
     * @param liquidityBufferPercentage Percentage for liquidity buffer (in basis points)
     * @return success Whether the allocation was set successfully
     */
    function setAllocation(
        uint256 rwaPercentage,
        uint256 yieldPercentage,
        uint256 liquidityBufferPercentage
    ) external returns (bool success);

    /**
     * @dev Adds a yield strategy with an allocation percentage
     * @param strategy Address of the yield strategy
     * @param percentage Percentage allocation within yield portion (in basis points)
     * @return success Whether the strategy was added successfully
     */
    function addYieldStrategy(address strategy, uint256 percentage) external returns (bool success);

    /**
     * @dev Updates a yield strategy's allocation percentage
     * @param strategy Address of the yield strategy
     * @param percentage New percentage allocation (in basis points)
     * @return success Whether the strategy was updated successfully
     */
    function updateYieldStrategy(address strategy, uint256 percentage) external returns (bool success);

    /**
     * @dev Removes a yield strategy
     * @param strategy Address of the yield strategy to remove
     * @return success Whether the strategy was removed successfully
     */
    function removeYieldStrategy(address strategy) external returns (bool success);

    /**
     * @dev Adds an RWA synthetic token with an allocation percentage
     * @param rwaToken Address of the RWA synthetic token
     * @param percentage Percentage allocation within RWA portion (in basis points)
     * @return success Whether the RWA token was added successfully
     */
    function addRWAToken(address rwaToken, uint256 percentage) external returns (bool success);

    /**
     * @dev Updates an RWA synthetic token's allocation percentage
     * @param rwaToken Address of the RWA synthetic token
     * @param percentage New percentage allocation (in basis points)
     * @return success Whether the RWA token was updated successfully
     */
    function updateRWAToken(address rwaToken, uint256 percentage) external returns (bool success);

    /**
     * @dev Removes an RWA synthetic token
     * @param rwaToken Address of the RWA synthetic token to remove
     * @return success Whether the RWA token was removed successfully
     */
    function removeRWAToken(address rwaToken) external returns (bool success);

    /**
     * @dev Rebalances the capital allocation according to the set percentages
     * @return success Whether the rebalance was successful
     */
    function rebalance() external returns (bool success);

    /**
     * @dev Gets the current overall allocation
     * @return allocation The current allocation
     */
    function getAllocation() external view returns (Allocation memory allocation);

    /**
     * @dev Gets all active yield strategies and their allocations
     * @return strategies Array of strategy allocations
     */
    function getYieldStrategies() external view returns (StrategyAllocation[] memory strategies);

    /**
     * @dev Gets all active RWA tokens and their allocations
     * @return rwaTokens Array of RWA token allocations
     */
    function getRWATokens() external view returns (RWAAllocation[] memory rwaTokens);

    /**
     * @dev Gets the total value of all assets under management
     * @return totalValue The total value in the base asset (e.g., USDC)
     */
    function getTotalValue() external view returns (uint256 totalValue);

    /**
     * @dev Gets the value of assets allocated to RWA synthetics
     * @return rwaValue The value in the base asset
     */
    function getRWAValue() external view returns (uint256 rwaValue);

    /**
     * @dev Gets the value of assets allocated to yield strategies
     * @return yieldValue The value in the base asset
     */
    function getYieldValue() external view returns (uint256 yieldValue);

    /**
     * @dev Gets the value of assets kept as liquidity buffer
     * @return bufferValue The value in the base asset
     */
    function getLiquidityBufferValue() external view returns (uint256 bufferValue);
}
