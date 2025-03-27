// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFeeManager
 * @dev Interface for the FeeManager contract
 */
interface IFeeManager {
    /**
     * @dev Updates the management fee percentage
     * @param newFee The new fee in basis points
     */
    function setManagementFeePercentage(uint256 newFee) external;
    
    /**
     * @dev Updates the performance fee percentage
     * @param newFee The new fee in basis points
     */
    function setPerformanceFeePercentage(uint256 newFee) external;
    
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
    ) external returns (uint256 managementFee);
    
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
    ) external returns (uint256 performanceFee);
    
    /**
     * @dev Manually set the high water mark for a vault
     * @param vault The address of the vault
     * @param highWaterMark The new high water mark
     */
    function setHighWaterMark(address vault, uint256 highWaterMark) external;
    
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
    ) external returns (uint256 managementFee, uint256 performanceFee);
    
    /**
     * @dev Get the fee recipient address
     * @return recipient The address of the fee recipient
     */
    function getFeeRecipient() external view returns (address recipient);
    
    /**
     * @dev Manually set the last fee collection timestamp for a vault
     * @param vault The address of the vault
     * @param timestamp The timestamp to set
     */
    function setLastFeeCollectionTimestamp(address vault, uint256 timestamp) external;
    
    /**
     * @dev Returns the management fee percentage
     */
    function managementFeePercentage() external view returns (uint256);
    
    /**
     * @dev Returns the performance fee percentage
     */
    function performanceFeePercentage() external view returns (uint256);
    
    /**
     * @dev Returns the high water mark for a vault
     */
    function highWaterMarks(address vault) external view returns (uint256);
    
    /**
     * @dev Returns the last fee collection timestamp for a vault
     */
    function lastFeeCollectionTimestamps(address vault) external view returns (uint256);
}
