// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title MockPriceOracle
 * @dev Mock price oracle for testing
 */
contract MockPriceOracle is IPriceOracle, Ownable {
    mapping(address => uint256) public prices;
    address public baseAsset;

    /**
     * @dev Constructor that initializes the oracle with a base asset
     * @param _baseAsset The base asset address
     */
    constructor(address _baseAsset) Ownable(msg.sender) {
        baseAsset = _baseAsset;
        // Set the base asset price to 1
        prices[baseAsset] = 1e18;
    }

    /**
     * @dev Sets the price of a token
     * @param token The token address
     * @param price The price in base asset terms (with 18 decimals)
     */
    function setPrice(address token, uint256 price) external onlyOwner {
        prices[token] = price;
    }

    /**
     * @dev Gets the price of a token
     * @param token The token address
     * @return The price in base asset terms (with 18 decimals)
     */
    function getPrice(address token) external view returns (uint256) {
        require(prices[token] > 0, "Price not set");
        return prices[token];
    }

    /**
     * @dev Converts an amount of a token to the base asset
     * @param token The token address
     * @param amount The token amount
     * @return The equivalent amount in base asset terms
     */
    function convertToBaseAsset(address token, uint256 amount) external view returns (uint256) {
        require(prices[token] > 0, "Price not set");
        return (amount * prices[token]) / 1e18;
    }

    /**
     * @dev Converts an amount of the base asset to a token
     * @param token The token address
     * @param amount The base asset amount
     * @return The equivalent amount in token terms
     */
    function convertFromBaseAsset(address token, uint256 amount) external view returns (uint256) {
        require(prices[token] > 0, "Price not set");
        return (amount * 1e18) / prices[token];
    }
}
