// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDEXAdapter
 * @dev Interface for DEX adapters that standardizes interactions with various DEXs
 */
interface IDEXAdapter {
    /**
     * @dev Swaps tokens using the underlying DEX
     * @param tokenIn The token to swap from
     * @param tokenOut The token to swap to
     * @param amountIn The amount of tokenIn to swap
     * @param minAmountOut The minimum amount of tokenOut to receive
     * @param recipient The address to receive the swapped tokens
     * @return amountOut The amount of tokenOut received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);
    
    /**
     * @dev Gets the expected amount of tokenOut for a given amount of tokenIn
     * @param tokenIn The token to swap from
     * @param tokenOut The token to swap to
     * @param amountIn The amount of tokenIn to swap
     * @return amountOut The expected amount of tokenOut
     */
    function getExpectedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
    
    /**
     * @dev Checks if the DEX supports a specific token pair
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @return supported Whether the pair is supported
     */
    function isPairSupported(
        address tokenIn,
        address tokenOut
    ) external view returns (bool supported);
    
    /**
     * @dev Gets the name of the DEX
     * @return name The name of the DEX
     */
    function getDexName() external pure returns (string memory name);
}
