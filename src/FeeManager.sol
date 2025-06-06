// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title FeeManager
 * @dev Manages fee calculations for the index fund vaults
 */
contract FeeManager is Ownable {
    // Fee structure
    uint256 public managementFeePercentage = 100; // 1% annual (in basis points)
    uint256 public performanceFeePercentage = 1000; // 10% (in basis points)
    uint256 public constant BASIS_POINTS = 10000;
    
    // Fee recipient address
    address public feeRecipient;

    // High watermark for performance fees, mapped by vault address
    mapping(address => uint256) public highWaterMarks;

    // Last fee collection timestamp, mapped by vault address
    mapping(address => uint256) public lastFeeCollectionTimestamps;

    // Events
    event ManagementFeeCalculated(address indexed vault, uint256 amount);
    event PerformanceFeeCalculated(address indexed vault, uint256 amount);
    event ManagementFeeUpdated(uint256 newFee);
    event PerformanceFeeUpdated(uint256 newFee);
    event HighWaterMarkUpdated(address indexed vault, uint256 newHighWaterMark);

    constructor() Ownable(msg.sender) {
        feeRecipient = msg.sender; // Set the fee recipient to the deployer by default
    }

    /**
     * @dev Updates the management fee percentage
     * @param newFee The new fee in basis points
     */
    function setManagementFeePercentage(uint256 newFee) external onlyOwner {
        if (newFee > 500) revert CommonErrors.ValueOutOfRange(newFee, 0, 500); // Max 5%
        managementFeePercentage = newFee;
        emit ManagementFeeUpdated(newFee);
    }

    /**
     * @dev Updates the performance fee percentage
     * @param newFee The new fee in basis points
     */
    function setPerformanceFeePercentage(uint256 newFee) external onlyOwner {
        if (newFee > 3000) revert CommonErrors.ValueOutOfRange(newFee, 0, 3000); // Max 30%
        performanceFeePercentage = newFee;
        emit PerformanceFeeUpdated(newFee);
    }

    /**
     * @dev Calculates management fee
     * @param vault The address of the vault
     * @param totalAssetsValue The total value of assets in the vault
     * @param currentTimestamp The current timestamp
     * @return managementFee The calculated management fee
     */
    function calculateManagementFee(address vault, uint256 totalAssetsValue, uint256 currentTimestamp)
        public
        returns (uint256 managementFee)
    {
        uint256 lastTimestamp = lastFeeCollectionTimestamps[vault];

        // If this is the first fee calculation, set the timestamp and return 0
        if (lastTimestamp == 0) {
            lastFeeCollectionTimestamps[vault] = currentTimestamp;
            return 0;
        }

        uint256 timeSinceLastCollection = currentTimestamp - lastTimestamp;

        // Management fee is prorated based on time since last collection
        managementFee =
            (totalAssetsValue * managementFeePercentage * timeSinceLastCollection) / (BASIS_POINTS * 365 days);

        // Update the last collection timestamp
        lastFeeCollectionTimestamps[vault] = currentTimestamp;

        emit ManagementFeeCalculated(vault, managementFee);
    }

    /**
     * @dev Calculates performance fee
     * @param vault The address of the vault
     * @param currentSharePrice The current price per share
     * @param totalSupply The total supply of shares
     * @param decimals The number of decimals in the share token
     * @return performanceFee The calculated performance fee
     */
    function calculatePerformanceFee(address vault, uint256 currentSharePrice, uint256 totalSupply, uint8 decimals)
        public
        returns (uint256 performanceFee)
    {
        uint256 highWaterMark = highWaterMarks[vault];

        // If current share price is higher than high water mark
        if (currentSharePrice > highWaterMark) {
            uint256 appreciation = currentSharePrice - highWaterMark;
            uint256 feePerShare = (appreciation * performanceFeePercentage) / BASIS_POINTS;

            if (feePerShare > 0) {
                // Calculate total performance fee based on total supply
                performanceFee = (feePerShare * totalSupply) / 10 ** decimals;

                emit PerformanceFeeCalculated(vault, performanceFee);
            }

            // Update high watermark
            highWaterMarks[vault] = currentSharePrice;
            emit HighWaterMarkUpdated(vault, currentSharePrice);
        }
    }

    /**
     * @dev Manually set the high water mark for a vault
     * @param vault The address of the vault
     * @param newHighWaterMark The new high water mark
     */
    function setHighWaterMark(address vault, uint256 newHighWaterMark) external onlyOwner {
        highWaterMarks[vault] = newHighWaterMark;
        emit HighWaterMarkUpdated(vault, newHighWaterMark);
    }

    /**
     * @dev Manually set the last fee collection timestamp for a vault
     * @param vault The address of the vault
     * @param timestamp The timestamp to set
     */
    function setLastFeeCollectionTimestamp(address vault, uint256 timestamp) external onlyOwner {
        lastFeeCollectionTimestamps[vault] = timestamp;
    }
    
    /**
     * @dev Collect management and performance fees
     * @param totalValue The total value of the vault
     * @param timeElapsed The time elapsed since last fee collection
     * @return managementFee The management fee collected
     * @return performanceFee The performance fee collected
     */
    function collectFees(uint256 totalValue, uint256 timeElapsed)
        external
        view
        returns (uint256 managementFee, uint256 performanceFee)
    {
        // Calculate management fee based on total value and time elapsed
        managementFee = (totalValue * managementFeePercentage * timeElapsed) / (BASIS_POINTS * 365 days);
        
        // For simplicity, we're not calculating performance fee here
        // In a real implementation, you would need additional parameters like current share price
        performanceFee = 0;
        
        return (managementFee, performanceFee);
    }
    
    /**
     * @dev Get the fee recipient address
     * @return recipient The address of the fee recipient
     */
    function getFeeRecipient() external view returns (address recipient) {
        return feeRecipient;
    }
    
    /**
     * @dev Set the fee recipient address
     * @param newRecipient The new fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert CommonErrors.ZeroAddress();
        feeRecipient = newRecipient;
    }
}
