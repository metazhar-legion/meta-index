// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CapitalAllocationManager} from "../../src/CapitalAllocationManager.sol";

/**
 * @title TestableCapitalAllocationManager
 * @dev A version of CapitalAllocationManager that removes owner restrictions for testing purposes
 * This contract should NEVER be used in production, only for testing reentrancy protection
 */
contract TestableCapitalAllocationManager is CapitalAllocationManager {
    constructor(address _baseAsset) CapitalAllocationManager(_baseAsset) {}

    /**
     * @dev Override rebalance to remove onlyOwner modifier for testing reentrancy
     */
    function rebalance() public override nonReentrant returns (bool) {
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
}
