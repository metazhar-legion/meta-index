// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFeeManager} from "../interfaces/IFeeManager.sol";

/**
 * @title MockFeeManager
 * @dev Mock implementation of the FeeManager for testing
 */
contract MockFeeManager is IFeeManager, Ownable {
    // Fee structure
    uint256 private _managementFeePercentage = 100; // 1% annual (in basis points)
    uint256 private _performanceFeePercentage = 1000; // 10% (in basis points)
    uint256 public constant BASIS_POINTS = 10000;
    
    // High watermark for performance fees, mapped by vault address
    mapping(address => uint256) private _highWaterMarks;
    
    // Last fee collection timestamp, mapped by vault address
    mapping(address => uint256) private _lastFeeCollectionTimestamps;
    
    // For testing: control the return values
    uint256 public mockManagementFee = 0;
    uint256 public mockPerformanceFee = 0;
    bool public useFixedFees = false;
    
    // Fee recipient
    address public feeRecipient;

    constructor() Ownable(msg.sender) {
        feeRecipient = msg.sender;
    }
    
    /**
     * @dev Updates the management fee percentage
     * @param newFee The new fee in basis points
     */
    function setManagementFeePercentage(uint256 newFee) external override onlyOwner {
        _managementFeePercentage = newFee;
    }
    
    /**
     * @dev Updates the performance fee percentage
     * @param newFee The new fee in basis points
     */
    function setPerformanceFeePercentage(uint256 newFee) external override onlyOwner {
        _performanceFeePercentage = newFee;
    }
    
    /**
     * @dev Calculates management fee
     * @param vault The address of the vault
     * @param totalAssetsValue The total value of assets in the vault
     * @param currentTimestamp The current timestamp
     * @return managementFee The calculated management fee
     */
    function calculateManagementFee(
        address vault,
        uint256 totalAssetsValue,
        uint256 currentTimestamp
    ) external view override returns (uint256) {
        if (useFixedFees) {
            return mockManagementFee;
        }
        
        uint256 lastTimestamp = _lastFeeCollectionTimestamps[vault];
        
        // For view function, we can't modify state, so we just calculate the fee
        if (lastTimestamp == 0) {
            return 0;
        }
        
        uint256 timeSinceLastCollection = currentTimestamp - lastTimestamp;
        
        // Management fee is prorated based on time since last collection
        uint256 managementFee = (totalAssetsValue * _managementFeePercentage * timeSinceLastCollection) / (BASIS_POINTS * 365 days);
        
        return managementFee;
    }
    
    /**
     * @dev Calculates performance fee
     * @param vault The address of the vault
     * @param currentSharePrice The current price per share
     * @param totalSupply The total supply of shares
     * @param decimals The number of decimals in the share token
     * @return performanceFee The calculated performance fee
     */
    function calculatePerformanceFee(
        address vault,
        uint256 currentSharePrice,
        uint256 totalSupply,
        uint8 decimals
    ) external view override returns (uint256) {
        if (useFixedFees) {
            return mockPerformanceFee;
        }
        
        uint256 highWaterMark = _highWaterMarks[vault];
        
        // If current share price is higher than high water mark
        if (currentSharePrice > highWaterMark) {
            uint256 appreciation = currentSharePrice - highWaterMark;
            uint256 feePerShare = (appreciation * _performanceFeePercentage) / BASIS_POINTS;
            
            if (feePerShare > 0) {
                // Calculate total performance fee based on total supply
                uint256 performanceFee = (feePerShare * totalSupply) / 10**decimals;
                
                // Update high watermark
                _highWaterMarks[vault] = currentSharePrice;
                
                return performanceFee;
            }
            
            // Update high watermark even if no fee is collected
            _highWaterMarks[vault] = currentSharePrice;
        }
        
        return 0;
    }
    
    /**
     * @dev Manually set the high water mark for a vault
     * @param vault The address of the vault
     * @param newHighWaterMark The new high water mark
     */
    function setHighWaterMark(address vault, uint256 newHighWaterMark) external override {
        _highWaterMarks[vault] = newHighWaterMark;
    }
    
    /**
     * @dev Manually set the last fee collection timestamp for a vault
     * @param vault The address of the vault
     * @param timestamp The timestamp to set
     */
    function setLastFeeCollectionTimestamp(address vault, uint256 timestamp) external override {
        _lastFeeCollectionTimestamps[vault] = timestamp;
    }
    
    /**
     * @dev Returns the management fee percentage
     */
    function managementFeePercentage() external view override returns (uint256) {
        return _managementFeePercentage;
    }
    
    /**
     * @dev Returns the performance fee percentage
     */
    function performanceFeePercentage() external view override returns (uint256) {
        return _performanceFeePercentage;
    }
    
    /**
     * @dev Returns the high water mark for a vault
     */
    function highWaterMarks(address vault) external view override returns (uint256) {
        return _highWaterMarks[vault];
    }
    
    /**
     * @dev Returns the last fee collection timestamp for a vault
     */
    function lastFeeCollectionTimestamps(address vault) external view override returns (uint256) {
        return _lastFeeCollectionTimestamps[vault];
    }
    
    /**
     * @dev Collect management and performance fees
     * @param totalValue The total value of the vault
     * @param timeElapsed The time elapsed since last fee collection
     * @return managementFee The management fee collected
     * @return performanceFee The performance fee collected
     */
    function collectFees(
        uint256 totalValue,
        uint256 timeElapsed
    ) external view override returns (uint256 managementFee, uint256 performanceFee) {
        if (useFixedFees) {
            return (mockManagementFee, mockPerformanceFee);
        }
        
        // Calculate management fee (annualized)
        managementFee = (totalValue * _managementFeePercentage * timeElapsed) / (BASIS_POINTS * 365 days);
        
        // For simplicity, we'll just return a performance fee as a percentage of the total value
        // In a real implementation, this would compare against a high water mark
        performanceFee = (totalValue * _performanceFeePercentage) / (BASIS_POINTS * 10); // Reduced for testing
        
        return (managementFee, performanceFee);
    }
    
    /**
     * @dev Get the fee recipient address
     * @return recipient The address of the fee recipient
     */
    function getFeeRecipient() external view override returns (address recipient) {
        return feeRecipient;
    }
    
    // Test helper functions
    
    /**
     * @dev Set whether to use fixed fees for testing
     * @param use Whether to use fixed fees
     */
    function setUseFixedFees(bool use) external {
        useFixedFees = use;
    }
    
    /**
     * @dev Set the mock management fee for testing
     * @param fee The fee to return
     */
    function setMockManagementFee(uint256 fee) external {
        mockManagementFee = fee;
    }
    
    /**
     * @dev Set the mock performance fee for testing
     * @param fee The fee to return
     */
    function setMockPerformanceFee(uint256 fee) external {
        mockPerformanceFee = fee;
    }
}
