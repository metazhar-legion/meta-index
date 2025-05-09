// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICapitalAllocationManager} from "../interfaces/ICapitalAllocationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

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

    // Internal structures for tracking tokens and strategies
    struct RWAToken {
        address rwaToken;
        uint256 percentage;
        bool active;
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
    function setAllocation(uint256 rwaPercentage_, uint256 yieldPercentage_, uint256 liquidityBufferPercentage_)
        external
        onlyOwner
        returns (bool success)
    {
        if (rwaPercentage_ + yieldPercentage_ + liquidityBufferPercentage_ != 10000) {
            revert CommonErrors.TotalExceeds100Percent();
        }

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
        if (rwaToken == address(0)) revert CommonErrors.ZeroAddress();
        if (percentage > 10000) revert CommonErrors.PercentageTooHigh();

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
                    revert CommonErrors.TokenAlreadyExists();
                }
            }
        }

        // Add new token
        _rwaTokens.push(RWAToken({rwaToken: rwaToken, percentage: percentage, active: true}));

        _rwaTokenIndexes[rwaToken] = _rwaTokens.length - 1;

        _rebalanceRWAPercentages();

        emit RWATokenAdded(rwaToken, percentage);
        return true;
    }

    /**
     * @dev Updates an RWA token's allocation percentage
     * @param rwaToken The RWA token address
     * @param percentage The new allocation percentage (in basis points)
     * @return success True if the update was successful
     */
    function updateRWAToken(address rwaToken, uint256 percentage) external onlyOwner returns (bool success) {
        if (rwaToken == address(0)) revert CommonErrors.ZeroAddress();
        if (percentage > 10000) revert CommonErrors.PercentageTooHigh();

        bool found = false;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken && _rwaTokens[i].active) {
                _rwaTokens[i].percentage = percentage;
                found = true;
                break;
            }
        }

        if (!found) revert CommonErrors.TokenNotFound();

        _rebalanceRWAPercentages();

        emit RWATokenPercentageUpdated(rwaToken, percentage);
        return true;
    }

    /**
     * @dev Removes an RWA synthetic token from the allocation
     * @param rwaToken The RWA synthetic token address to remove
     * @return success True if the token was removed successfully
     */
    function removeRWAToken(address rwaToken) external onlyOwner returns (bool success) {
        if (rwaToken == address(0)) revert CommonErrors.ZeroAddress();

        bool found = false;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].rwaToken == rwaToken && _rwaTokens[i].active) {
                _rwaTokens[i].active = false;
                _rwaTokens[i].percentage = 0;
                found = true;
                break;
            }
        }

        if (!found) revert CommonErrors.TokenNotFound();

        _rebalanceRWAPercentages();

        emit RWATokenRemoved(rwaToken);
        return true;
    }

    /**
     * @dev Adds a new yield strategy to the allocation
     * @param strategy The yield strategy address
     * @param percentage The allocation percentage within the yield category (in basis points)
     * @return success True if the strategy was added successfully
     */
    function addYieldStrategy(address strategy, uint256 percentage) external onlyOwner returns (bool success) {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        if (percentage > 10000) revert CommonErrors.PercentageTooHigh();

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
                    revert CommonErrors.TokenAlreadyExists();
                }
            }
        }

        // Add new strategy
        _yieldStrategies.push(YieldStrategy({strategy: strategy, percentage: percentage, active: true}));

        _yieldStrategyIndexes[strategy] = _yieldStrategies.length - 1;

        _rebalanceYieldPercentages();

        emit YieldStrategyAdded(strategy, percentage);
        return true;
    }

    /**
     * @dev Updates a yield strategy's allocation percentage
     * @param strategy The yield strategy address
     * @param percentage The new allocation percentage (in basis points)
     * @return success True if the update was successful
     */
    function updateYieldStrategy(address strategy, uint256 percentage) external onlyOwner returns (bool success) {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        if (percentage > 10000) revert CommonErrors.PercentageTooHigh();

        bool found = false;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy && _yieldStrategies[i].active) {
                _yieldStrategies[i].percentage = percentage;
                found = true;
                break;
            }
        }

        if (!found) revert CommonErrors.TokenNotFound();

        _rebalanceYieldPercentages();

        emit YieldStrategyPercentageUpdated(strategy, percentage);
        return true;
    }

    /**
     * @dev Removes a yield strategy from the allocation
     * @param strategy The yield strategy address to remove
     * @return success True if the strategy was removed successfully
     */
    function removeYieldStrategy(address strategy) external onlyOwner returns (bool success) {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();

        bool found = false;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].strategy == strategy && _yieldStrategies[i].active) {
                _yieldStrategies[i].active = false;
                _yieldStrategies[i].percentage = 0;
                found = true;
                break;
            }
        }

        if (!found) revert CommonErrors.TokenNotFound();

        _rebalanceYieldPercentages();

        emit YieldStrategyRemoved(strategy);
        return true;
    }

    /**
     * @dev Gets all RWA synthetic tokens and their allocation percentages
     * @return tokens Array of RWA token allocations
     */
    function getRWATokens() external view returns (RWAAllocation[] memory tokens) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].active) {
                activeCount++;
            }
        }

        RWAAllocation[] memory activeTokens = new RWAAllocation[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < _rwaTokens.length; i++) {
            if (_rwaTokens[i].active) {
                activeTokens[index] = RWAAllocation({
                    rwaToken: _rwaTokens[i].rwaToken,
                    percentage: _rwaTokens[i].percentage,
                    active: true
                });
                index++;
            }
        }

        return activeTokens;
    }

    /**
     * @dev Gets all yield strategies and their allocation percentages
     * @return strategies Array of yield strategy allocations
     */
    function getYieldStrategies() external view returns (StrategyAllocation[] memory strategies) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].active) {
                activeCount++;
            }
        }

        StrategyAllocation[] memory activeStrategies = new StrategyAllocation[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < _yieldStrategies.length; i++) {
            if (_yieldStrategies[i].active) {
                activeStrategies[index] = StrategyAllocation({
                    strategy: _yieldStrategies[i].strategy,
                    percentage: _yieldStrategies[i].percentage,
                    active: true
                });
                index++;
            }
        }

        return activeStrategies;
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
     * @dev Gets the current overall allocation
     * @return allocation The current allocation
     */
    function getAllocation() external view returns (Allocation memory allocation) {
        return Allocation({
            rwaPercentage: rwaPercentage,
            yieldPercentage: yieldPercentage,
            liquidityBufferPercentage: liquidityBufferPercentage,
            lastRebalanced: block.timestamp
        });
    }

    /**
     * @dev Rebalances the capital allocation according to the set percentages
     * @return success Whether the rebalance was successful
     */
    function rebalance() external pure returns (bool success) {
        // Mock implementation - just return true
        return true;
    }

    /**
     * @dev Gets the total value of all assets under management
     * @return totalValue The total value in the base asset (e.g., USDC)
     */
    function getTotalValue() external pure returns (uint256 totalValue) {
        // Mock implementation - return 0
        return 0;
    }

    /**
     * @dev Gets the value of assets allocated to RWA synthetics
     * @return rwaValue The value in the base asset
     */
    function getRWAValue() external pure returns (uint256 rwaValue) {
        // Mock implementation - return 0
        return 0;
    }

    /**
     * @dev Gets the value of assets allocated to yield strategies
     * @return yieldValue The value in the base asset
     */
    function getYieldValue() external pure returns (uint256 yieldValue) {
        // Mock implementation - return 0
        return 0;
    }

    /**
     * @dev Gets the value of assets kept as liquidity buffer
     * @return bufferValue The value in the base asset
     */
    function getLiquidityBufferValue() external pure returns (uint256 bufferValue) {
        // Mock implementation - return 0
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
