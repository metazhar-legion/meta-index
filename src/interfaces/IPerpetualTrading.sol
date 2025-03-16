pragma solidity ^0.8.20;

/**
 * @title IPerpetualTrading
 * @dev Interface for interacting with perpetual trading platforms like dYdX
 */
interface IPerpetualTrading {
    /**
     * @dev Represents a synthetic position in a perpetual market
     */
    struct Position {
        bytes32 marketId;      // Identifier for the market (e.g., "BTC-USD")
        int256 size;           // Position size (positive for long, negative for short)
        uint256 entryPrice;    // Entry price of the position
        uint256 leverage;      // Leverage used (e.g., 2x, 5x)
        uint256 collateral;    // Amount of collateral allocated to this position
        uint256 lastUpdated;   // Timestamp of last position update
    }

    /**
     * @dev Opens a new position in a perpetual market
     * @param marketId The identifier for the market
     * @param size The size of the position (positive for long, negative for short)
     * @param leverage The leverage to use
     * @param collateral The amount of collateral to allocate
     * @return positionId The identifier for the opened position
     */
    function openPosition(
        bytes32 marketId,
        int256 size,
        uint256 leverage,
        uint256 collateral
    ) external returns (bytes32 positionId);

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
    function adjustPosition(
        bytes32 positionId,
        int256 newSize,
        uint256 newLeverage,
        int256 collateralDelta
    ) external returns (bool);

    /**
     * @dev Gets the current market price for a given market
     * @param marketId The identifier for the market
     * @return price The current market price
     */
    function getMarketPrice(bytes32 marketId) external view returns (uint256 price);

    /**
     * @dev Gets the details of an existing position
     * @param positionId The identifier for the position
     * @return position The position details
     */
    function getPosition(bytes32 positionId) external view returns (Position memory position);

    /**
     * @dev Gets the current value of a position including unrealized PnL
     * @param positionId The identifier for the position
     * @return value The current value of the position
     */
    function getPositionValue(bytes32 positionId) external view returns (uint256 value);

    /**
     * @dev Gets the funding rate for a given market
     * @param marketId The identifier for the market
     * @return fundingRate The current funding rate (can be positive or negative)
     */
    function getFundingRate(bytes32 marketId) external view returns (int256 fundingRate);
}
