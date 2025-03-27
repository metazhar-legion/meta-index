// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {CommonErrors} from "./errors/CommonErrors.sol";
import {IAssetWrapper} from "./interfaces/IAssetWrapper.sol";
import {IRWASyntheticToken} from "./interfaces/IRWASyntheticToken.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/**
 * @title RWAAssetWrapper
 * @dev Wrapper for Real World Assets (RWAs) that manages the 20/80 split between
 * RWA tokens and yield strategies. This abstracts the implementation details from the vault.
 */
contract RWAAssetWrapper is IAssetWrapper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Allocation constants
    uint256 public constant RWA_ALLOCATION = 2000; // 20% in basis points
    uint256 public constant YIELD_ALLOCATION = 8000; // 80% in basis points
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points
    
    // The RWA synthetic token
    IRWASyntheticToken public rwaToken;
    
    // The yield strategy
    IYieldStrategy public yieldStrategy;
    
    // The base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // The price oracle
    IPriceOracle public priceOracle;
    
    // The name of this RWA wrapper
    string public name;
    
    // Total capital allocated to this wrapper
    uint256 public totalAllocated;
    
    // Yield strategy shares owned by this wrapper
    uint256 private yieldShares;
    
    // Events
    event CapitalAllocated(uint256 totalAmount, uint256 rwaAmount, uint256 yieldAmount);
    event CapitalWithdrawn(uint256 requestedAmount, uint256 actualAmount);
    event YieldHarvested(uint256 amount);
    
    /**
     * @dev Constructor
     * @param _name The name of this RWA wrapper
     * @param _baseAsset The base asset token (e.g., USDC)
     * @param _rwaToken The RWA synthetic token
     * @param _yieldStrategy The yield strategy
     * @param _priceOracle The price oracle
     */
    constructor(
        string memory _name,
        IERC20 _baseAsset,
        IRWASyntheticToken _rwaToken,
        IYieldStrategy _yieldStrategy,
        IPriceOracle _priceOracle
    ) Ownable(msg.sender) {
        if (address(_baseAsset) == address(0)) revert CommonErrors.ZeroAddress();
        if (address(_rwaToken) == address(0)) revert CommonErrors.ZeroAddress();
        if (address(_yieldStrategy) == address(0)) revert CommonErrors.ZeroAddress();
        if (address(_priceOracle) == address(0)) revert CommonErrors.ZeroAddress();
        
        name = _name;
        baseAsset = _baseAsset;
        rwaToken = _rwaToken;
        yieldStrategy = _yieldStrategy;
        priceOracle = _priceOracle;
        
        // Approve tokens for the RWA token and yield strategy
        baseAsset.approve(address(rwaToken), type(uint256).max);
        baseAsset.approve(address(yieldStrategy), type(uint256).max);
    }
    
    /**
     * @dev Get the current value of this asset in terms of the base asset
     * @return The current value in base asset units
     */
    function getValueInBaseAsset() external view override returns (uint256) {
        // Get the value of RWA tokens
        uint256 rwaValue = getRWAValue();
        
        // Get the value of yield strategy
        uint256 yieldValue = getYieldValue();
        
        // Return the total value
        return rwaValue + yieldValue;
    }
    
    /**
     * @dev Allocate more capital to this asset
     * @param amount The amount of base asset to allocate
     * @return success Whether the allocation was successful
     */
    function allocateCapital(uint256 amount) external override nonReentrant returns (bool) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer the base asset from the caller to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate the allocation amounts
        uint256 rwaAmount = (amount * RWA_ALLOCATION) / BASIS_POINTS;
        uint256 yieldAmount = amount - rwaAmount;
        
        // Allocate to RWA token
        rwaToken.mint(address(this), rwaAmount);
        
        // Allocate to yield strategy
        uint256 shares = yieldStrategy.deposit(yieldAmount);
        yieldShares += shares;
        
        // Update total allocated
        totalAllocated += amount;
        
        emit CapitalAllocated(amount, rwaAmount, yieldAmount);
        return true;
    }
    
    /**
     * @dev Withdraw capital from this asset
     * @param amount The amount of base asset to withdraw
     * @return actualAmount The actual amount withdrawn
     */
    function withdrawCapital(uint256 amount) external override nonReentrant returns (uint256) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (amount > totalAllocated) revert CommonErrors.ValueTooHigh();
        
        // Calculate the withdrawal amounts based on current allocation
        uint256 totalValue = getRWAValue() + getYieldValue();
        uint256 rwaRatio = getRWAValue() * BASIS_POINTS / totalValue;
        
        uint256 rwaWithdrawAmount = (amount * rwaRatio) / BASIS_POINTS;
        uint256 yieldWithdrawAmount = amount - rwaWithdrawAmount;
        
        // Withdraw from RWA token
        if (rwaWithdrawAmount > 0) {
            rwaToken.burn(address(this), rwaWithdrawAmount);
        }
        
        // Withdraw from yield strategy
        if (yieldWithdrawAmount > 0) {
            // Calculate shares to withdraw based on value proportion
            uint256 yieldValue = getYieldValue();
            uint256 sharesToWithdraw = yieldValue > 0 ? (yieldWithdrawAmount * yieldShares) / yieldValue : 0;
            
            if (sharesToWithdraw > 0) {
                yieldStrategy.withdraw(sharesToWithdraw);
                yieldShares -= sharesToWithdraw;
            }
        }
        
        // Transfer the base asset to the caller
        uint256 actualAmount = baseAsset.balanceOf(address(this));
        if (actualAmount > 0) {
            baseAsset.safeTransfer(msg.sender, actualAmount);
        }
        
        // Update total allocated
        totalAllocated = totalAllocated > actualAmount ? totalAllocated - actualAmount : 0;
        
        emit CapitalWithdrawn(amount, actualAmount);
        return actualAmount;
    }
    
    /**
     * @dev Get the underlying tokens this wrapper manages
     * @return tokens Array of token addresses
     */
    function getUnderlyingTokens() external view override returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = address(rwaToken);
        tokens[1] = address(yieldStrategy);
        return tokens;
    }
    
    /**
     * @dev Get the name of this asset wrapper
     * @return The name of the asset wrapper
     */
    function getName() external view override returns (string memory) {
        return name;
    }
    
    /**
     * @dev Harvest any yield generated by this asset wrapper
     * @return harvestedAmount The amount of yield harvested in base asset units
     */
    function harvestYield() external override nonReentrant returns (uint256) {
        // Harvest yield from the yield strategy
        uint256 harvestedAmount = yieldStrategy.harvestYield();
        
        // Transfer the harvested yield to the caller
        if (harvestedAmount > 0) {
            baseAsset.safeTransfer(msg.sender, harvestedAmount);
        }
        
        emit YieldHarvested(harvestedAmount);
        return harvestedAmount;
    }
    
    /**
     * @dev Get the base asset used by this wrapper
     * @return The address of the base asset token
     */
    function getBaseAsset() external view override returns (address) {
        return address(baseAsset);
    }
    
    /**
     * @dev Get the value of RWA tokens
     * @return The value in base asset units
     */
    function getRWAValue() public view returns (uint256) {
        uint256 rwaBalance = rwaToken.balanceOf(address(this));
        if (rwaBalance == 0) return 0;
        
        // Get the price of the RWA token
        uint256 rwaPrice = priceOracle.getPrice(address(rwaToken));
        
        // Calculate the value - use 18 decimals for price and convert to base asset decimals
        uint8 baseDecimals = IERC20Metadata(address(baseAsset)).decimals();
        return (rwaBalance * rwaPrice) / 10**18;
    }
    
    /**
     * @dev Get the value of the yield strategy
     * @return The value in base asset units
     */
    function getYieldValue() public view returns (uint256) {
        if (yieldShares == 0) return 0;
        
        // Get the value of the yield shares
        return yieldStrategy.getValueOfShares(yieldShares);
    }
    
    /**
     * @dev Rebalance the allocation between RWA and yield
     * This ensures the 20/80 split is maintained
     */
    function rebalance() external nonReentrant onlyOwner {
        uint256 totalValue = getRWAValue() + getYieldValue();
        if (totalValue == 0) return;
        
        uint256 currentRwaValue = getRWAValue();
        uint256 targetRwaValue = (totalValue * RWA_ALLOCATION) / BASIS_POINTS;
        
        if (currentRwaValue < targetRwaValue) {
            // Need to allocate more to RWA
            uint256 amountToMove = targetRwaValue - currentRwaValue;
            
            // Calculate shares to withdraw based on value proportion
            uint256 yieldValue = getYieldValue();
            uint256 sharesToWithdraw = yieldValue > 0 ? (amountToMove * yieldShares) / yieldValue : 0;
            
            if (sharesToWithdraw > 0) {
                yieldStrategy.withdraw(sharesToWithdraw);
                yieldShares -= sharesToWithdraw;
                
                // Allocate to RWA token
                rwaToken.mint(address(this), amountToMove);
            }
        } else if (currentRwaValue > targetRwaValue) {
            // Need to allocate more to yield
            uint256 amountToMove = currentRwaValue - targetRwaValue;
            
            // Withdraw from RWA token
            rwaToken.burn(address(this), amountToMove);
            
            // Allocate to yield strategy
            uint256 shares = yieldStrategy.deposit(amountToMove);
            yieldShares += shares;
        }
    }
}
