// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IYieldStrategy
 * @dev Interface for yield-generating strategies
 */
interface IYieldStrategy {
    /**
     * @dev Represents the status and performance of a yield strategy
     */
    struct StrategyInfo {
        string name;           // Name of the strategy
        address asset;         // Address of the underlying asset
        uint256 totalDeposited;// Total amount deposited into this strategy
        uint256 currentValue;  // Current value including yield
        uint256 apy;           // Current APY in basis points (e.g., 500 = 5%)
        uint256 lastUpdated;   // Timestamp of last update
        bool active;           // Whether the strategy is currently active
        uint256 risk;          // Risk level from 1 (lowest) to 10 (highest)
    }

    /**
     * @dev Deposits assets into the yield strategy
     * @param amount The amount to deposit
     * @return shares The number of shares received
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @dev Withdraws assets from the yield strategy
     * @param shares The number of shares to withdraw
     * @return amount The amount withdrawn
     */
    function withdraw(uint256 shares) external returns (uint256 amount);

    /**
     * @dev Gets the current value of shares
     * @param shares The number of shares
     * @return value The current value of the shares
     */
    function getValueOfShares(uint256 shares) external view returns (uint256 value);

    /**
     * @dev Gets the total value of all assets in the strategy
     * @return value The total value
     */
    function getTotalValue() external view returns (uint256 value);

    /**
     * @dev Gets the current APY of the strategy
     * @return apy The current APY in basis points
     */
    function getCurrentAPY() external view returns (uint256 apy);

    /**
     * @dev Gets detailed information about the strategy
     * @return info The strategy information
     */
    function getStrategyInfo() external view returns (StrategyInfo memory info);

    /**
     * @dev Harvests yield from the strategy
     * @return harvested The amount harvested
     */
    function harvestYield() external returns (uint256 harvested);
}
