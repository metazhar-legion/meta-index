// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";

/**
 * @title MockYieldStrategy
 * @dev Mock implementation of a yield strategy for testing
 */
contract MockYieldStrategy is IYieldStrategy, Ownable {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable asset;
    uint256 public yieldRate; // Annual yield rate in basis points (e.g., 500 = 5%)
    uint256 public lastHarvest;
    uint256 public totalDeposited;
    string public name;
    uint256 public risk;
    bool public active;
    
    // Events
    event Deposited(address indexed caller, uint256 assets, uint256 shares);
    event Withdrawn(address indexed caller, uint256 shares, uint256 assets);
    event YieldHarvested(uint256 yieldAmount);
    event YieldRateUpdated(uint256 newRate);
    
    constructor(
        string memory _name,
        address _asset, 
        uint256 _yieldRate,
        uint256 _risk
    ) Ownable(msg.sender) {
        name = _name;
        asset = IERC20(_asset);
        yieldRate = _yieldRate;
        risk = _risk;
        active = true;
        lastHarvest = block.timestamp;
    }
    
    /**
     * @dev Deposits assets into the yield strategy
     * @param amount Amount of assets to deposit
     * @return shares The number of shares received (1:1 for simplicity)
     */
    function deposit(uint256 amount) external override returns (uint256 shares) {
        if (amount == 0) return 0;
        
        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update total deposited (1:1 share ratio for simplicity)
        totalDeposited += amount;
        shares = amount;
        
        emit Deposited(msg.sender, amount, shares);
        
        return shares;
    }
    
    /**
     * @dev Withdraws assets from the yield strategy
     * @param shares The number of shares to withdraw (1:1 for simplicity)
     * @return amount The amount withdrawn
     */
    function withdraw(uint256 shares) external override returns (uint256 amount) {
        if (shares == 0) return 0;
        
        // Ensure we have enough to withdraw (1:1 share ratio for simplicity)
        amount = shares;
        require(amount <= totalDeposited, "Insufficient balance");
        
        // Update total deposited
        totalDeposited -= amount;
        
        // Transfer assets to caller
        asset.safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, shares, amount);
        
        return amount;
    }
    
    /**
     * @dev Gets the value of shares (1:1 for simplicity)
     * @param shares The number of shares
     * @return value The current value of the shares
     */
    function getValueOfShares(uint256 shares) external view override returns (uint256 value) {
        // 1:1 share ratio for simplicity
        return shares;
    }
    
    /**
     * @dev Gets the total value of all assets in the strategy
     * @return value The total value
     */
    function getTotalValue() external view override returns (uint256 value) {
        return totalDeposited;
    }
    
    /**
     * @dev Gets the current APY of the strategy
     * @return apy The current APY in basis points
     */
    function getCurrentAPY() external pure override returns (uint256 apy) {
        return 500; // Fixed 5% APY for testing
    }
    
    /**
     * @dev Gets detailed information about the strategy
     * @return info The strategy information
     */
    function getStrategyInfo() external view override returns (StrategyInfo memory info) {
        return StrategyInfo({
            name: name,
            asset: address(asset),
            totalDeposited: totalDeposited,
            currentValue: totalDeposited,
            apy: yieldRate,
            lastUpdated: lastHarvest,
            active: active,
            risk: risk
        });
    }
    
    /**
     * @dev Harvests yield from the strategy
     * @return yieldAmount The amount harvested
     */
    function harvestYield() external override returns (uint256 yieldAmount) {
        uint256 timeElapsed = block.timestamp - lastHarvest;
        
        // Calculate yield based on time elapsed and yield rate
        // yield = principal * rate * time / (365 days * 10000)
        yieldAmount = (totalDeposited * yieldRate * timeElapsed) / (365 days * 10000);
        
        // Mint yield (in a real strategy, this would come from external protocols)
        if (yieldAmount > 0) {
            // For testing, we'll just transfer the yield to the caller
            asset.safeTransfer(msg.sender, yieldAmount);
        }
        
        lastHarvest = block.timestamp;
        
        emit YieldHarvested(yieldAmount);
        
        return yieldAmount;
    }
    
    /**
     * @dev Sets the yield rate
     * @param newRate New yield rate in basis points
     */
    function setYieldRate(uint256 newRate) external onlyOwner {
        yieldRate = newRate;
        emit YieldRateUpdated(newRate);
    }
    
    /**
     * @dev Sets the active status of the strategy
     * @param _active New active status
     */
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }
    
    /**
     * @dev Simulates yield for testing
     * @param amount Amount of yield to simulate
     */
    function simulateYield(uint256 amount) external {
        // This function is only for testing
        // It simulates yield by artificially increasing the balance
        // For the mock, we don't need to do anything special
        // When harvestYield is called, it will return the simulated yield
    }
}
