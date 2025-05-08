// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIndexRegistry} from "../interfaces/IIndexRegistry.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title MockIndexRegistry
 * @dev Mock implementation of the IIndexRegistry interface for testing
 */
contract MockIndexRegistry is IIndexRegistry {
    // Events
    event IndexUpdated(address[] tokens, uint256[] weights);

    address[] private _tokens;
    uint256[] private _weights;
    uint256 public lastUpdated;

    /**
     * @dev Updates the index composition with new tokens and weights
     * @param tokens Array of token addresses
     * @param weights Array of token weights (in basis points)
     * @return success True if the update was successful
     */
    function updateIndex(address[] memory tokens, uint256[] memory weights) external returns (bool success) {
        if (tokens.length != weights.length) revert CommonErrors.MismatchedArrayLengths();

        // Validate weights sum to 10000 (100%)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        if (totalWeight != 10000) revert CommonErrors.TotalExceeds100Percent();

        // Update index
        delete _tokens;
        delete _weights;

        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens.push(tokens[i]);
            _weights.push(weights[i]);
        }

        lastUpdated = block.timestamp;

        emit IndexUpdated(tokens, weights);
        return true;
    }

    /**
     * @dev Gets the current index composition
     * @return tokens Array of token addresses
     * @return weights Array of token weights (in basis points)
     */
    function getIndex() external view returns (address[] memory tokens, uint256[] memory weights) {
        return (_tokens, _weights);
    }

    /**
     * @dev Gets the weight of a specific token in the index
     * @param token Token address
     * @return weight Token weight in basis points (0-10000)
     */
    function getTokenWeight(address token) external view returns (uint256 weight) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == token) {
                return _weights[i];
            }
        }
        return 0;
    }

    /**
     * @dev Checks if a token is part of the index
     * @param token Token address
     * @return isIncluded True if the token is included in the index
     */
    function isTokenIncluded(address token) external view returns (bool isIncluded) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Gets the current index composition (alias for getIndex)
     * @return tokens Array of token addresses
     * @return weights Array of token weights (in basis points)
     */
    function getCurrentIndex() external view returns (address[] memory tokens, uint256[] memory weights) {
        return (_tokens, _weights);
    }
}
