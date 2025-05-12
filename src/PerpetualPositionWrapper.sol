// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {CommonErrors} from "./errors/CommonErrors.sol";
import {IPerpetualRouter} from "./interfaces/IPerpetualRouter.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/**
 * @title PerpetualPositionWrapper
 * @dev Manages perpetual positions for RWA exposure
 * This contract handles the creation, management, and valuation of perpetual positions
 */
contract PerpetualPositionWrapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Core components
    IPerpetualRouter public perpetualRouter;
    IERC20 public baseAsset;
    IPriceOracle public priceOracle;
    
    // Position parameters
    uint256 public leverage;
    bool public isLong;
    bytes32 public marketId;
    string public assetSymbol;
    
    // Position tracking
    uint256 public positionSize;
    uint256 public collateralAmount;
    uint256 public entryPrice;
    uint256 public lastUpdated;
    bool public positionOpen;
    
    // Events
    event PositionOpened(bytes32 marketId, uint256 size, uint256 collateral, uint256 leverage, bool isLong);
    event PositionClosed(bytes32 marketId, uint256 pnl);
    event PositionAdjusted(bytes32 marketId, uint256 newSize, uint256 newCollateral);
    event CollateralAdded(uint256 amount);
    event CollateralRemoved(uint256 amount);
    
    // Custom errors
    error PositionAlreadyOpen();
    error NoPositionOpen();
    error InsufficientCollateral();
    error InvalidLeverage();
    error InvalidMarket();
    error FailedToOpenPosition();
    error FailedToClosePosition();
    error FailedToAdjustPosition();
    
    /**
     * @dev Constructor
     * @param _perpetualRouter Address of the perpetual router contract
     * @param _baseAsset Address of the base asset (e.g., USDC)
     * @param _priceOracle Address of the price oracle
     * @param _marketId Market identifier for the perpetual position
     * @param _leverage Initial leverage for positions
     * @param _isLong Whether positions should be long (true) or short (false)
     * @param _assetSymbol Symbol of the asset being tracked (e.g., "BTC", "ETH", "SPX")
     */
    constructor(
        address _perpetualRouter,
        address _baseAsset,
        address _priceOracle,
        bytes32 _marketId,
        uint256 _leverage,
        bool _isLong,
        string memory _assetSymbol
    ) Ownable(msg.sender) {
        if (_perpetualRouter == address(0) || _baseAsset == address(0) || _priceOracle == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        if (_leverage == 0 || _leverage > 10) {
            revert InvalidLeverage();
        }
        
        perpetualRouter = IPerpetualRouter(_perpetualRouter);
        baseAsset = IERC20(_baseAsset);
        priceOracle = IPriceOracle(_priceOracle);
        marketId = _marketId;
        leverage = _leverage;
        isLong = _isLong;
        assetSymbol = _assetSymbol;
        positionOpen = false;
    }
    
    /**
     * @dev Opens a perpetual position with the specified collateral
     * @param _collateralAmount Amount of collateral to use
     */
    function openPosition(uint256 _collateralAmount) external onlyOwner nonReentrant {
        if (positionOpen) {
            revert PositionAlreadyOpen();
        }
        if (_collateralAmount == 0) {
            revert InsufficientCollateral();
        }
        
        // Ensure we have enough balance
        uint256 balance = baseAsset.balanceOf(address(this));
        if (balance < _collateralAmount) {
            revert InsufficientCollateral();
        }
        
        // Approve the router to spend the collateral
        baseAsset.approve(address(perpetualRouter), _collateralAmount);
        
        // Open the position
        try perpetualRouter.openPosition(marketId, _collateralAmount, leverage, isLong) returns (uint256 size, uint256 price) {
            positionSize = size;
            entryPrice = price;
            collateralAmount = _collateralAmount;
            positionOpen = true;
            lastUpdated = block.timestamp;
            
            emit PositionOpened(marketId, size, collateralAmount, leverage, isLong);
        } catch {
            revert FailedToOpenPosition();
        }
    }
    
    /**
     * @dev Closes the current perpetual position
     */
    function closePosition() external onlyOwner nonReentrant {
        if (!positionOpen) {
            revert NoPositionOpen();
        }
        
        try perpetualRouter.closePosition(marketId) returns (uint256 pnl) {
            positionOpen = false;
            positionSize = 0;
            collateralAmount = 0;
            
            emit PositionClosed(marketId, pnl);
        } catch {
            revert FailedToClosePosition();
        }
    }
    
    /**
     * @dev Adjusts the size of the current position
     * @param newCollateralAmount New collateral amount
     */
    function adjustPosition(uint256 newCollateralAmount) external onlyOwner nonReentrant {
        if (!positionOpen) {
            revert NoPositionOpen();
        }
        if (newCollateralAmount == 0) {
            revert InsufficientCollateral();
        }
        
        uint256 currentCollateral = collateralAmount;
        
        if (newCollateralAmount > currentCollateral) {
            // Adding collateral
            uint256 additionalCollateral = newCollateralAmount - currentCollateral;
            uint256 balance = baseAsset.balanceOf(address(this));
            if (balance < additionalCollateral) {
                revert InsufficientCollateral();
            }
            
            // Approve the router to spend the additional collateral
            baseAsset.approve(address(perpetualRouter), additionalCollateral);
            
            try perpetualRouter.addCollateral(marketId, additionalCollateral) {
                collateralAmount = newCollateralAmount;
                
                // Update position size based on new collateral
                (uint256 newSize, ) = perpetualRouter.getPositionDetails(marketId);
                positionSize = newSize;
                lastUpdated = block.timestamp;
                
                emit PositionAdjusted(marketId, newSize, newCollateralAmount);
                emit CollateralAdded(additionalCollateral);
            } catch {
                revert FailedToAdjustPosition();
            }
        } else if (newCollateralAmount < currentCollateral) {
            // Removing collateral
            uint256 collateralToRemove = currentCollateral - newCollateralAmount;
            
            try perpetualRouter.removeCollateral(marketId, collateralToRemove) {
                collateralAmount = newCollateralAmount;
                
                // Update position size based on new collateral
                (uint256 newSize, ) = perpetualRouter.getPositionDetails(marketId);
                positionSize = newSize;
                lastUpdated = block.timestamp;
                
                emit PositionAdjusted(marketId, newSize, newCollateralAmount);
                emit CollateralRemoved(collateralToRemove);
            } catch {
                revert FailedToAdjustPosition();
            }
        }
    }
    
    /**
     * @dev Changes the leverage of the position
     * @param newLeverage New leverage value
     */
    function setLeverage(uint256 newLeverage) external onlyOwner {
        if (newLeverage == 0 || newLeverage > 10) {
            revert InvalidLeverage();
        }
        
        leverage = newLeverage;
        
        // If position is open, adjust it
        if (positionOpen) {
            try perpetualRouter.adjustLeverage(marketId, newLeverage) {
                // Update position size based on new leverage
                (uint256 newSize, ) = perpetualRouter.getPositionDetails(marketId);
                positionSize = newSize;
                lastUpdated = block.timestamp;
                
                emit PositionAdjusted(marketId, newSize, collateralAmount);
            } catch {
                revert FailedToAdjustPosition();
            }
        }
    }
    
    /**
     * @dev Gets the current value of the position including PnL
     * @return totalValue The total value of the position in base asset units
     */
    function getPositionValue() public view returns (uint256 totalValue) {
        if (!positionOpen) {
            return 0;
        }
        
        // Get current position details
        (uint256 size, uint256 currentPrice) = perpetualRouter.getPositionDetails(marketId);
        
        // Calculate PnL
        int256 pnl;
        if (isLong) {
            // For long positions: (currentPrice - entryPrice) * size / entryPrice
            if (currentPrice > entryPrice) {
                // Profit
                pnl = int256((currentPrice - entryPrice) * size / entryPrice);
            } else if (currentPrice < entryPrice) {
                // Loss
                pnl = -int256((entryPrice - currentPrice) * size / entryPrice);
            } else {
                // No change
                pnl = 0;
            }
        } else {
            // For short positions: (entryPrice - currentPrice) * size / entryPrice
            if (entryPrice > currentPrice) {
                // Profit
                pnl = int256((entryPrice - currentPrice) * size / entryPrice);
            } else if (entryPrice < currentPrice) {
                // Loss
                pnl = -int256((currentPrice - entryPrice) * size / entryPrice);
            } else {
                // No change
                pnl = 0;
            }
        }
        
        // Total value is collateral + PnL
        totalValue = collateralAmount;
        if (pnl > 0) {
            totalValue += uint256(pnl);
        } else if (pnl < 0) {
            if (uint256(-pnl) < collateralAmount) {
                totalValue -= uint256(-pnl);
            } else {
                // If PnL loss exceeds collateral, position is liquidated
                totalValue = 0;
            }
        }
        // If pnl == 0, totalValue remains equal to collateralAmount
        
        return totalValue;
    }
    
    /**
     * @dev Gets the current position details
     * @return size The size of the position
     * @return collateral The collateral amount
     * @return currentPrice The current price of the asset
     * @return pnl The profit or loss of the position
     * @return isActive Whether the position is active
     */
    function getPositionDetails() external view returns (
        uint256 size,
        uint256 collateral,
        uint256 currentPrice,
        int256 pnl,
        bool isActive
    ) {
        if (!positionOpen) {
            return (0, 0, 0, 0, false);
        }
        
        // Get current position details from router
        (size, currentPrice) = perpetualRouter.getPositionDetails(marketId);
        collateral = collateralAmount;
        
        // Calculate PnL
        if (isLong) {
            // For long positions: (currentPrice - entryPrice) * size / entryPrice
            pnl = currentPrice > entryPrice
                ? int256((currentPrice - entryPrice) * size / entryPrice)
                : -int256((entryPrice - currentPrice) * size / entryPrice);
        } else {
            // For short positions: (entryPrice - currentPrice) * size / entryPrice
            pnl = entryPrice > currentPrice
                ? int256((entryPrice - currentPrice) * size / entryPrice)
                : -int256((currentPrice - entryPrice) * size / entryPrice);
        }
        
        isActive = positionOpen;
        
        return (size, collateral, currentPrice, pnl, isActive);
    }
    
    /**
     * @dev Withdraws base asset from the wrapper (only unused funds)
     * @param amount Amount to withdraw
     * @param recipient Address to receive the funds
     */
    function withdrawBaseAsset(uint256 amount, address recipient) external onlyOwner nonReentrant {
        if (recipient == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        // Calculate available balance (total balance minus collateral)
        uint256 totalBalance = baseAsset.balanceOf(address(this));
        uint256 availableBalance = positionOpen ? totalBalance - collateralAmount : totalBalance;
        
        if (amount > availableBalance) {
            revert InsufficientCollateral();
        }
        
        baseAsset.safeTransfer(recipient, amount);
    }
    
    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Address of the token to recover
     * @param amount Amount to recover
     * @param recipient Address to receive the tokens
     */
    function recoverToken(address token, uint256 amount, address recipient) external onlyOwner nonReentrant {
        if (recipient == address(0)) {
            revert CommonErrors.ZeroAddress();
        }
        
        // Prevent recovering base asset that's being used as collateral
        if (token == address(baseAsset) && positionOpen) {
            uint256 totalBalance = baseAsset.balanceOf(address(this));
            uint256 availableBalance = totalBalance - collateralAmount;
            if (amount > availableBalance) {
                revert InsufficientCollateral();
            }
        }
        
        IERC20(token).safeTransfer(recipient, amount);
    }
}
