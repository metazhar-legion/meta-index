// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDEX
 * @dev Interface for DEXes
 */
interface IDEX {
    /**
     * @dev Swaps tokens
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param fromAmount The amount of fromToken to swap
     * @param minToAmount The minimum amount of toToken to receive
     * @return toAmount The amount of toToken received
     */
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount
    ) external returns (uint256 toAmount);

    /**
     * @dev Gets the expected amount of toToken for a given amount of fromToken
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param fromAmount The amount of fromToken to swap
     * @return toAmount The expected amount of toToken
     */
    function getExpectedAmount(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view returns (uint256 toAmount);
}
