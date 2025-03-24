// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICapitalAllocationManager} from "../interfaces/ICapitalAllocationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockCapitalAllocationManager
 * @dev Mock implementation of the ICapitalAllocationManager interface for testing
 */
contract MockCapitalAllocationManager is ICapitalAllocationManager, Ownable {
    // Events
    event AllocationUpdated(uint256 rwaPercentage, uint256 yieldPercentage, uint256 liquidityBufferPercentage);
    event RWATokenAdded(address indexed rwaToken, uint256 percentage);
    event RWATokenRemoved(address indexed rwaToken);
    event RWATokenPercentageUpdated(address indexed rwaToken, uint256 percentage);
    event YieldStrategyAdded(address indexed strategy, uint256 percentage);
    event YieldStrategyRemoved(address indexed strategy);
    event YieldStrategyPercentageUpdated(address indexed strategy, uint256 percentage);
    struct RWAToken {
        address rwaToken;
        uint256 percentage;
        bool active;
    }
    
    // Additional functions required by the interface
    function getAllocation() external view returns (Allocation memory allocation) {
        return Allocation({
            rwaPercentage: rwaPercentage,
            yieldPercentage: yieldPercentage,
            liquidityBufferPercentage: liquidityBufferPercentage,
            lastRebalanced: block.timestamp
        });
    }
    
    function rebalance() external returns (bool success) {
        // Mock implementation
        return true;
    }
    
    function getTotalValue() external view returns (uint256 totalValue) {
        // Mock implementation
        return 0;
    }
    
    function getRWAValue() external view returns (uint256 rwaValue) {
        // Mock implementation
        return 0;
    }
    
    function getYieldValue() external view returns (uint256 yieldValue) {
        // Mock implementation
        return 0;
    }
    
    function getLiquidityBufferValue() external view returns (uint256 bufferValue) {
        // Mock implementation
        return 0;
    }
    
    struct YieldStrategy {
        address strategy;
        uint256 percentage;
        bool active;
    }
    
    IERC20 public immutable baseAsset;
    
    uint256 public rwaPercentage;
    uint256 public yieldPercentage;
    uint256 public liquidityBufferPercentage;
    
    RWAToken[] private _rwaTokens;
    YieldStrategy[] private _yieldStrategies;
    
    mapping(address => uint256) private _rwaTokenIndexes;
    mapping(address => uint256) private _yieldStrategyIndexes;
    
    /**
     * @dev Constructor that initializes the manager with the base asset
     * @param baseAsset_ The underlying asset token (typically a stablecoin)
     */
    constructor(IERC20 baseAsset_) Ownable(msg.sender) {
        baseAsset = baseAsset_;
    }
    
    /**
     * @dev Sets the overall allocation percentages
     * @param rwaPercentage_ Percentage allocated to RWA synthetics (in basis points)
     * @param yieldPercentage_ Percentage allocated to yield strategies (in basis points)
     * @param liquidityBufferPercentage_ Percentage kept as liquidity buffer (in basis points)
     * @return success True if the allocation was set successfully
     */
    function setAllocation(
        uint256 rwaPercentage_,
        uint256 yieldPercentage_,
        uint256 liquidityBufferPercentage_
    ) external onlyOwner returns (bool success) {
        require(rwaPercentage_ + yieldPercentage_ + liquidityBufferPercentage_ == 10000, "Percentages must sum to 10000");
        
        rwaPercentage = rwaPercentage_;
        yieldPercentage = yieldPercentage_;
        liquidityBufferPercentage = liquidityBufferPercentage_;
        
        emit AllocationUpdated(rwaPercentage_, yieldPercentage_, liquidityBufferPercentage_);
        return true;
    }
    
    /**
     * @dev Adds a new RWA synthetic token to the allocation
     * @param rwaToken The RWA synthetic token address
     * @param percentage The allocation percentage within the RWA category (in basis points)
     * @return success True if the token was added successfully
     */
    function addRWAToken(address rwaToken, uint256 percentage) external onlyOwner returns (bool success) {
        require(rwaToken != address(0), "Invalid RWA token address");
        require(percentage <= 10000, "Percentage cannot exceed 10000");
        
        // Check if token already exists
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken) {
                if (!_rwaTokens[i].active) {
                    // Reactivate token
                    _rwaTokens[i].active = true;
                    _rwaTokens[i].percentage = percentage;
                    _rebalanceRWAPercentages();
                    emit RWATokenAdded(rwaToken, percentage);
                    return true;
                } else {
                    revert("RWA token already exists");
                }
            }
        }
        
        // Add new token
        _rwaTokens.push(RWAToken({
            rwaToken: rwaToken,
            percentage: percentage,
            active: true
        }));
        
        _rwaTokenIndexes[rwaToken] = _rwaTokens.length - 1;
        
        _rebalanceRWAPercentages();
        
        emit RWATokenAdded(rwaToken, percentage);
        return true;
    }
    
    /**
     * @dev Removes an RWA synthetic token from the allocation
     * @param rwaToken The RWA synthetic token address to remove
     * @return success True if the token was removed successfully
     */
    function removeRWAToken(address rwaToken) external onlyOwner returns (bool success) {
        require(rwaToken != address(0), "Invalid RWA token address");
        
        bool found = false;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken && _rwaTokens[i].active) {
                _rwaTokens[i].active = false;
                _rwaTokens[i].percentage = 0;
                found = true;
                break;
            }
        }
        
        require(found, "RWA token not found or already inactive");
        
        _rebalanceRWAPercentages();
        
        emit RWATokenRemoved(rwaToken);
        return true;
    }
    
    /**
     * @dev Updates the allocation percentage for an RWA synthetic token
     * @param rwaToken The RWA synthetic token address
     * @param percentage The new allocation percentage (in basis points)
     * @return success True if the allocation was updated successfully
     */
    function updateRWATokenPercentage(address rwaToken, uint256 percentage) external onlyOwner returns (bool success) {
        require(rwaToken != address(0), "Invalid RWA token address");
        require(percentage <= 10000, "Percentage cannot exceed 10000");
        
        bool found = false;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken && _rwaTokens[i].active) {
                _rwaTokens[i].percentage = percentage;
                found = true;
                break;
            }
        }
        
        require(found, "RWA token not found or inactive");
        
        _rebalanceRWAPercentages();
        
        emit RWATokenPercentageUpdated(rwaToken, percentage);
        return true;
    }
    
    /**
     * @dev Updates the allocation percentage for an RWA synthetic token
     * @param rwaToken The RWA synthetic token address
     * @param percentage The new allocation percentage (in basis points)
     * @return success True if the allocation was updated successfully
     */
    function updateRWATokenPercentage(address rwaToken, uint256 percentage) external onlyOwner returns (bool success) {
        require(rwaToken != address(0), "Invalid RWA token address");
        require(percentage <= 10000, "Percentage cannot exceed 10000");
        
        bool found = false;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken && _rwaTokens[i].active) {
                _rwaTokens[i].percentage = percentage;
                found = true;
                break;
            }
        }
        
        require(found, "RWA token not found or inactive");
        
        _rebalanceRWAPercentages();
        
        emit RWATokenPercentageUpdated(rwaToken, percentage);
        return true;
    }

    function updateRWAToken(address rwaToken, uint256 percentage) external returns (bool success) {
        return updateRWATokenPercentage(rwaToken, percentage);
    }
    
    /**
     * @dev Adds a new yield strategy to the allocation
     * @param strategy The yield strategy address
     * @param percentage The allocation percentage within the yield category (in basis points)
     * @return success True if the strategy was added successfully
     */
    function addYieldStrategy(address strategy, uint256 percentage) external onlyOwner returns (bool success) {
        require(strategy != address(0), "Invalid strategy address");
        require(percentage <= 10000, "Percentage cannot exceed 10000");
        
        // Check if strategy already exists
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy) {
                if (!_yieldStrategies[i].active) {
                    // Reactivate strategy
                    _yieldStrategies[i].active = true;
                    _yieldStrategies[i].percentage = percentage;
                    _rebalanceYieldPercentages();
                    emit YieldStrategyAdded(strategy, percentage);
                    return true;
                } else {
                    revert("Yield strategy already exists");
                }
            }
        }
        
        // Add new strategy
        _yieldStrategies.push(YieldStrategy({
            strategy: strategy,
            percentage: percentage,
            active: true
        }));
        
        _yieldStrategyIndexes[strategy] = _yieldStrategies.length - 1;
        
        _rebalanceYieldPercentages();
        
        emit YieldStrategyAdded(strategy, percentage);
        return true;
    }
    
    /**
     * @dev Removes a yield strategy from the allocation
     * @param strategy The yield strategy address to remove
     * @return success True if the strategy was removed successfully
     */
    function removeYieldStrategy(address strategy) external onlyOwner returns (bool success) {
        require(strategy != address(0), "Invalid strategy address");
        
        bool found = false;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy && _yieldStrategies[i].active) {
                _yieldStrategies[i].active = false;
                _yieldStrategies[i].percentage = 0;
                found = true;
                break;
            }
        }
        
        require(found, "Yield strategy not found or already inactive");
        
        _rebalanceYieldPercentages();
        
        emit YieldStrategyRemoved(strategy);
        return true;
    }
    
    /**
     * @dev Updates the allocation percentage for a yield strategy
     * @param strategy The yield strategy address
     * @param percentage The new allocation percentage (in basis points)
     * @return success True if the allocation was updated successfully
     */
    function updateYieldStrategyPercentage(address strategy, uint256 percentage) external onlyOwner returns (bool success) {
        require(strategy != address(0), "Invalid strategy address");
        require(percentage <= 10000, "Percentage cannot exceed 10000");
        
        bool found = false;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy && _yieldStrategies[i].active) {
                _yieldStrategies[i].percentage = percentage;
                found = true;
                break;
            }
        }
        
        require(found, "Yield strategy not found or inactive");
        
        _rebalanceYieldPercentages();
        
        emit YieldStrategyPercentageUpdated(strategy, percentage);
        return true;
    }
    
    /**
     * @dev Updates the allocation percentage for a yield strategy
     * @param strategy The yield strategy address
     * @param percentage The new allocation percentage (in basis points)
     * @return success True if the allocation was updated successfully
     */
    function updateYieldStrategyPercentage(address strategy, uint256 percentage) external onlyOwner returns (bool success) {
        require(strategy != address(0), "Invalid strategy address");
        require(percentage <= 10000, "Percentage cannot exceed 10000");
        
        bool found = false;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy && _yieldStrategies[i].active) {
                _yieldStrategies[i].percentage = percentage;
                found = true;
                break;
            }
        }
        
        require(found, "Yield strategy not found or inactive");
        
        _rebalanceYieldPercentages();
        
        emit YieldStrategyPercentageUpdated(strategy, percentage);
        return true;
    }

    function updateYieldStrategy(address strategy, uint256 percentage) external returns (bool success) {
        return updateYieldStrategyPercentage(strategy, percentage);
    }
    
    /**
     * @dev Gets all RWA synthetic tokens and their allocation percentages
     * @return tokens Array of RWA token structs
     */
    function getRWATokens() external view returns (RWAAllocation[] memory tokens) {
        RWAAllocation[] memory result = new RWAAllocation[](_rwaTokens.length);
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            result[i] = RWAAllocation({
                rwaToken: _rwaTokens[i].rwaToken,
                percentage: _rwaTokens[i].percentage,
                active: _rwaTokens[i].active
            });
        }
        return result;

    }
    
    /**
     * @dev Gets all yield strategies and their allocation percentages
     * @return strategies Array of yield strategy structs
     */
    function getYieldStrategies() external view returns (StrategyAllocation[] memory strategies) {
        StrategyAllocation[] memory result = new StrategyAllocation[](_yieldStrategies.length);
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            result[i] = StrategyAllocation({
                strategy: _yieldStrategies[i].strategy,
                percentage: _yieldStrategies[i].percentage,
                active: _yieldStrategies[i].active
            });
        }
        return result;

    }
    
    /**
     * @dev Gets the allocation percentage for a specific RWA token
     * @param rwaToken The RWA token address
     * @return percentage The allocation percentage (in basis points)
     */


    function getRWATokenPercentage(address rwaToken) external view returns (uint256 percentage) {
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken && _rwaTokens[i].active) {
                return _rwaTokens[i].percentage;
            }
        }
        return 0;
    }
    
    /**
     * @dev Gets the allocation percentage for a specific yield strategy
     * @param strategy The yield strategy address
     * @return percentage The allocation percentage (in basis points)
     */


    function getYieldStrategyPercentage(address strategy) external view returns (uint256 percentage) {
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy && _yieldStrategies[i].active) {
                return _yieldStrategies[i].percentage;
            }
        }
        return 0;
    }
    
    /**
     * @dev Rebalances the RWA token percentages to ensure they sum to 10000 (100%)
     */
    function _rebalanceRWAPercentages() private {
        uint256 totalPercentage = 0;
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].active) {
                totalPercentage += _rwaTokens[i].percentage;
                activeCount++;
            }
        }
        
        if (activeCount == 0 || totalPercentage == 0) {
            return;
        }
        
        if (totalPercentage != 10000) {
            // Normalize percentages to sum to 10000
            for (uint256 i = 0; i < _rwaTokens.length; i++) {
                if (_rwaTokens[i].active) {
                    _rwaTokens[i].percentage = (_rwaTokens[i].percentage * 10000) / totalPercentage;
                }
            }
        }
    }
    
    /**
     * @dev Rebalances the yield strategy percentages to ensure they sum to 10000 (100%)
     */
    function _rebalanceYieldPercentages() private {
        uint256 totalPercentage = 0;
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].active) {
                totalPercentage += _yieldStrategies[i].percentage;
                activeCount++;
            }
        }
        
        if (activeCount == 0 || totalPercentage == 0) {
            return;
        }
        
        if (totalPercentage != 10000) {
            // Normalize percentages to sum to 10000
            for (uint256 i = 0; i < _yieldStrategies.length; i++) {
                if (_yieldStrategies[i].active) {
                    _yieldStrategies[i].percentage = (_yieldStrategies[i].percentage * 10000) / totalPercentage;
                }
            }
        }
    }
}
