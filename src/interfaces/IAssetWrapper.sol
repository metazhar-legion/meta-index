// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAssetWrapper
 * @dev Interface for asset wrappers that abstract the implementation details of different asset types
 */
interface IAssetWrapper {
    /**
     * @dev Get the current value of this asset in terms of the base asset (e.g., USDC)
     * @return The current value in base asset units
     */
    function getValueInBaseAsset() external view returns (uint256);

    /**
     * @dev Allocate more capital to this asset
     * @param amount The amount of base asset to allocate
     * @return success Whether the allocation was successful
     */
    function allocateCapital(uint256 amount) external returns (bool);

    /**
     * @dev Withdraw capital from this asset
     * @param amount The amount of base asset to withdraw
     * @return actualAmount The actual amount withdrawn (may differ due to slippage, fees, etc.)
     */
    function withdrawCapital(uint256 amount) external returns (uint256 actualAmount);

    /**
     * @dev Get the underlying tokens this wrapper manages
     * @return tokens Array of token addresses
     */
    function getUnderlyingTokens() external view returns (address[] memory tokens);

    /**
     * @dev Get the name of this asset wrapper
     * @return name The name of the asset wrapper
     */
    function getName() external view returns (string memory name);

    /**
     * @dev Harvest any yield generated by this asset wrapper
     * @return harvestedAmount The amount of yield harvested in base asset units
     */
    function harvestYield() external returns (uint256 harvestedAmount);

    /**
     * @dev Get the base asset used by this wrapper
     * @return baseAsset The address of the base asset token
     */
    function getBaseAsset() external view returns (address baseAsset);
}
