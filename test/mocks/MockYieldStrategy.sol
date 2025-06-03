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
    
    function deposit(uint256 amount) external override returns (uint256) {
        if (amount == 0) return 0;
        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
        return amount; // 1:1 share ratio for simplicity
    }
    
    function withdraw(uint256 shares) external override returns (uint256) {
        if (shares == 0) return 0;
        uint256 amount = shares; // 1:1 share ratio
        require(amount <= totalDeposited, "Insufficient balance");
        totalDeposited -= amount;
        asset.safeTransfer(msg.sender, amount);
        return amount;
    }
    
    function getValueOfShares(uint256 shares) external pure override returns (uint256) {
        return shares; // 1:1 share ratio
    }
    
    function getTotalValue() external view override returns (uint256) {
        return totalDeposited;
    }
    
    function getCurrentAPY() external pure override returns (uint256) {
        return 500; // Fixed 5% APY for testing
    }
    
    function getStrategyInfo() external view override returns (StrategyInfo memory) {
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
    
    function harvestYield() external override returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastHarvest;
        uint256 yieldAmount = (totalDeposited * yieldRate * timeElapsed) / (365 days * 10000);
        
        if (yieldAmount > 0) {
            asset.safeTransfer(msg.sender, yieldAmount);
        }
        
        lastHarvest = block.timestamp;
        return yieldAmount;
    }
    
    function setYieldRate(uint256 newRate) external onlyOwner {
        yieldRate = newRate;
    }
    
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }
}
