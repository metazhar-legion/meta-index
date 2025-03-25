// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IIndexRegistry} from "./IIndexRegistry.sol";
import {IFeeManager} from "./IFeeManager.sol";

/**
 * @title IIndexFundVault
 * @dev Interface for the IndexFundVault contract
 */
interface IIndexFundVault is IERC4626 {
    /**
     * @dev Updates the index registry address
     * @param newRegistry The new registry contract address
     */
    function setIndexRegistry(IIndexRegistry newRegistry) external;

    /**
     * @dev Sets the rebalancing interval
     * @param newInterval The new interval in seconds
     */
    function setRebalancingInterval(uint256 newInterval) external;

    /**
     * @dev Sets the rebalancing threshold
     * @param newThreshold The new threshold in basis points
     */
    function setRebalancingThreshold(uint256 newThreshold) external;

    /**
     * @dev Sets the fee manager address
     * @param newFeeManager The new fee manager contract address
     */
    function setFeeManager(IFeeManager newFeeManager) external;
    
    /**
     * @dev Sets the management fee percentage
     * @param newFee The new fee in basis points
     */
    function setManagementFee(uint256 newFee) external;

    /**
     * @dev Sets the performance fee percentage
     * @param newFee The new fee in basis points
     */
    function setPerformanceFee(uint256 newFee) external;

    /**
     * @dev Sets the price oracle address
     * @param newOracle The new price oracle address
     */
    function setPriceOracle(address newOracle) external;

    /**
     * @dev Sets the DEX address
     * @param newDex The new DEX address
     */
    function setDEX(address newDex) external;

    /**
     * @dev Rebalances the index fund according to the current index composition
     */
    function rebalance() external;

    /**
     * @dev Checks if rebalancing is needed based on the deviation threshold
     * @return bool True if rebalancing is needed
     */
    function isRebalancingNeeded() external view returns (bool);

    /**
     * @dev Returns the current index composition
     * @return tokens Array of token addresses
     * @return weights Array of token weights in basis points
     */
    function getCurrentIndex() external view returns (address[] memory tokens, uint256[] memory weights);
}
