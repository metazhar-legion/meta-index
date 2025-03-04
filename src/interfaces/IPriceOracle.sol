// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @dev Interface for price oracles
 */
interface IPriceOracle {
    /**
     * @dev Gets the price of a token
     * @param token The token address
     * @return The price in base asset terms (with 18 decimals)
     */
    function getPrice(address token) external view returns (uint256);

    /**
     * @dev Converts an amount of a token to the base asset
     * @param token The token address
     * @param amount The token amount
     * @return The equivalent amount in base asset terms
     */
    function convertToBaseAsset(address token, uint256 amount) external view returns (uint256);

    /**
     * @dev Converts an amount of the base asset to a token
     * @param token The token address
     * @param amount The base asset amount
     * @return The equivalent amount in token terms
     */
    function convertFromBaseAsset(address token, uint256 amount) external view returns (uint256);
}
