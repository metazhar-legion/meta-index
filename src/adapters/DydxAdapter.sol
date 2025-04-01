// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IPerpetualAdapter} from "../interfaces/IPerpetualAdapter.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

// dYdX interfaces (simplified for this example)
interface IDydxPerpetual {
    struct OpenPositionArgs {
        bytes32 marketId;
        int256 size;
        uint256 leverage;
        uint256 collateral;
    }
    
    struct ClosePositionArgs {
        bytes32 positionId;
    }
    
    struct AdjustPositionArgs {
        bytes32 positionId;
        int256 sizeDelta;
        uint256 newLeverage;
        int256 collateralDelta;
    }
    
    function openPosition(OpenPositionArgs calldata args) external returns (bytes32 positionId);
    function closePosition(ClosePositionArgs calldata args) external returns (int256 pnl);
    function adjustPosition(AdjustPositionArgs calldata args) external;
    function getPosition(bytes32 positionId) external view returns (
        bytes32 marketId,
        int256 size,
        uint256 entryPrice,
        uint256 leverage,
        uint256 collateral,
        uint256 lastUpdated
    );
    function getMarketPrice(bytes32 marketId) external view returns (uint256 price);
    function calculatePnL(bytes32 positionId) external view returns (int256 pnl);
    function isMarketSupported(bytes32 marketId) external view returns (bool);
}

/**
 * @title DydxAdapter
 * @dev Adapter for dYdX perpetual trading platform
 */
contract DydxAdapter is IPerpetualAdapter, Ownable, ReentrancyGuard {

    // dYdX contract
    IDydxPerpetual public immutable dydx;
    
    // Base asset (e.g., USDC)
    IERC20 public immutable baseAsset;
    
    // Supported markets
    mapping(bytes32 => bool) public supportedMarkets;
    
    // Events
    event PositionOpened(bytes32 indexed positionId, bytes32 indexed marketId, int256 size, uint256 leverage, uint256 collateral);
    event PositionClosed(bytes32 indexed positionId, int256 pnl);
    event PositionAdjusted(bytes32 indexed positionId, int256 newSize, uint256 newLeverage, int256 collateralDelta);
    event MarketAdded(bytes32 indexed marketId);
    event MarketRemoved(bytes32 indexed marketId);
    
    /**
     * @dev Constructor
     * @param _dydx The dYdX perpetual contract address
     * @param _baseAsset The base asset address (e.g., USDC)
     */
    constructor(address _dydx, address _baseAsset) Ownable(msg.sender) {
        if (_dydx == address(0)) revert CommonErrors.ZeroAddress();
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        
        dydx = IDydxPerpetual(_dydx);
        baseAsset = IERC20(_baseAsset);
    }
    
    /**
     * @dev Adds a supported market
     * @param marketId The market identifier
     */
    function addMarket(bytes32 marketId) external onlyOwner {
        if (marketId == bytes32(0)) revert CommonErrors.InvalidValue();
        if (supportedMarkets[marketId]) revert CommonErrors.AlreadyExists();
        
        // Check if dYdX supports this market
        if (!dydx.isMarketSupported(marketId)) revert CommonErrors.NotSupported();
        
        supportedMarkets[marketId] = true;
        emit MarketAdded(marketId);
    }
    
    /**
     * @dev Removes a supported market
     * @param marketId The market identifier
     */
    function removeMarket(bytes32 marketId) external onlyOwner {
        if (!supportedMarkets[marketId]) revert CommonErrors.NotFound();
        
        supportedMarkets[marketId] = false;
        emit MarketRemoved(marketId);
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
    ) external override nonReentrant returns (bytes32 positionId) {
        if (!supportedMarkets[marketId]) revert CommonErrors.NotSupported();
        if (size == 0) revert CommonErrors.ValueTooLow();
        if (leverage == 0) revert CommonErrors.ValueTooLow();
        if (collateral == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer collateral from the sender to this contract
        baseAsset.transferFrom(msg.sender, address(this), collateral);
        
        // Approve dYdX to spend the collateral
        baseAsset.approve(address(dydx), 0);
        baseAsset.approve(address(dydx), collateral);
        
        // Open the position
        IDydxPerpetual.OpenPositionArgs memory args = IDydxPerpetual.OpenPositionArgs({
            marketId: marketId,
            size: size,
            leverage: leverage,
            collateral: collateral
        });
        
        positionId = dydx.openPosition(args);
        
        emit PositionOpened(positionId, marketId, size, leverage, collateral);
        
        return positionId;
    }
    
    /**
     * @dev Closes an existing position
     * @param positionId The identifier for the position to close
     * @return pnl The profit or loss from the position (can be negative)
     */
    function closePosition(bytes32 positionId) external override nonReentrant returns (int256 pnl) {
        if (positionId == bytes32(0)) revert CommonErrors.InvalidValue();
        
        // Close the position
        IDydxPerpetual.ClosePositionArgs memory args = IDydxPerpetual.ClosePositionArgs({
            positionId: positionId
        });
        
        pnl = dydx.closePosition(args);
        
        // If there's a profit, transfer it to the sender
        if (pnl > 0) {
            baseAsset.transfer(msg.sender, uint256(pnl));
        }
        
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
    ) external override nonReentrant {
        if (positionId == bytes32(0)) revert CommonErrors.InvalidValue();
        
        // Get the current position
        (bytes32 marketId, int256 currentSize, , uint256 currentLeverage, , ) = dydx.getPosition(positionId);
        
        // Use current values if not specified
        if (newSize == 0) newSize = currentSize;
        if (newLeverage == 0) newLeverage = currentLeverage;
        
        // Handle collateral changes if needed
        if (collateralDelta > 0) {
            // Adding collateral
            baseAsset.transferFrom(msg.sender, address(this), uint256(collateralDelta));
            
            // Approve dYdX to spend the additional collateral
            baseAsset.approve(address(dydx), 0);
            baseAsset.approve(address(dydx), uint256(collateralDelta));
        }
        
        // Adjust the position
        IDydxPerpetual.AdjustPositionArgs memory args = IDydxPerpetual.AdjustPositionArgs({
            positionId: positionId,
            sizeDelta: newSize - currentSize,
            newLeverage: newLeverage,
            collateralDelta: collateralDelta
        });
        
        dydx.adjustPosition(args);
        
        // If removing collateral, transfer it to the sender
        if (collateralDelta < 0) {
            baseAsset.transfer(msg.sender, uint256(-collateralDelta));
        }
        
        emit PositionAdjusted(positionId, newSize, newLeverage, collateralDelta);
    }
    
    /**
     * @dev Gets the current position information
     * @param positionId The identifier for the position
     * @return position The position information
     */
    function getPosition(bytes32 positionId) external view override returns (Position memory position) {
        if (positionId == bytes32(0)) revert CommonErrors.InvalidValue();
        
        // Get the position from dYdX
        (
            bytes32 marketId,
            int256 size,
            uint256 entryPrice,
            uint256 leverage,
            uint256 collateral,
            uint256 lastUpdated
        ) = dydx.getPosition(positionId);
        
        // Convert to our Position struct
        position = Position({
            marketId: marketId,
            size: size,
            entryPrice: entryPrice,
            leverage: leverage,
            collateral: collateral,
            lastUpdated: lastUpdated
        });
        
        return position;
    }
    
    /**
     * @dev Gets the current market price
     * @param marketId The identifier for the market
     * @return price The current market price
     */
    function getMarketPrice(bytes32 marketId) external view override returns (uint256 price) {
        if (!supportedMarkets[marketId]) revert CommonErrors.NotSupported();
        
        return dydx.getMarketPrice(marketId);
    }
    
    /**
     * @dev Calculates the profit or loss for a position
     * @param positionId The identifier for the position
     * @return pnl The profit or loss (can be negative)
     */
    function calculatePnL(bytes32 positionId) external view override returns (int256 pnl) {
        if (positionId == bytes32(0)) revert CommonErrors.InvalidValue();
        
        return dydx.calculatePnL(positionId);
    }
    
    /**
     * @dev Gets the name of the perpetual trading platform
     * @return name The name of the platform
     */
    function getPlatformName() external pure override returns (string memory name) {
        return "dYdX";
    }
    
    /**
     * @dev Checks if a market is supported by the platform
     * @param marketId The identifier for the market
     * @return supported Whether the market is supported
     */
    function isMarketSupported(bytes32 marketId) external view override returns (bool supported) {
        return supportedMarkets[marketId];
    }
}
