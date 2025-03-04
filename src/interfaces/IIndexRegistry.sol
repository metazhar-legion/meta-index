// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IIndexRegistry
 * @dev Interface for the IndexRegistry contract
 */
interface IIndexRegistry {
    /**
     * @dev Gets the current index composition
     * @return tokens Array of token addresses
     * @return weights Array of token weights in basis points
     */
    function getCurrentIndex() external view returns (address[] memory tokens, uint256[] memory weights);
}
