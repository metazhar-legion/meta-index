// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRWASyntheticToken} from "./interfaces/IRWASyntheticToken.sol";
import {IPerpetualTrading} from "./interfaces/IPerpetualTrading.sol";

/**
 * @title RWASyntheticSP500
 * @dev Synthetic token representing the S&P 500 Index backed by perpetual futures
 */
contract RWASyntheticSP500 is IRWASyntheticToken, ERC20, Ownable {
    using SafeERC20 for IERC20;

    // Constants
    bytes32 public constant MARKET_ID = "SP500-USD";
    uint256 public constant COLLATERAL_RATIO = 5000; // 50% in basis points
    
    // Asset info
    AssetInfo private assetInfo;
    
    // Perpetual trading platform
    IPerpetualTrading public perpetualTrading;
    
    // Base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // Position tracking
    bytes32 public activePositionId;
    uint256 public totalCollateral;
    uint256 public leverage = 2; // 2x leverage by default
    
    // Oracle
    address public priceOracle;
    uint256 public lastOracleUpdate;
    
    // Events
    event PositionOpened(bytes32 positionId, int256 size, uint256 collateral, uint256 leverage);
    event PositionClosed(bytes32 positionId, int256 pnl);
    event PositionAdjusted(bytes32 positionId, int256 newSize, uint256 newLeverage);
    event PriceUpdated(uint256 price, uint256 timestamp);
    event CollateralAdded(uint256 amount);
    event CollateralRemoved(uint256 amount);
    
    /**
     * @dev Constructor
     * @param _baseAsset Address of the base asset (e.g., USDC)
     * @param _perpetualTrading Address of the perpetual trading platform
     * @param _priceOracle Address of the price oracle
     */
    constructor(
        address _baseAsset,
        address _perpetualTrading,
        address _priceOracle
    ) ERC20("S&P 500 Index Synthetic", "sSP500") Ownable(msg.sender) {
        require(_baseAsset != address(0), "Invalid base asset address");
        require(_perpetualTrading != address(0), "Invalid perpetual trading address");
        require(_priceOracle != address(0), "Invalid price oracle address");
        
        baseAsset = IERC20(_baseAsset);
        perpetualTrading = IPerpetualTrading(_perpetualTrading);
        priceOracle = _priceOracle;
        
        // Initialize asset info
        assetInfo = AssetInfo({
            name: "S&P 500 Index",
            symbol: "SPX",
            assetType: AssetType.EQUITY_INDEX,
            oracle: _priceOracle,
            lastPrice: 0,
            lastUpdated: 0,
            marketId: MARKET_ID,
            isActive: true
        });
        
        // Update initial price
        updatePrice();
    }
    
    /**
     * @dev Gets information about the synthetic asset
     * @return info The asset information
     */
    function getAssetInfo() external view override returns (AssetInfo memory info) {
        return assetInfo;
    }
    
    /**
     * @dev Gets the current price of the asset in USD
     * @return price The current price (scaled by 10^18)
     */
    function getCurrentPrice() external view override returns (uint256 price) {
        return assetInfo.lastPrice;
    }
    
    /**
     * @dev Updates the asset price from the oracle
     * @return success Whether the update was successful
     */
    function updatePrice() public override returns (bool success) {
        // In a real implementation, this would call the oracle
        // For now, we'll use the perpetual trading platform's market price
        uint256 newPrice = perpetualTrading.getMarketPrice(MARKET_ID);
        require(newPrice > 0, "Invalid price from oracle");
        
        assetInfo.lastPrice = newPrice;
        assetInfo.lastUpdated = block.timestamp;
        lastOracleUpdate = block.timestamp;
        
        emit PriceUpdated(newPrice, block.timestamp);
        return true;
    }
    
    /**
     * @dev Mints synthetic tokens
     * @param to The address to mint tokens to
     * @param amount The amount to mint
     * @return success Whether the mint was successful
     */
    function mint(address to, uint256 amount) external override onlyOwner returns (bool success) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be positive");
        
        // Transfer base asset from sender to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate collateral amount (e.g., 50% of the total)
        uint256 collateralAmount = (amount * COLLATERAL_RATIO) / 10000;
        
        // Open or adjust perpetual position
        _managePosition(collateralAmount);
        
        // Mint synthetic tokens
        _mint(to, amount);
        
        return true;
    }
    
    /**
     * @dev Burns synthetic tokens
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     * @return success Whether the burn was successful
     */
    function burn(address from, uint256 amount) external override onlyOwner returns (bool success) {
        require(from != address(0), "Invalid address");
        require(amount > 0, "Amount must be positive");
        require(balanceOf(from) >= amount, "Insufficient balance");
        
        // Calculate collateral to release
        uint256 collateralToRelease = (amount * COLLATERAL_RATIO) / 10000;
        
        // Adjust perpetual position
        if (activePositionId != bytes32(0)) {
            _reducePosition(collateralToRelease);
        }
        
        // Burn synthetic tokens
        _burn(from, amount);
        
        // Transfer base asset back to sender
        baseAsset.safeTransfer(msg.sender, amount);
        
        return true;
    }
    
    /**
     * @dev Manages the perpetual position when adding collateral
     * @param collateralAmount The amount of collateral to add
     */
    function _managePosition(uint256 collateralAmount) internal {
        if (activePositionId == bytes32(0)) {
            // No active position, open a new one
            _openPosition(collateralAmount);
        } else {
            // Adjust existing position
            _increasePosition(collateralAmount);
        }
    }
    
    /**
     * @dev Opens a new perpetual position
     * @param collateralAmount The amount of collateral to use
     */
    function _openPosition(uint256 collateralAmount) internal {
        // Calculate position size based on collateral and leverage
        int256 size = int256((collateralAmount * leverage));
        
        // Approve collateral transfer to perpetual trading platform
        baseAsset.approve(address(perpetualTrading), collateralAmount);
        
        // Open position
        bytes32 positionId = perpetualTrading.openPosition(
            MARKET_ID,
            size,
            leverage,
            collateralAmount
        );
        
        // Update state
        activePositionId = positionId;
        totalCollateral = collateralAmount;
        
        emit PositionOpened(positionId, size, collateralAmount, leverage);
    }
    
    /**
     * @dev Increases an existing perpetual position
     * @param additionalCollateral The amount of additional collateral
     */
    function _increasePosition(uint256 additionalCollateral) internal {
        require(activePositionId != bytes32(0), "No active position");
        
        // Get current position
        IPerpetualTrading.Position memory position = perpetualTrading.getPosition(activePositionId);
        
        // Calculate new size
        int256 newSize = position.size + int256((additionalCollateral * leverage));
        
        // Approve collateral transfer to perpetual trading platform
        baseAsset.approve(address(perpetualTrading), additionalCollateral);
        
        // Adjust position
        perpetualTrading.adjustPosition(
            activePositionId,
            newSize,
            leverage,
            int256(additionalCollateral)
        );
        
        // Update state
        totalCollateral += additionalCollateral;
        
        emit PositionAdjusted(activePositionId, newSize, leverage);
        emit CollateralAdded(additionalCollateral);
    }
    
    /**
     * @dev Reduces an existing perpetual position
     * @param collateralToRemove The amount of collateral to remove
     */
    function _reducePosition(uint256 collateralToRemove) internal {
        require(activePositionId != bytes32(0), "No active position");
        require(collateralToRemove <= totalCollateral, "Insufficient collateral");
        
        // Get current position
        IPerpetualTrading.Position memory position = perpetualTrading.getPosition(activePositionId);
        
        // Calculate new size
        int256 newSize = position.size - int256((collateralToRemove * leverage));
        
        if (newSize <= 0) {
            // Close position entirely
            int256 pnl = perpetualTrading.closePosition(activePositionId);
            
            // Reset state
            activePositionId = bytes32(0);
            totalCollateral = 0;
            
            emit PositionClosed(activePositionId, pnl);
        } else {
            // Adjust position
            perpetualTrading.adjustPosition(
                activePositionId,
                newSize,
                leverage,
                -int256(collateralToRemove)
            );
            
            // Update state
            totalCollateral -= collateralToRemove;
            
            emit PositionAdjusted(activePositionId, newSize, leverage);
            emit CollateralRemoved(collateralToRemove);
        }
    }
    
    /**
     * @dev Sets the leverage for future positions
     * @param _leverage The new leverage value
     */
    function setLeverage(uint256 _leverage) external onlyOwner {
        require(_leverage > 0 && _leverage <= 10, "Invalid leverage value");
        leverage = _leverage;
    }
    
    /**
     * @dev Sets a new price oracle
     * @param _priceOracle The address of the new price oracle
     */
    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Invalid price oracle address");
        priceOracle = _priceOracle;
        assetInfo.oracle = _priceOracle;
    }
    
    /**
     * @dev Gets the total value of the synthetic asset
     * @return value The total value in the base asset
     */
    function getTotalValue() external view returns (uint256 value) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) return 0;
        
        uint256 price = assetInfo.lastPrice;
        return (totalSupply * price) / 1e18;
    }
}
