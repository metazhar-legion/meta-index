// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPerpetualAdapter
 * @dev Interface for perpetual trading platform adapters
 */
interface IPerpetualAdapter {
    /**
     * @dev Represents a synthetic position in a perpetual market
     */
    struct Position {
        bytes32 marketId; // Identifier for the market (e.g., "BTC-USD")
        int256 size; // Position size (positive for long, negative for short)
        uint256 entryPrice; // Entry price of the position
        uint256 leverage; // Leverage used (e.g., 2x, 5x)
        uint256 collateral; // Amount of collateral allocated to this position
        uint256 lastUpdated; // Timestamp of last position update
    }

    /**
     * @dev Opens a new position in a perpetual market
     * @param marketId The identifier for the market
     * @param size The size of the position (positive for long, negative for short)
     * @param leverage The leverage to use
     * @param collateral The amount of collateral to allocate
     * @return positionId The identifier for the opened position
     */
    function openPosition(bytes32 marketId, int256 size, uint256 leverage, uint256 collateral)
        external
        returns (bytes32 positionId);

    /**
     * @dev Closes an existing position
     * @param positionId The identifier for the position to close
     * @return pnl The profit or loss from the position (can be negative)
     */
    function closePosition(bytes32 positionId) external returns (int256 pnl);

    /**
     * @dev Adjusts the size or leverage of an existing position
     * @param positionId The identifier for the position to adjust
     * @param newSize The new size of the position (0 to keep current)
     * @param newLeverage The new leverage to use (0 to keep current)
     * @param collateralDelta Amount to add to collateral (negative to remove)
     */
    function adjustPosition(bytes32 positionId, int256 newSize, uint256 newLeverage, int256 collateralDelta) external;

    /**
     * @dev Gets the current position information
     * @param positionId The identifier for the position
     * @return position The position information
     */
    function getPosition(bytes32 positionId) external view returns (Position memory position);

    /**
     * @dev Gets the current market price
     * @param marketId The identifier for the market
     * @return price The current market price
     */
    function getMarketPrice(bytes32 marketId) external view returns (uint256 price);

    /**
     * @dev Calculates the profit or loss for a position
     * @param positionId The identifier for the position
     * @return pnl The profit or loss (can be negative)
     */
    function calculatePnL(bytes32 positionId) external view returns (int256 pnl);

    /**
     * @dev Gets the name of the perpetual trading platform
     * @return name The name of the platform
     */
    function getPlatformName() external view returns (string memory name);

    /**
     * @dev Gets the base asset (collateral token) used by this platform
     * @return baseAsset The address of the base asset token
     */
    function getBaseAsset() external view returns (address baseAsset);

    /**
     * @dev Checks if a market is supported by the platform
     * @param marketId The identifier for the market
     * @return supported Whether the market is supported
     */
    function isMarketSupported(bytes32 marketId) external view returns (bool supported);
}
