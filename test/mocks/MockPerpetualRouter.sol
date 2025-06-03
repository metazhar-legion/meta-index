// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPerpetualRouter} from "../../src/interfaces/IPerpetualRouter.sol";

/**
 * @title MockPerpetualRouter
 * @dev Mock implementation of a perpetual position router for testing
 */
contract MockPerpetualRouter {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable baseAsset;
    
    // Mapping to track positions by market and trader
    mapping(bytes32 => mapping(address => Position)) public positions;
    
    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
        bool isLong;
        bool isOpen;
    }
    
    // Events
    event PositionOpened(bytes32 marketId, address trader, uint256 size, uint256 collateral, bool isLong);
    event PositionClosed(bytes32 marketId, address trader, uint256 pnl);
    event PositionAdjusted(bytes32 marketId, address trader, uint256 newSize, uint256 newCollateral);
    
    constructor(address _baseAsset) {
        baseAsset = IERC20(_baseAsset);
    }
    
    /**
     * @dev Opens a position in the specified market
     * @param marketId ID of the market
     * @param collateralAmount Amount of collateral to use
     * @param leverage Leverage to use
     * @param isLong Whether the position is long or short
     */
    function openPosition(
        bytes32 marketId,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external returns (uint256 positionSize, uint256 entryPrice) {
        // Transfer collateral from trader
        baseAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);
        
        // Mock position size and entry price
        positionSize = collateralAmount * leverage;
        entryPrice = 1000 * 10**18; // Mock entry price of 1000 USD
        
        // Store position
        positions[marketId][msg.sender] = Position({
            size: positionSize,
            collateral: collateralAmount,
            entryPrice: entryPrice,
            isLong: isLong,
            isOpen: true
        });
        
        emit PositionOpened(marketId, msg.sender, positionSize, collateralAmount, isLong);
        
        return (positionSize, entryPrice);
    }
    
    /**
     * @dev Closes an existing position
     * @param marketId ID of the market
     */
    function closePosition(bytes32 marketId) external returns (uint256 pnl) {
        Position storage position = positions[marketId][msg.sender];
        require(position.isOpen, "No position open");
        
        // Mock PnL calculation (0 for simplicity)
        pnl = 0;
        
        // Return collateral to trader
        baseAsset.safeTransfer(msg.sender, position.collateral + pnl);
        
        // Close position
        position.isOpen = false;
        
        emit PositionClosed(marketId, msg.sender, pnl);
        
        return pnl;
    }
    
    /**
     * @dev Adjusts an existing position
     * @param marketId ID of the market
     * @param newCollateralAmount New collateral amount
     */
    function adjustPosition(
        bytes32 marketId,
        uint256 newCollateralAmount
    ) external returns (uint256 newPositionSize) {
        Position storage position = positions[marketId][msg.sender];
        require(position.isOpen, "No position open");
        
        uint256 currentCollateral = position.collateral;
        
        if (newCollateralAmount > currentCollateral) {
            // Add collateral
            uint256 additionalCollateral = newCollateralAmount - currentCollateral;
            baseAsset.safeTransferFrom(msg.sender, address(this), additionalCollateral);
        } else if (newCollateralAmount < currentCollateral) {
            // Remove collateral
            uint256 collateralToReturn = currentCollateral - newCollateralAmount;
            baseAsset.safeTransfer(msg.sender, collateralToReturn);
        }
        
        // Update position
        position.collateral = newCollateralAmount;
        
        // Calculate new position size based on the original leverage
        uint256 leverage = position.size / currentCollateral;
        newPositionSize = newCollateralAmount * leverage;
        position.size = newPositionSize;
        
        emit PositionAdjusted(marketId, msg.sender, newPositionSize, newCollateralAmount);
        
        return newPositionSize;
    }
    
    /**
     * @dev Gets the current position information
     * @param marketId ID of the market
     * @param trader Address of the trader
     */
    function getPosition(bytes32 marketId, address trader) external view returns (
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        bool isLong,
        bool isOpen
    ) {
        Position memory position = positions[marketId][trader];
        return (
            position.size,
            position.collateral,
            position.entryPrice,
            position.isLong,
            position.isOpen
        );
    }
    
    /**
     * @dev Calculates the PnL for a position
     * @param marketId ID of the market
     * @param trader Address of the trader
     * @param currentPrice Current price of the asset
     */
    function calculatePnL(
        bytes32 marketId,
        address trader,
        uint256 currentPrice
    ) external view returns (int256 pnl) {
        Position memory position = positions[marketId][trader];
        
        if (!position.isOpen) {
            return 0;
        }
        
        if (position.isLong) {
            if (currentPrice > position.entryPrice) {
                // Profit for long position
                pnl = int256((currentPrice - position.entryPrice) * position.size / position.entryPrice);
            } else {
                // Loss for long position
                pnl = -int256((position.entryPrice - currentPrice) * position.size / position.entryPrice);
            }
        } else {
            if (currentPrice < position.entryPrice) {
                // Profit for short position
                pnl = int256((position.entryPrice - currentPrice) * position.size / position.entryPrice);
            } else {
                // Loss for short position
                pnl = -int256((currentPrice - position.entryPrice) * position.size / position.entryPrice);
            }
        }
        
        return pnl;
    }
}
