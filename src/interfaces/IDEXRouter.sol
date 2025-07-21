// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDEXRouter
 * @dev Interface for DEX routers to enable token swaps
 */
interface IDEXRouter {
    /**
     * @dev Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @return amountOut The amount of output tokens received
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut
    ) external returns (uint256 amountOut);
    
    /**
     * @dev Returns the expected output amount for a given input amount and token pair
     * @param amountIn The amount of input tokens
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @return amountOut The expected amount of output tokens
     */
    function getAmountsOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountOut);
}