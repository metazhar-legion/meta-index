// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPerpetualRouter} from "../interfaces/IPerpetualRouter.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title MockPerpetualRouter
 * @dev Mock implementation of the PerpetualRouter for testing
 * This contract simulates the behavior of a perpetual trading protocol
 */
contract MockPerpetualRouter is IPerpetualRouter, Ownable {
    using SafeERC20 for IERC20;

    // Price oracle for asset prices
    IPriceOracle public priceOracle;
    
    // Base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // Market information
    struct Market {
        string name;
        address baseToken;
        address quoteToken;
        uint256 maxLeverage;
        bool active;
    }
    
    // Position information
    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
        uint256 leverage;
        bool isLong;
        bool isOpen;
        address owner;
    }
    
    // Mappings
    mapping(bytes32 => Market) public markets;
    mapping(bytes32 => Position) public positions;
    bytes32[] public marketIds;
    
    // Events
    event PositionOpened(bytes32 marketId, address owner, uint256 size, uint256 collateral, uint256 leverage, bool isLong);
    event PositionClosed(bytes32 marketId, address owner, uint256 pnl);
    event CollateralAdded(bytes32 marketId, address owner, uint256 amount);
    event CollateralRemoved(bytes32 marketId, address owner, uint256 amount);
    event LeverageAdjusted(bytes32 marketId, address owner, uint256 newLeverage);
    event MarketAdded(bytes32 marketId, string name, address baseToken, address quoteToken, uint256 maxLeverage);
    
    // Custom errors
    error MarketNotFound();
    error MarketAlreadyExists();
    error PositionNotFound();
    error PositionAlreadyExists();
    error InsufficientCollateral();
    error InvalidLeverage();
    error Unauthorized();
    
    /**
     * @dev Constructor
     * @param _priceOracle Address of the price oracle
     * @param _baseAsset Address of the base asset
     */
    constructor(address _priceOracle, address _baseAsset) Ownable(msg.sender) {
        if (_priceOracle == address(0) || _baseAsset == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        priceOracle = IPriceOracle(_priceOracle);
        baseAsset = IERC20(_baseAsset);
    }
    
    /**
     * @dev Adds a new market
     * @param marketId Identifier for the market
     * @param name Name of the market
     * @param baseToken Base token of the market
     * @param quoteToken Quote token of the market
     * @param maxLeverage Maximum allowed leverage
     */
    function addMarket(
        bytes32 marketId,
        string memory name,
        address baseToken,
        address quoteToken,
        uint256 maxLeverage
    ) external onlyOwner {
        if (markets[marketId].active) {
            revert MarketAlreadyExists();
        }
        
        markets[marketId] = Market({
            name: name,
            baseToken: baseToken,
            quoteToken: quoteToken,
            maxLeverage: maxLeverage,
            active: true
        });
        
        marketIds.push(marketId);
        
        emit MarketAdded(marketId, name, baseToken, quoteToken, maxLeverage);
    }
    
    /**
     * @dev Opens a new perpetual position
     * @param marketId Identifier for the market
     * @param collateralAmount Amount of collateral to use
     * @param leverage Leverage to use
     * @param isLong Whether the position is long or short
     * @return size The size of the opened position
     * @return price The entry price of the position
     */
    function openPosition(
        bytes32 marketId,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external override returns (uint256 size, uint256 price) {
        // Check if market exists
        if (!markets[marketId].active) {
            revert MarketNotFound();
        }
        
        // Check if position already exists
        if (positions[marketId].isOpen) {
            revert PositionAlreadyExists();
        }
        
        // Check leverage
        if (leverage == 0 || leverage > markets[marketId].maxLeverage) {
            revert InvalidLeverage();
        }
        
        // Transfer collateral from user
        if (msg.sender != address(this)) {
            baseAsset.safeTransferFrom(msg.sender, address(this), collateralAmount);
        }
        
        // Get current price from oracle
        price = priceOracle.getPrice(markets[marketId].baseToken);
        
        // Calculate position size (collateral * leverage)
        size = collateralAmount * leverage;
        
        // Create position
        positions[marketId] = Position({
            size: size,
            collateral: collateralAmount,
            entryPrice: price,
            leverage: leverage,
            isLong: isLong,
            isOpen: true,
            owner: msg.sender
        });
        
        emit PositionOpened(marketId, msg.sender, size, collateralAmount, leverage, isLong);
        
        return (size, price);
    }
    
    /**
     * @dev Closes an existing perpetual position
     * @param marketId Identifier for the market
     * @return pnl The profit or loss from closing the position
     */
    function closePosition(bytes32 marketId) external override returns (uint256 pnl) {
        // Check if position exists
        if (!positions[marketId].isOpen) {
            revert PositionNotFound();
        }
        
        Position memory position = positions[marketId];
        
        // Calculate PnL
        int256 calculatedPnl = calculatePnL(marketId);
        
        // Handle PnL
        if (calculatedPnl > 0) {
            // Profit: return collateral + profit
            uint256 profit = uint256(calculatedPnl);
            baseAsset.safeTransfer(msg.sender, position.collateral + profit);
            pnl = profit;
        } else if (calculatedPnl < 0) {
            // Loss: return collateral - loss
            uint256 loss = uint256(-calculatedPnl);
            
            if (loss >= position.collateral) {
                // Total loss
                pnl = 0;
            } else {
                // Partial loss
                baseAsset.safeTransfer(msg.sender, position.collateral - loss);
                pnl = position.collateral - loss; // Return the actual amount after loss
            }
        } else {
            // No PnL: return collateral
            baseAsset.safeTransfer(msg.sender, position.collateral);
            pnl = position.collateral;
        }
        
        // Close position
        delete positions[marketId];
        
        emit PositionClosed(marketId, msg.sender, pnl);
        
        return pnl;
    }
    
    /**
     * @dev Adds collateral to an existing position
     * @param marketId Identifier for the market
     * @param additionalCollateral Amount of additional collateral to add
     */
    function addCollateral(bytes32 marketId, uint256 additionalCollateral) external override {
        // Check if position exists and belongs to sender
        if (!positions[marketId].isOpen || positions[marketId].owner != msg.sender) {
            revert PositionNotFound();
        }
        
        // Transfer additional collateral from user
        baseAsset.safeTransferFrom(msg.sender, address(this), additionalCollateral);
        
        // Update position
        positions[marketId].collateral += additionalCollateral;
        positions[marketId].size = positions[marketId].collateral * positions[marketId].leverage;
        
        emit CollateralAdded(marketId, msg.sender, additionalCollateral);
    }
    
    /**
     * @dev Removes collateral from an existing position
     * @param marketId Identifier for the market
     * @param collateralToRemove Amount of collateral to remove
     */
    function removeCollateral(bytes32 marketId, uint256 collateralToRemove) external override {
        // Check if position exists
        if (!positions[marketId].isOpen) {
            revert PositionNotFound();
        }
        
        Position storage position = positions[marketId];
        
        // Check if there's enough collateral to remove
        if (collateralToRemove >= position.collateral) {
            revert InsufficientCollateral();
        }
        
        // Calculate new collateral
        uint256 newCollateral = position.collateral - collateralToRemove;
        
        // Calculate minimum required collateral based on current PnL
        int256 currentPnl = calculatePnL(marketId);
        uint256 minimumCollateral = 0;
        
        if (currentPnl < 0) {
            // If position is in loss, ensure we maintain enough collateral
            minimumCollateral = uint256(-currentPnl) + position.collateral / 10; // 10% buffer
        } else {
            // If position is in profit, minimum is 10% of original
            minimumCollateral = position.collateral / 10;
        }
        
        if (newCollateral < minimumCollateral) {
            revert InsufficientCollateral();
        }
        
        // Update position
        position.collateral = newCollateral;
        position.size = newCollateral * position.leverage;
        
        // Transfer collateral back to user
        baseAsset.safeTransfer(msg.sender, collateralToRemove);
        
        emit CollateralRemoved(marketId, msg.sender, collateralToRemove);
    }
    
    /**
     * @dev Adjusts the leverage of an existing position
     * @param marketId Identifier for the market
     * @param newLeverage New leverage value
     */
    function adjustLeverage(bytes32 marketId, uint256 newLeverage) external override {
        // Check if position exists and belongs to sender
        if (!positions[marketId].isOpen || positions[marketId].owner != msg.sender) {
            revert PositionNotFound();
        }
        
        // Check leverage
        if (newLeverage == 0 || newLeverage > markets[marketId].maxLeverage) {
            revert InvalidLeverage();
        }
        
        // Update position
        positions[marketId].leverage = newLeverage;
        positions[marketId].size = positions[marketId].collateral * newLeverage;
        
        emit LeverageAdjusted(marketId, msg.sender, newLeverage);
    }
    
    /**
     * @dev Gets the current details of a position
     * @param marketId Identifier for the market
     * @return size The current size of the position
     * @return price The current price of the asset
     */
    function getPositionDetails(bytes32 marketId) external view override returns (uint256 size, uint256 price) {
        // Check if position exists
        if (!positions[marketId].isOpen) {
            return (0, 0);
        }
        
        Position memory position = positions[marketId];
        
        // Get current price from oracle
        price = priceOracle.getPrice(markets[marketId].baseToken);
        
        return (position.size, price);
    }
    
    /**
     * @dev Calculates the profit or loss of a position
     * @param marketId Identifier for the market
     * @return pnl The current profit or loss of the position
     */
    function calculatePnL(bytes32 marketId) public view override returns (int256 pnl) {
        // Check if position exists
        if (!positions[marketId].isOpen) {
            return 0;
        }
        
        Position memory position = positions[marketId];
        
        // Get current price from oracle
        uint256 currentPrice = priceOracle.getPrice(markets[marketId].baseToken);
        
        // Calculate PnL
        if (position.isLong) {
            // Long position: (currentPrice - entryPrice) * size / entryPrice
            if (currentPrice > position.entryPrice) {
                // Profit
                pnl = int256((currentPrice - position.entryPrice) * position.size / position.entryPrice);
            } else if (currentPrice < position.entryPrice) {
                // Loss
                pnl = -int256((position.entryPrice - currentPrice) * position.size / position.entryPrice);
            } else {
                // No change
                pnl = 0;
            }
        } else {
            // Short position: (entryPrice - currentPrice) * size / entryPrice
            if (currentPrice < position.entryPrice) {
                // Profit
                pnl = int256((position.entryPrice - currentPrice) * position.size / position.entryPrice);
            } else if (currentPrice > position.entryPrice) {
                // Loss
                pnl = -int256((currentPrice - position.entryPrice) * position.size / position.entryPrice);
            } else {
                // No change
                pnl = 0;
            }
        }
        
        return pnl;
    }
    
    /**
     * @dev Gets the current price of an asset
     * @param marketId Identifier for the market
     * @return price The current price of the asset
     */
    function getPrice(bytes32 marketId) external view override returns (uint256 price) {
        // Check if market exists
        if (!markets[marketId].active) {
            revert MarketNotFound();
        }
        
        // Get price from oracle
        price = priceOracle.getPrice(markets[marketId].baseToken);
        
        return price;
    }
    
    /**
     * @dev Gets the available markets
     * @return marketIds Array of available market identifiers
     */
    function getAvailableMarkets() external view override returns (bytes32[] memory) {
        return marketIds;
    }
    
    /**
     * @dev Gets information about a specific market
     * @param marketId Identifier for the market
     * @return name The name of the market
     * @return baseToken The base token of the market
     * @return quoteToken The quote token of the market
     * @return maxLeverage The maximum allowed leverage
     * @return active Whether the market is active
     */
    function getMarketInfo(bytes32 marketId) external view override returns (
        string memory name,
        address baseToken,
        address quoteToken,
        uint256 maxLeverage,
        bool active
    ) {
        Market memory market = markets[marketId];
        
        return (
            market.name,
            market.baseToken,
            market.quoteToken,
            market.maxLeverage,
            market.active
        );
    }
    
    /**
     * @dev Sets the price oracle
     * @param _priceOracle New price oracle address
     */
    function setPriceOracle(address _priceOracle) external onlyOwner {
        if (_priceOracle == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        priceOracle = IPriceOracle(_priceOracle);
    }
    
    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Address of the token to recover
     * @param amount Amount to recover
     */
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
