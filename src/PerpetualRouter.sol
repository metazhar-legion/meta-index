// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IPerpetualAdapter} from "./interfaces/IPerpetualAdapter.sol";
import {IPerpetualTrading} from "./interfaces/IPerpetualTrading.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title PerpetualRouter
 * @dev Routes perpetual trading operations to the best platform based on available markets and pricing
 */
contract PerpetualRouter is IPerpetualTrading, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Array of perpetual trading adapters
    IPerpetualAdapter[] public perpetualAdapters;
    
    // Mapping to check if a perpetual adapter is already added
    mapping(address => bool) public isAdapter;
    
    // Mapping from positionId to adapter address
    mapping(bytes32 => address) public positionToAdapter;
    
    // Events
    event AdapterAdded(address indexed adapter, string name);
    event AdapterRemoved(address indexed adapter);
    event PositionOpened(bytes32 indexed positionId, bytes32 indexed marketId, int256 size, uint256 leverage, uint256 collateral, address indexed platform);
    event PositionClosed(bytes32 indexed positionId, int256 pnl, address indexed platform);
    event PositionAdjusted(bytes32 indexed positionId, int256 newSize, uint256 newLeverage, int256 collateralDelta, address indexed platform);
    
    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Adds a new perpetual trading adapter
     * @param adapter The address of the perpetual adapter
     */
    function addAdapter(address adapter) external onlyOwner {
        if (adapter == address(0)) revert CommonErrors.ZeroAddress();
        if (isAdapter[adapter]) revert CommonErrors.InvalidValue();
        
        IPerpetualAdapter perpAdapter = IPerpetualAdapter(adapter);
        perpetualAdapters.push(perpAdapter);
        isAdapter[adapter] = true;
        
        emit AdapterAdded(adapter, perpAdapter.getPlatformName());
    }
    
    /**
     * @dev Removes a perpetual trading adapter
     * @param adapter The address of the perpetual adapter to remove
     */
    function removeAdapter(address adapter) external onlyOwner {
        if (!isAdapter[adapter]) revert CommonErrors.NotFound();
        
        // Find the adapter in the array
        uint256 adapterIndex = type(uint256).max;
        for (uint256 i = 0; i < perpetualAdapters.length; i++) {
            if (address(perpetualAdapters[i]) == adapter) {
                adapterIndex = i;
                break;
            }
        }
        
        if (adapterIndex == type(uint256).max) revert CommonErrors.NotFound();
        
        // Remove the adapter by swapping with the last element and popping
        perpetualAdapters[adapterIndex] = perpetualAdapters[perpetualAdapters.length - 1];
        perpetualAdapters.pop();
        isAdapter[adapter] = false;
        
        emit AdapterRemoved(adapter);
    }
    
    /**
     * @dev Gets the number of perpetual trading adapters
     * @return count The number of adapters
     */
    function getAdapterCount() external view returns (uint256 count) {
        return perpetualAdapters.length;
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
        if (perpetualAdapters.length == 0) revert CommonErrors.NotInitialized();
        
        // Find the best platform for this market
        IPerpetualAdapter bestPlatform = _getBestPlatformForMarket(marketId);
        if (address(bestPlatform) == address(0)) revert CommonErrors.NotFound();
        
        // Transfer collateral from the user to this contract
        IERC20 baseAsset = IERC20(bestPlatform.getPosition(0).marketId); // This is a hack to get the base asset, in a real implementation we would have a proper way to get the base asset
        baseAsset.safeTransferFrom(msg.sender, address(this), collateral);
        
        // Approve the platform to spend the collateral
        baseAsset.safeApprove(address(bestPlatform), 0);
        baseAsset.safeApprove(address(bestPlatform), collateral);
        
        // Open the position
        positionId = bestPlatform.openPosition(marketId, size, leverage, collateral);
        
        // Store which adapter handles this position
        positionToAdapter[positionId] = address(bestPlatform);
        
        emit PositionOpened(positionId, marketId, size, leverage, collateral, address(bestPlatform));
        
        return positionId;
    }
    
    /**
     * @dev Closes an existing position
     * @param positionId The identifier for the position to close
     * @return pnl The profit or loss from the position (can be negative)
     */
    function closePosition(bytes32 positionId) external override nonReentrant returns (int256 pnl) {
        address adapterAddress = positionToAdapter[positionId];
        if (adapterAddress == address(0)) revert CommonErrors.NotFound();
        
        IPerpetualAdapter adapter = IPerpetualAdapter(adapterAddress);
        
        // Close the position
        pnl = adapter.closePosition(positionId);
        
        // Clean up the mapping
        delete positionToAdapter[positionId];
        
        emit PositionClosed(positionId, pnl, adapterAddress);
        
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
    ) external override nonReentrant returns (bool) {
        address adapterAddress = positionToAdapter[positionId];
        if (adapterAddress == address(0)) revert CommonErrors.NotFound();
        
        IPerpetualAdapter adapter = IPerpetualAdapter(adapterAddress);
        
        // Handle collateral changes if needed
        if (collateralDelta > 0) {
            // Adding collateral
            IERC20 baseAsset = IERC20(adapter.getPosition(0).marketId); // This is a hack to get the base asset, in a real implementation we would have a proper way to get the base asset
            baseAsset.safeTransferFrom(msg.sender, address(this), uint256(collateralDelta));
            
            // Approve the platform to spend the additional collateral
            baseAsset.safeApprove(address(adapter), 0);
            baseAsset.safeApprove(address(adapter), uint256(collateralDelta));
        }
        
        // Adjust the position
        adapter.adjustPosition(positionId, newSize, newLeverage, collateralDelta);
        
        emit PositionAdjusted(positionId, newSize, newLeverage, collateralDelta, adapterAddress);
        
        return true;
    }
    
    /**
     * @dev Gets the current position information
     * @param positionId The identifier for the position
     * @return position The position information
     */
    function getPosition(bytes32 positionId) external view override returns (Position memory) {
        address adapterAddress = positionToAdapter[positionId];
        if (adapterAddress == address(0)) revert CommonErrors.NotFound();
        
        IPerpetualAdapter adapter = IPerpetualAdapter(adapterAddress);
        IPerpetualAdapter.Position memory adapterPosition = adapter.getPosition(positionId);
        
        // Convert from adapter position to IPerpetualTrading position
        Position memory result = Position({
            marketId: adapterPosition.marketId,
            size: adapterPosition.size,
            entryPrice: adapterPosition.entryPrice,
            leverage: adapterPosition.leverage,
            collateral: adapterPosition.collateral,
            lastUpdated: adapterPosition.lastUpdated
        });
        
        return result;
    }
    
    /**
     * @dev Gets the current market price
     * @param marketId The identifier for the market
     * @return price The current market price
     */
    function getMarketPrice(bytes32 marketId) external view returns (uint256 price) {
        IPerpetualAdapter bestPlatform = _getBestPlatformForMarket(marketId);
        if (address(bestPlatform) == address(0)) revert CommonErrors.NotFound();
        
        return bestPlatform.getMarketPrice(marketId);
    }
    
    /**
     * @dev Calculates the profit or loss for a position
     * @param positionId The identifier for the position
     * @return pnl The profit or loss (can be negative)
     */
    function calculatePnL(bytes32 positionId) external view returns (int256 pnl) {
        address adapterAddress = positionToAdapter[positionId];
        if (adapterAddress == address(0)) revert CommonErrors.NotFound();
        
        IPerpetualAdapter adapter = IPerpetualAdapter(adapterAddress);
        return adapter.calculatePnL(positionId);
    }
    
    /**
     * @dev Gets the funding rate for a market
     * @param marketId The identifier for the market
     * @return fundingRate The current funding rate (can be negative)
     */
    function getFundingRate(bytes32 marketId) external view returns (int256 fundingRate) {
        // In a real implementation, we would get this from the platform
        // For simplicity, we just return 0
        return 0;
    }
    
    /**
     * @dev Gets the current value of a position
     * @param positionId The identifier for the position
     * @return value The current value of the position
     */
    function getPositionValue(bytes32 positionId) external view returns (uint256 value) {
        address adapterAddress = positionToAdapter[positionId];
        if (adapterAddress == address(0)) revert CommonErrors.NotFound();
        
        IPerpetualAdapter adapter = IPerpetualAdapter(adapterAddress);
        IPerpetualAdapter.Position memory position = adapter.getPosition(positionId);
        
        // Calculate position value: collateral + PnL
        int256 pnl = adapter.calculatePnL(positionId);
        if (pnl >= 0) {
            return position.collateral + uint256(pnl);
        } else {
            // If PnL is negative, subtract it from collateral (but don't go below 0)
            uint256 absPnl = uint256(-pnl);
            return position.collateral > absPnl ? position.collateral - absPnl : 0;
        }
    }
    
    /**
     * @dev Finds the best platform that supports a given market
     * @param marketId The identifier for the market
     * @return bestPlatform The platform that supports the market with the best conditions
     */
    function _getBestPlatformForMarket(bytes32 marketId) internal view returns (IPerpetualAdapter bestPlatform) {
        for (uint256 i = 0; i < perpetualAdapters.length; i++) {
            IPerpetualAdapter adapter = perpetualAdapters[i];
            
            if (adapter.isMarketSupported(marketId)) {
                // In a real implementation, we would compare fees, liquidity, etc.
                // For simplicity, we just return the first platform that supports the market
                return adapter;
            }
        }
        
        return IPerpetualAdapter(address(0));
    }
}
