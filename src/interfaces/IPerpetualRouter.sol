// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPerpetualRouter
 * @dev Interface for interacting with perpetual trading protocols
 * This interface abstracts the implementation details of different perpetual protocols
 */
interface IPerpetualRouter {
    /**
     * @dev Opens a new perpetual position
     * @param marketId Identifier for the market (e.g., BTC-USD)
     * @param collateralAmount Amount of collateral to use
     * @param leverage Leverage to use (e.g., 2x, 5x)
     * @param isLong Whether the position is long (true) or short (false)
     * @return size The size of the opened position
     * @return price The entry price of the position
     */
    function openPosition(
        bytes32 marketId,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external returns (uint256 size, uint256 price);
    
    /**
     * @dev Closes an existing perpetual position
     * @param marketId Identifier for the market
     * @return pnl The profit or loss from closing the position
     */
    function closePosition(bytes32 marketId) external returns (uint256 pnl);
    
    /**
     * @dev Adds collateral to an existing position
     * @param marketId Identifier for the market
     * @param additionalCollateral Amount of additional collateral to add
     */
    function addCollateral(bytes32 marketId, uint256 additionalCollateral) external;
    
    /**
     * @dev Removes collateral from an existing position
     * @param marketId Identifier for the market
     * @param collateralToRemove Amount of collateral to remove
     */
    function removeCollateral(bytes32 marketId, uint256 collateralToRemove) external;
    
    /**
     * @dev Adjusts the leverage of an existing position
     * @param marketId Identifier for the market
     * @param newLeverage New leverage value
     */
    function adjustLeverage(bytes32 marketId, uint256 newLeverage) external;
    
    /**
     * @dev Gets the current details of a position
     * @param marketId Identifier for the market
     * @return size The current size of the position
     * @return price The current price of the asset
     */
    function getPositionDetails(bytes32 marketId) external view returns (uint256 size, uint256 price);
    
    /**
     * @dev Calculates the profit or loss of a position
     * @param marketId Identifier for the market
     * @return pnl The current profit or loss of the position (can be negative)
     */
    function calculatePnL(bytes32 marketId) external view returns (int256 pnl);
    
    /**
     * @dev Gets the current price of an asset
     * @param marketId Identifier for the market
     * @return price The current price of the asset
     */
    function getPrice(bytes32 marketId) external view returns (uint256 price);
    
    /**
     * @dev Gets the available markets
     * @return marketIds Array of available market identifiers
     */
    function getAvailableMarkets() external view returns (bytes32[] memory marketIds);
    
    /**
     * @dev Gets information about a specific market
     * @param marketId Identifier for the market
     * @return name The name of the market
     * @return baseToken The base token of the market
     * @return quoteToken The quote token of the market
     * @return maxLeverage The maximum allowed leverage
     * @return active Whether the market is active
     */
    function getMarketInfo(bytes32 marketId) external view returns (
        string memory name,
        address baseToken,
        address quoteToken,
        uint256 maxLeverage,
        bool active
    );
}
