// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPerpetualTrading} from "../interfaces/IPerpetualTrading.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title MockPerpetualTrading
 * @dev Mock implementation of a perpetual trading platform for testing RWA synthetic tokens
 */
contract MockPerpetualTrading is IPerpetualTrading, Ownable {
    // Constants
    uint256 private constant SECONDS_PER_HOUR = 3600;
    uint256 private constant FUNDING_RATE_PERIOD_HOURS = 8;
    uint256 private constant BASIS_POINTS = 10000;
    using SafeERC20 for IERC20;

    // Base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // Mapping from positionId to Position
    mapping(bytes32 => Position) private positions;
    
    // Mapping from marketId to price
    mapping(bytes32 => uint256) private marketPrices;
    
    // Mapping from marketId to funding rate
    mapping(bytes32 => int256) private fundingRates;
    
    // Position counter for generating unique IDs
    uint256 private positionCounter;
    
    // Events
    event PositionOpened(bytes32 indexed positionId, bytes32 indexed marketId, int256 size, uint256 leverage, uint256 collateral);
    event PositionClosed(bytes32 indexed positionId, int256 pnl);
    event PositionAdjusted(bytes32 indexed positionId, int256 newSize, uint256 newLeverage, int256 collateralDelta);
    event MarketPriceUpdated(bytes32 indexed marketId, uint256 price);
    event FundingRateUpdated(bytes32 indexed marketId, int256 fundingRate);
    
    /**
     * @dev Constructor
     * @param _baseAsset Address of the base asset (e.g., USDC)
     */
    constructor(address _baseAsset) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        baseAsset = IERC20(_baseAsset);
        
        // Initialize some default market prices for testing
        marketPrices[bytes32("SP500-USD")] = 5000 * 10**18; // $5000 with 18 decimals
        marketPrices[bytes32("GOLD-USD")] = 2000 * 10**18;  // $2000 with 18 decimals
        marketPrices[bytes32("BTC-USD")] = 50000 * 10**18;  // $50000 with 18 decimals
        
        // Initialize funding rates (in basis points)
        fundingRates[bytes32("SP500-USD")] = 1 * 10**16;    // 0.01% (positive means longs pay shorts)
        fundingRates[bytes32("GOLD-USD")] = -2 * 10**16;    // -0.02% (negative means shorts pay longs)
        fundingRates[bytes32("BTC-USD")] = 5 * 10**16;      // 0.05%
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
    ) external override returns (bytes32 positionId) {
        if (marketPrices[marketId] == 0) revert CommonErrors.InvalidValue();
        if (size == 0) revert CommonErrors.ValueTooLow();
        if (leverage == 0) revert CommonErrors.ValueTooLow();
        if (collateral == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer collateral from sender
        baseAsset.safeTransferFrom(msg.sender, address(this), collateral);
        
        // Generate a unique position ID
        positionId = keccak256(abi.encodePacked(msg.sender, marketId, block.timestamp, positionCounter++));
        
        // Create and store the position
        positions[positionId] = Position({
            marketId: marketId,
            size: size,
            entryPrice: marketPrices[marketId],
            leverage: leverage,
            collateral: collateral,
            lastUpdated: block.timestamp
        });
        
        emit PositionOpened(positionId, marketId, size, leverage, collateral);
        
        return positionId;
    }
    
    /**
     * @dev Closes an existing position
     * @param positionId The identifier for the position to close
     * @return pnl The profit or loss from the position (can be negative)
     */
    function closePosition(bytes32 positionId) external override returns (int256 pnl) {
        Position memory position = positions[positionId];
        if (position.size == 0) revert CommonErrors.InvalidState();
        
        // Calculate PnL
        pnl = _calculatePnL(positionId);
        
        // Transfer collateral plus PnL back to sender
        uint256 amountToReturn;
        if (pnl >= 0) {
            amountToReturn = position.collateral + uint256(pnl);
        } else {
            // Ensure we don't underflow if loss exceeds collateral
            int256 remainingCollateral = int256(position.collateral) + pnl;
            amountToReturn = remainingCollateral > 0 ? uint256(remainingCollateral) : 0;
        }
        
        if (amountToReturn > 0) {
            baseAsset.safeTransfer(msg.sender, amountToReturn);
        }
        
        // Delete the position
        delete positions[positionId];
        
        emit PositionClosed(positionId, pnl);
        
        return pnl;
    }
    
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
    ) external override returns (bool) {
        Position storage position = positions[positionId];
        if (position.size == 0) revert CommonErrors.InvalidState();
        
        // Handle collateral changes
        if (collateralDelta > 0) {
            // Add collateral
            baseAsset.safeTransferFrom(msg.sender, address(this), uint256(collateralDelta));
            position.collateral += uint256(collateralDelta);
        } else if (collateralDelta < 0) {
            // Remove collateral
            uint256 collateralToRemove = uint256(-collateralDelta);
            if (position.collateral <= collateralToRemove) revert CommonErrors.InsufficientBalance();
            position.collateral -= collateralToRemove;
            baseAsset.safeTransfer(msg.sender, collateralToRemove);
        }
        
        // Update size if specified
        if (newSize != 0) {
            position.size = newSize;
        }
        
        // Update leverage if specified
        if (newLeverage > 0) {
            position.leverage = newLeverage;
        }
        
        // Update timestamp
        position.lastUpdated = block.timestamp;
        
        emit PositionAdjusted(positionId, position.size, position.leverage, collateralDelta);
        
        return true;
    }
    
    /**
     * @dev Gets the current market price for a given market
     * @param marketId The identifier for the market
     * @return price The current market price
     */
    function getMarketPrice(bytes32 marketId) external view override returns (uint256 price) {
        if (marketPrices[marketId] == 0) revert CommonErrors.InvalidValue();
        return marketPrices[marketId];
    }
    
    /**
     * @dev Gets the details of an existing position
     * @param positionId The identifier for the position
     * @return position The position details
     */
    function getPosition(bytes32 positionId) external view override returns (Position memory position) {
        if (positions[positionId].size == 0) revert CommonErrors.InvalidState();
        return positions[positionId];
    }
    
    /**
     * @dev Gets the current value of a position including unrealized PnL
     * @param positionId The identifier for the position
     * @return value The current value of the position
     */
    function getPositionValue(bytes32 positionId) external view override returns (uint256 value) {
        Position memory position = positions[positionId];
        if (position.size == 0) revert CommonErrors.InvalidState();
        
        int256 pnl = _calculatePnL(positionId);
        
        // Calculate total value (collateral + PnL)
        if (pnl >= 0) {
            return position.collateral + uint256(pnl);
        } else {
            // Ensure we don't underflow if loss exceeds collateral
            int256 remainingValue = int256(position.collateral) + pnl;
            return remainingValue > 0 ? uint256(remainingValue) : 0;
        }
    }
    
    /**
     * @dev Gets the funding rate for a given market
     * @param marketId The identifier for the market
     * @return fundingRate The current funding rate (can be positive or negative)
     */
    function getFundingRate(bytes32 marketId) external view override returns (int256 fundingRate) {
        if (marketPrices[marketId] == 0) revert CommonErrors.InvalidValue();
        return fundingRates[marketId];
    }
    
    /**
     * @dev Sets the market price for a given market (for testing)
     * @param marketId The identifier for the market
     * @param price The new market price
     */
    function setMarketPrice(bytes32 marketId, uint256 price) external onlyOwner {
        if (price == 0) revert CommonErrors.ValueTooLow();
        marketPrices[marketId] = price;
        emit MarketPriceUpdated(marketId, price);
    }
    
    /**
     * @dev Sets the funding rate for a given market (for testing)
     * @param marketId The identifier for the market
     * @param fundingRate The new funding rate
     */
    function setFundingRate(bytes32 marketId, int256 fundingRate) external onlyOwner {
        marketPrices[marketId] > 0 ? marketPrices[marketId] : marketPrices[marketId] = 1000 * 10**18;
        fundingRates[marketId] = fundingRate;
        emit FundingRateUpdated(marketId, fundingRate);
    }
    
    /**
     * @dev Calculates the profit or loss for a position
     * @param positionId The identifier for the position
     * @return pnl The profit or loss (can be negative)
     */
    function _calculatePnL(bytes32 positionId) internal view returns (int256 pnl) {
        Position memory position = positions[positionId];
        uint256 currentPrice = marketPrices[position.marketId];
        
        // Calculate price change percentage
        int256 priceChange;
        if (position.size > 0) {
            // Long position
            priceChange = int256(currentPrice) - int256(position.entryPrice);
        } else {
            // Short position
            priceChange = int256(position.entryPrice) - int256(currentPrice);
        }
        
        // Calculate PnL based on position size, leverage, and price change
        // For simplicity, we'll use a linear calculation
        int256 positionValue = int256(position.collateral) * int256(position.leverage);
        pnl = (positionValue * priceChange) / int256(position.entryPrice);
        
        // Apply funding rate effects based on time elapsed
        uint256 timeElapsed = block.timestamp - position.lastUpdated;
        if (timeElapsed > 0 && fundingRates[position.marketId] != 0) {
            // Convert time to hours (approximate)
            uint256 hoursElapsed = timeElapsed / SECONDS_PER_HOUR;
            
            // Apply funding rate (funding rate is per 8 hours in basis points)
            int256 fundingRate = fundingRates[position.marketId];
            int256 fundingAmount = (positionValue * fundingRate * int256(hoursElapsed)) / (int256(FUNDING_RATE_PERIOD_HOURS * BASIS_POINTS));
            
            // For long positions, positive funding rate means paying funding
            // For short positions, it's the opposite
            if (position.size > 0) {
                pnl -= fundingAmount;
            } else {
                pnl += fundingAmount;
            }
        }
        
        return pnl;
    }
}
