// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ICapitalAllocationManager} from "./interfaces/ICapitalAllocationManager.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {IRWASyntheticToken} from "./interfaces/IRWASyntheticToken.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title CapitalAllocationManager
 * @dev Manages capital allocation between RWA synthetics and yield strategies
 */
contract CapitalAllocationManager is ICapitalAllocationManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    
    // Base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // Overall allocation
    Allocation public allocation;
    
    // Yield strategies
    StrategyAllocation[] public yieldStrategies;
    mapping(address => uint256) public yieldStrategyIndexes;
    mapping(address => bool) public isActiveYieldStrategy;
    
    // RWA tokens
    RWAAllocation[] public rwaTokens;
    mapping(address => uint256) public rwaTokenIndexes;
    mapping(address => bool) public isActiveRWAToken;
    
    // Events
    event AllocationUpdated(uint256 rwaPercentage, uint256 yieldPercentage, uint256 liquidityBufferPercentage);
    event YieldStrategyAdded(address indexed strategy, uint256 percentage);
    event YieldStrategyUpdated(address indexed strategy, uint256 percentage);
    event YieldStrategyRemoved(address indexed strategy);
    event RWATokenAdded(address indexed rwaToken, uint256 percentage);
    event RWATokenUpdated(address indexed rwaToken, uint256 percentage);
    event RWATokenRemoved(address indexed rwaToken);
    event Rebalanced(uint256 timestamp);
    
    /**
     * @dev Constructor
     * @param _baseAsset Address of the base asset (e.g., USDC)
     */
    constructor(address _baseAsset) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        baseAsset = IERC20(_baseAsset);
        
        // Default allocation: 20% RWA, 75% yield, 5% liquidity buffer
        allocation = Allocation({
            rwaPercentage: 2000,
            yieldPercentage: 7500,
            liquidityBufferPercentage: 500,
            lastRebalanced: block.timestamp
        });
    }
    
    /**
     * @dev Sets the overall allocation percentages
     * @param rwaPercentage Percentage for RWA synthetics (in basis points)
     * @param yieldPercentage Percentage for yield strategies (in basis points)
     * @param liquidityBufferPercentage Percentage for liquidity buffer (in basis points)
     * @return success Whether the allocation was set successfully
     */
    function setAllocation(
        uint256 rwaPercentage,
        uint256 yieldPercentage,
        uint256 liquidityBufferPercentage
    ) external override onlyOwner returns (bool success) {
        if (rwaPercentage + yieldPercentage + liquidityBufferPercentage != BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        allocation.rwaPercentage = rwaPercentage;
        allocation.yieldPercentage = yieldPercentage;
        allocation.liquidityBufferPercentage = liquidityBufferPercentage;
        
        emit AllocationUpdated(rwaPercentage, yieldPercentage, liquidityBufferPercentage);
        return true;
    }
    
    /**
     * @dev Adds a yield strategy with an allocation percentage
     * @param strategy Address of the yield strategy
     * @param percentage Percentage allocation within yield portion (in basis points)
     * @return success Whether the strategy was added successfully
     */
    function addYieldStrategy(address strategy, uint256 percentage) external override onlyOwner returns (bool success) {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        if (isActiveYieldStrategy[strategy]) revert CommonErrors.AlreadyExists();
        if (percentage == 0) revert CommonErrors.ZeroValue();
        
        // Check that total percentage doesn't exceed 100%
        uint256 totalPercentage = getTotalYieldPercentage();
        if (totalPercentage + percentage > BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        // Add strategy
        yieldStrategies.push(StrategyAllocation({
            strategy: strategy,
            percentage: percentage,
            active: true
        }));
        
        yieldStrategyIndexes[strategy] = yieldStrategies.length - 1;
        isActiveYieldStrategy[strategy] = true;
        
        emit YieldStrategyAdded(strategy, percentage);
        return true;
    }
    
    /**
     * @dev Updates a yield strategy's allocation percentage
     * @param strategy Address of the yield strategy
     * @param percentage New percentage allocation (in basis points)
     * @return success Whether the strategy was updated successfully
     */
    function updateYieldStrategy(address strategy, uint256 percentage) external override onlyOwner returns (bool success) {
        if (!isActiveYieldStrategy[strategy]) revert CommonErrors.NotFound();
        if (percentage == 0) revert CommonErrors.ZeroValue();
        
        uint256 index = yieldStrategyIndexes[strategy];
        uint256 oldPercentage = yieldStrategies[index].percentage;
        
        // Check that total percentage doesn't exceed 100%
        uint256 totalPercentage = getTotalYieldPercentage() - oldPercentage;
        if (totalPercentage + percentage > BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        // Update strategy
        yieldStrategies[index].percentage = percentage;
        
        emit YieldStrategyUpdated(strategy, percentage);
        return true;
    }
    
    /**
     * @dev Removes a yield strategy
     * @param strategy Address of the yield strategy to remove
     * @return success Whether the strategy was removed successfully
     */
    function removeYieldStrategy(address strategy) external override onlyOwner returns (bool success) {
        if (!isActiveYieldStrategy[strategy]) revert CommonErrors.NotFound();
        
        uint256 index = yieldStrategyIndexes[strategy];
        
        // Mark as inactive instead of removing from array to preserve indexes
        yieldStrategies[index].active = false;
        isActiveYieldStrategy[strategy] = false;
        
        emit YieldStrategyRemoved(strategy);
        return true;
    }
    
    /**
     * @dev Adds an RWA synthetic token with an allocation percentage
     * @param rwaToken Address of the RWA synthetic token
     * @param percentage Percentage allocation within RWA portion (in basis points)
     * @return success Whether the RWA token was added successfully
     */
    function addRWAToken(address rwaToken, uint256 percentage) external override onlyOwner returns (bool success) {
        if (rwaToken == address(0)) revert CommonErrors.ZeroAddress();
        if (isActiveRWAToken[rwaToken]) revert CommonErrors.AlreadyExists();
        if (percentage == 0) revert CommonErrors.ZeroValue();
        
        // Check that total percentage doesn't exceed 100%
        uint256 totalPercentage = getTotalRWAPercentage();
        if (totalPercentage + percentage > BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        // Add RWA token
        rwaTokens.push(RWAAllocation({
            rwaToken: rwaToken,
            percentage: percentage,
            active: true
        }));
        
        rwaTokenIndexes[rwaToken] = rwaTokens.length - 1;
        isActiveRWAToken[rwaToken] = true;
        
        emit RWATokenAdded(rwaToken, percentage);
        return true;
    }
    
    /**
     * @dev Updates an RWA synthetic token's allocation percentage
     * @param rwaToken Address of the RWA synthetic token
     * @param percentage New percentage allocation (in basis points)
     * @return success Whether the RWA token was updated successfully
     */
    function updateRWAToken(address rwaToken, uint256 percentage) external override onlyOwner returns (bool success) {
        if (!isActiveRWAToken[rwaToken]) revert CommonErrors.NotFound();
        if (percentage == 0) revert CommonErrors.ZeroValue();
        
        uint256 index = rwaTokenIndexes[rwaToken];
        uint256 oldPercentage = rwaTokens[index].percentage;
        
        // Check that total percentage doesn't exceed 100%
        uint256 totalPercentage = getTotalRWAPercentage() - oldPercentage;
        if (totalPercentage + percentage > BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        // Update RWA token
        rwaTokens[index].percentage = percentage;
        
        emit RWATokenUpdated(rwaToken, percentage);
        return true;
    }
    
    /**
     * @dev Removes an RWA synthetic token
     * @param rwaToken Address of the RWA synthetic token to remove
     * @return success Whether the RWA token was removed successfully
     */
    function removeRWAToken(address rwaToken) external override onlyOwner returns (bool success) {
        if (!isActiveRWAToken[rwaToken]) revert CommonErrors.NotFound();
        
        uint256 index = rwaTokenIndexes[rwaToken];
        
        // Mark as inactive instead of removing from array to preserve indexes
        rwaTokens[index].active = false;
        isActiveRWAToken[rwaToken] = false;
        
        emit RWATokenRemoved(rwaToken);
        return true;
    }
    
    /**
     * @dev Rebalances the capital allocation according to the set percentages
     * @return success Whether the rebalance was successful
     */
    function rebalance() external override onlyOwner nonReentrant returns (bool success) {
        // Get total value of assets under management
        uint256 totalValue = getTotalValue();
        if (totalValue == 0) revert CommonErrors.ZeroValue();
        
        // Calculate target values for each allocation
        uint256 targetRWAValue = (totalValue * allocation.rwaPercentage) / BASIS_POINTS;
        uint256 targetYieldValue = (totalValue * allocation.yieldPercentage) / BASIS_POINTS;
        uint256 targetBufferValue = (totalValue * allocation.liquidityBufferPercentage) / BASIS_POINTS;
        
        // Current values
        uint256 currentRWAValue = getRWAValue();
        uint256 currentYieldValue = getYieldValue();
        uint256 currentBufferValue = getLiquidityBufferValue();
        
        // Rebalance RWA allocation
        if (currentRWAValue < targetRWAValue) {
            // Need to increase RWA allocation
            uint256 amountToAdd = targetRWAValue - currentRWAValue;
            
            // Take from buffer first, then from yield if needed
            if (currentBufferValue > targetBufferValue) {
                uint256 amountFromBuffer = currentBufferValue - targetBufferValue;
                if (amountFromBuffer > amountToAdd) {
                    amountFromBuffer = amountToAdd;
                }
                
                _allocateToRWA(amountFromBuffer);
                amountToAdd -= amountFromBuffer;
            }
            
            if (amountToAdd > 0 && currentYieldValue > targetYieldValue) {
                uint256 amountFromYield = currentYieldValue - targetYieldValue;
                if (amountFromYield > amountToAdd) {
                    amountFromYield = amountToAdd;
                }
                
                _withdrawFromYield(amountFromYield);
                _allocateToRWA(amountFromYield);
            }
        } else if (currentRWAValue > targetRWAValue) {
            // Need to decrease RWA allocation
            uint256 amountToRemove = currentRWAValue - targetRWAValue;
            
            _withdrawFromRWA(amountToRemove);
            
            // Allocate to yield or buffer as needed
            if (currentYieldValue < targetYieldValue) {
                uint256 amountToYield = targetYieldValue - currentYieldValue;
                if (amountToYield > amountToRemove) {
                    amountToYield = amountToRemove;
                }
                
                _allocateToYield(amountToYield);
                amountToRemove -= amountToYield;
            }
            
            // Any remaining goes to buffer
            if (amountToRemove > 0) {
                // Already in buffer, no action needed
            }
        }
        
        // Rebalance yield allocation
        if (currentYieldValue < targetYieldValue && currentBufferValue > targetBufferValue) {
            uint256 amountToAdd = targetYieldValue - currentYieldValue;
            uint256 excessBuffer = currentBufferValue - targetBufferValue;
            
            if (excessBuffer > amountToAdd) {
                excessBuffer = amountToAdd;
            }
            
            _allocateToYield(excessBuffer);
        }
        
        // Update rebalance timestamp
        allocation.lastRebalanced = block.timestamp;
        
        emit Rebalanced(block.timestamp);
        return true;
    }
    
    /**
     * @dev Gets the current overall allocation
     * @return allocation The current allocation
     */
    function getAllocation() external view override returns (Allocation memory) {
        return allocation;
    }
    
    /**
     * @dev Gets all active yield strategies and their allocations
     * @return strategies Array of strategy allocations
     */
    function getYieldStrategies() external view override returns (StrategyAllocation[] memory strategies) {
        uint256 activeCount = 0;
        
        // Count active strategies
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                activeCount++;
            }
        }
        
        // Create result array
        strategies = new StrategyAllocation[](activeCount);
        
        // Fill result array
        uint256 index = 0;
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                strategies[index] = yieldStrategies[i];
                index++;
            }
        }
        
        return strategies;
    }
    
    /**
     * @dev Gets all active RWA tokens and their allocations
     * @return rwaTokensArray Array of RWA token allocations
     */
    function getRWATokens() external view override returns (RWAAllocation[] memory rwaTokensArray) {
        uint256 activeCount = 0;
        
        // Count active RWA tokens
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                activeCount++;
            }
        }
        
        // Create result array
        rwaTokensArray = new RWAAllocation[](activeCount);
        
        // Fill result array
        uint256 index = 0;
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                rwaTokensArray[index] = rwaTokens[i];
                index++;
            }
        }
        
        return rwaTokensArray;
    }
    
    /**
     * @dev Gets the total value of all assets under management
     * @return totalValue The total value in the base asset (e.g., USDC)
     */
    function getTotalValue() public view override returns (uint256 totalValue) {
        return getRWAValue() + getYieldValue() + getLiquidityBufferValue();
    }
    
    /**
     * @dev Gets the value of assets allocated to RWA synthetics
     * @return rwaValue The value in the base asset
     */
    function getRWAValue() public view override returns (uint256 rwaValue) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                address rwaToken = rwaTokens[i].rwaToken;
                uint256 balance = IERC20(rwaToken).balanceOf(address(this));
                
                if (balance > 0) {
                    uint256 price = IRWASyntheticToken(rwaToken).getCurrentPrice();
                    totalValue += (balance * price) / 1e18; // Assuming price is scaled by 10^18
                }
            }
        }
        
        return totalValue;
    }
    
    /**
     * @dev Gets the value of assets allocated to yield strategies
     * @return yieldValue The value in the base asset
     */
    function getYieldValue() public view override returns (uint256 yieldValue) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                address strategy = yieldStrategies[i].strategy;
                totalValue += IYieldStrategy(strategy).getTotalValue();
            }
        }
        
        return totalValue;
    }
    
    /**
     * @dev Gets the value of assets kept as liquidity buffer
     * @return bufferValue The value in the base asset
     */
    function getLiquidityBufferValue() public view override returns (uint256 bufferValue) {
        return baseAsset.balanceOf(address(this));
    }
    
    /**
     * @dev Gets the total percentage allocation for yield strategies
     * @return totalPercentage The total percentage in basis points
     */
    function getTotalYieldPercentage() public view returns (uint256 totalPercentage) {
        uint256 total = 0;
        
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                total += yieldStrategies[i].percentage;
            }
        }
        
        return total;
    }
    
    /**
     * @dev Gets the total percentage allocation for RWA tokens
     * @return totalPercentage The total percentage in basis points
     */
    function getTotalRWAPercentage() public view returns (uint256 totalPercentage) {
        uint256 total = 0;
        
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                total += rwaTokens[i].percentage;
            }
        }
        
        return total;
    }
    
    /**
     * @dev Allocates funds to RWA synthetic tokens
     * @param amount The amount to allocate
     */
    function _allocateToRWA(uint256 amount) internal {
        if (amount == 0) return;
        
        // Get active RWA tokens
        uint256 activeCount = 0;
        uint256 totalPercentage = 0;
        
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                activeCount++;
                totalPercentage += rwaTokens[i].percentage;
            }
        }
        
        if (activeCount == 0 || totalPercentage == 0) return;
        
        // Allocate to each RWA token according to its percentage
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                uint256 tokenAmount = (amount * rwaTokens[i].percentage) / totalPercentage;
                
                if (tokenAmount > 0) {
                    address rwaToken = rwaTokens[i].rwaToken;
                    
                    // Approve and mint synthetic tokens
                    baseAsset.approve(rwaToken, tokenAmount);
                    IRWASyntheticToken(rwaToken).mint(address(this), tokenAmount);
                }
            }
        }
    }
    
    /**
     * @dev Withdraws funds from RWA synthetic tokens
     * @param amount The amount to withdraw
     */
    function _withdrawFromRWA(uint256 amount) internal {
        if (amount == 0) return;
        
        uint256 totalRWAValue = getRWAValue();
        if (totalRWAValue == 0) return;
        
        // Calculate how much to withdraw from each token
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                address rwaToken = rwaTokens[i].rwaToken;
                uint256 balance = IERC20(rwaToken).balanceOf(address(this));
                
                if (balance > 0) {
                    uint256 price = IRWASyntheticToken(rwaToken).getCurrentPrice();
                    uint256 tokenValue = (balance * price) / 1e18;
                    
                    uint256 withdrawAmount = (amount * tokenValue) / totalRWAValue;
                    uint256 tokenAmount = (withdrawAmount * 1e18) / price;
                    
                    if (tokenAmount > 0) {
                        // Burn synthetic tokens
                        IRWASyntheticToken(rwaToken).burn(address(this), tokenAmount);
                    }
                }
            }
        }
    }
    
    /**
     * @dev Allocates funds to yield strategies
     * @param amount The amount to allocate
     */
    function _allocateToYield(uint256 amount) internal {
        if (amount == 0) return;
        
        // Get active yield strategies
        uint256 activeCount = 0;
        uint256 totalPercentage = 0;
        
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                activeCount++;
                totalPercentage += yieldStrategies[i].percentage;
            }
        }
        
        if (activeCount == 0 || totalPercentage == 0) return;
        
        // Allocate to each strategy according to its percentage
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                uint256 strategyAmount = (amount * yieldStrategies[i].percentage) / totalPercentage;
                
                if (strategyAmount > 0) {
                    address strategy = yieldStrategies[i].strategy;
                    
                    // Approve and deposit into strategy
                    baseAsset.approve(strategy, strategyAmount);
                    IYieldStrategy(strategy).deposit(strategyAmount);
                }
            }
        }
    }
    
    /**
     * @dev Withdraws funds from yield strategies
     * @param amount The amount to withdraw
     */
    function _withdrawFromYield(uint256 amount) internal {
        if (amount == 0) return;
        
        uint256 totalYieldValue = getYieldValue();
        if (totalYieldValue == 0) return;
        
        // Calculate how much to withdraw from each strategy
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                address strategy = yieldStrategies[i].strategy;
                uint256 strategyValue = IYieldStrategy(strategy).getTotalValue();
                
                if (strategyValue > 0) {
                    uint256 withdrawAmount = (amount * strategyValue) / totalYieldValue;
                    
                    if (withdrawAmount > 0) {
                        // Calculate shares to withdraw
                        uint256 totalShares = IERC20(strategy).balanceOf(address(this));
                        uint256 sharesToWithdraw = (totalShares * withdrawAmount) / strategyValue;
                        
                        // Withdraw from strategy
                        IYieldStrategy(strategy).withdraw(sharesToWithdraw);
                    }
                }
            }
        }
    }
}
