// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICapitalAllocationManager} from "../../src/interfaces/ICapitalAllocationManager.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {IRWASyntheticToken} from "../../src/interfaces/IRWASyntheticToken.sol";

/**
 * @title TestableCapitalAllocationManager
 * @dev A simplified version of CapitalAllocationManager without owner restrictions for testing reentrancy
 * This contract should NEVER be used in production, only for testing reentrancy protection
 */
contract TestableCapitalAllocationManager is ICapitalAllocationManager, Ownable, ReentrancyGuard {
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
    event YieldStrategyAdded(address indexed strategy, uint256 percentage);
    event YieldStrategyUpdated(address indexed strategy, uint256 percentage);
    event YieldStrategyRemoved(address indexed strategy);
    event RWATokenAdded(address indexed rwaToken, uint256 percentage);
    event RWATokenUpdated(address indexed rwaToken, uint256 percentage);
    event RWATokenRemoved(address indexed rwaToken);
    event AllocationSet(uint256 rwaPercentage, uint256 yieldPercentage, uint256 liquidityBufferPercentage);
    event Rebalanced(uint256 timestamp);
    
    constructor(address _baseAsset) Ownable(msg.sender) {
        require(_baseAsset != address(0), "Base asset cannot be zero address");
        baseAsset = IERC20(_baseAsset);
        
        // Default allocation: 0% RWA, 0% yield, 100% buffer
        allocation = Allocation({
            rwaPercentage: 0,
            yieldPercentage: 0,
            liquidityBufferPercentage: BASIS_POINTS,
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
    ) external override returns (bool success) {
        require(rwaPercentage + yieldPercentage + liquidityBufferPercentage == BASIS_POINTS, "Percentages must sum to 100%");
        
        allocation.rwaPercentage = rwaPercentage;
        allocation.yieldPercentage = yieldPercentage;
        allocation.liquidityBufferPercentage = liquidityBufferPercentage;
        
        emit AllocationSet(rwaPercentage, yieldPercentage, liquidityBufferPercentage);
        return true;
    }
    
    /**
     * @dev Adds a yield strategy with an allocation percentage
     * @param strategy Address of the yield strategy
     * @param percentage Percentage allocation within yield portion (in basis points)
     * @return success Whether the strategy was added successfully
     */
    function addYieldStrategy(address strategy, uint256 percentage) external override returns (bool success) {
        require(strategy != address(0), "Strategy cannot be zero address");
        require(percentage > 0, "Percentage must be positive");
        require(!isActiveYieldStrategy[strategy], "Strategy already exists");
        
        // Validate strategy interface
        IYieldStrategy yieldStrategy = IYieldStrategy(strategy);
        require(yieldStrategy.getStrategyInfo().asset == address(baseAsset), "Strategy asset mismatch");
        
        // Add to strategies array
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
     * @dev Adds an RWA synthetic token with an allocation percentage
     * @param rwaToken Address of the RWA synthetic token
     * @param percentage Percentage allocation within RWA portion (in basis points)
     * @return success Whether the RWA token was added successfully
     */
    function addRWAToken(address rwaToken, uint256 percentage) external override returns (bool success) {
        require(rwaToken != address(0), "RWA token cannot be zero address");
        require(percentage > 0, "Percentage must be positive");
        require(!isActiveRWAToken[rwaToken], "RWA token already exists");
        
        // For testing purposes, we'll skip the asset validation
        // In a real implementation, we would validate that the RWA token uses the same base asset
        // but the interface doesn't expose a direct way to check this
        
        // Add to RWA tokens array
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
     * @dev Updates a yield strategy's allocation percentage
     * @param strategy Address of the yield strategy
     * @param percentage New percentage allocation (in basis points)
     * @return success Whether the strategy was updated successfully
     */
    function updateYieldStrategy(address strategy, uint256 percentage) external override returns (bool success) {
        require(isActiveYieldStrategy[strategy], "Strategy not active");
        require(percentage > 0, "Percentage must be positive");
        
        uint256 index = yieldStrategyIndexes[strategy];
        // No need to store the old percentage for testing purposes
        yieldStrategies[index].percentage = percentage;
        
        emit YieldStrategyUpdated(strategy, percentage);
        return true;
    }
    
    /**
     * @dev Updates an RWA synthetic token's allocation percentage
     * @param rwaToken Address of the RWA synthetic token
     * @param percentage New percentage allocation (in basis points)
     * @return success Whether the RWA token was updated successfully
     */
    function updateRWAToken(address rwaToken, uint256 percentage) external override returns (bool success) {
        require(isActiveRWAToken[rwaToken], "RWA token not active");
        require(percentage > 0, "Percentage must be positive");
        
        uint256 index = rwaTokenIndexes[rwaToken];
        // No need to store the old percentage for testing purposes
        rwaTokens[index].percentage = percentage;
        
        emit RWATokenUpdated(rwaToken, percentage);
        return true;
    }
    
    /**
     * @dev Removes a yield strategy
     * @param strategy Address of the yield strategy to remove
     * @return success Whether the strategy was removed successfully
     */
    function removeYieldStrategy(address strategy) external override returns (bool success) {
        require(isActiveYieldStrategy[strategy], "Strategy not active");
        
        uint256 index = yieldStrategyIndexes[strategy];
        yieldStrategies[index].active = false;
        isActiveYieldStrategy[strategy] = false;
        
        emit YieldStrategyRemoved(strategy);
        return true;
    }
    
    /**
     * @dev Removes an RWA synthetic token
     * @param rwaToken Address of the RWA token to remove
     * @return success Whether the RWA token was removed successfully
     */
    function removeRWAToken(address rwaToken) external override returns (bool success) {
        require(isActiveRWAToken[rwaToken], "RWA token not active");
        
        uint256 index = rwaTokenIndexes[rwaToken];
        rwaTokens[index].active = false;
        isActiveRWAToken[rwaToken] = false;
        
        emit RWATokenRemoved(rwaToken);
        return true;
    }
    
    /**
     * @dev Rebalances the capital allocation according to the set percentages
     * This version doesn't have the onlyOwner modifier for testing reentrancy
     * @return success Whether the rebalance was successful
     */
    function rebalance() external override nonReentrant returns (bool success) {
        // Get total value of assets under management
        uint256 totalValue = getTotalValue();
        require(totalValue > 0, "No assets to rebalance");
        
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
     * @return totalValue The total value in the base asset
     */
    function getTotalValue() public view override returns (uint256 totalValue) {
        return getRWAValue() + getYieldValue() + getLiquidityBufferValue();
    }
    
    /**
     * @dev Gets the value of assets allocated to yield strategies
     * @return yieldValue The value in the base asset
     */
    function getYieldValue() public view override returns (uint256 yieldValue) {
        uint256 totalYieldValue = 0;
        
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                IYieldStrategy strategy = IYieldStrategy(yieldStrategies[i].strategy);
                totalYieldValue += strategy.getTotalValue();
            }
        }
        
        return totalYieldValue;
    }
    
    /**
     * @dev Gets the value of assets allocated to RWA synthetics
     * @return rwaValue The value in the base asset
     */
    function getRWAValue() public view override returns (uint256 rwaValue) {
        uint256 totalRWAValue = 0;
        
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                // For testing purposes, we'll use the token's total supply as a proxy for value
                // In a real implementation, we would use the token's getTotalValue method
                IRWASyntheticToken token = IRWASyntheticToken(rwaTokens[i].rwaToken);
                totalRWAValue += token.totalSupply();
            }
        }
        
        return totalRWAValue;
    }
    
    /**
     * @dev Gets the value of assets in the liquidity buffer
     * @return bufferValue The value in the base asset
     */
    function getLiquidityBufferValue() public view override returns (uint256 bufferValue) {
        return baseAsset.balanceOf(address(this));
    }
    
    /**
     * @dev Internal function to allocate funds to RWA tokens
     * @param amount Amount to allocate
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
                    IRWASyntheticToken token = IRWASyntheticToken(rwaTokens[i].rwaToken);
                    baseAsset.approve(rwaTokens[i].rwaToken, tokenAmount);
                    token.mint(address(this), tokenAmount);
                }
            }
        }
    }
    
    /**
     * @dev Internal function to allocate funds to yield strategies
     * @param amount Amount to allocate
     */
    function _allocateToYield(uint256 amount) internal {
        if (amount == 0) return;
        
        // Get active strategies
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
                    IYieldStrategy strategy = IYieldStrategy(yieldStrategies[i].strategy);
                    baseAsset.approve(yieldStrategies[i].strategy, strategyAmount);
                    strategy.deposit(strategyAmount);
                }
            }
        }
    }
    
    /**
     * @dev Internal function to withdraw funds from RWA tokens
     * @param amount Amount to withdraw
     */
    function _withdrawFromRWA(uint256 amount) internal {
        if (amount == 0) return;
        
        uint256 totalRWAValue = getRWAValue();
        if (totalRWAValue == 0) return;
        
        // Withdraw proportionally from each RWA token
        for (uint256 i = 0; i < rwaTokens.length; i++) {
            if (rwaTokens[i].active) {
                IRWASyntheticToken token = IRWASyntheticToken(rwaTokens[i].rwaToken);
                // For testing purposes, we'll use the token's total supply as a proxy for value
                uint256 tokenValue = token.totalSupply();
                
                if (tokenValue > 0) {
                    uint256 withdrawAmount = (amount * tokenValue) / totalRWAValue;
                    if (withdrawAmount > 0) {
                        // For testing purposes, we'll burn a proportional amount of tokens
                        // In a real implementation, we would use the token's getTokensForValue method
                        uint256 tokensToBurn = (withdrawAmount * token.balanceOf(address(this))) / tokenValue;
                        if (tokensToBurn > 0) {
                            token.burn(address(this), tokensToBurn);
                        }
                    }
                }
            }
        }
    }
    
    /**
     * @dev Internal function to withdraw funds from yield strategies
     * @param amount Amount to withdraw
     */
    function _withdrawFromYield(uint256 amount) internal {
        if (amount == 0) return;
        
        uint256 totalYieldValue = getYieldValue();
        if (totalYieldValue == 0) return;
        
        // Withdraw proportionally from each strategy
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].active) {
                IYieldStrategy strategy = IYieldStrategy(yieldStrategies[i].strategy);
                uint256 strategyValue = strategy.getTotalValue();
                
                if (strategyValue > 0) {
                    uint256 withdrawAmount = (amount * strategyValue) / totalYieldValue;
                    if (withdrawAmount > 0) {
                        // Calculate how many shares to withdraw
                        // Calculate shares based on the value using the available interface methods
                        // For simplicity in testing, we'll use a direct proportion calculation
                        uint256 totalValue = strategy.getTotalValue();
                        uint256 sharesToWithdraw = 0;
                        if (totalValue > 0) {
                            // Calculate shares proportionally to the withdraw amount
                            sharesToWithdraw = (withdrawAmount * 1e18) / totalValue;
                        }
                        if (sharesToWithdraw > 0) {
                            strategy.withdraw(sharesToWithdraw);
                        }
                    }
                }
            }
        }
    }
}
