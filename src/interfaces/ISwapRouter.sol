// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISwapRouter
 * @notice Interface for DEX swap router functionality
 */
interface ISwapRouter {
    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received
     * @param path The token addresses to trade through
     * @param to The recipient address
     * @param deadline The unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swaps as few input tokens as possible for an exact amount of output tokens
     * @param amountOut The amount of output tokens to receive
     * @param amountInMax The maximum amount of input tokens that can be required
     * @param path The token addresses to trade through
     * @param to The recipient address
     * @param deadline The unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Get the amount of output tokens for an exact input amount
     * @param amountIn The amount of input tokens
     * @param path The token addresses to trade through
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    /**
     * @notice Get the amount of input tokens for an exact output amount
     * @param amountOut The amount of output tokens
     * @param path The token addresses to trade through
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function getAmountsIn(
        uint256 amountOut,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}
