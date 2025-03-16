// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockPriceOracle} from "./MockPriceOracle.sol";
import {IDEX} from "../interfaces/IDEX.sol";

/**
 * @title MockDEX
 * @dev Mock DEX for testing
 */
contract MockDEX is IDEX, Ownable {
    using SafeERC20 for IERC20;

    MockPriceOracle public priceOracle;
    uint256 public constant FEE_BASIS_POINTS = 30; // 0.3% fee
    uint256 public constant BASIS_POINTS = 10000;

    /**
     * @dev Constructor that initializes the DEX with a price oracle
     * @param _priceOracle The price oracle address
     */
    constructor(MockPriceOracle _priceOracle) Ownable(msg.sender) {
        priceOracle = _priceOracle;
    }

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
    ) external returns (uint256 toAmount) {
        require(fromToken != toToken, "Same token");
        require(fromAmount > 0, "Zero amount");

        // Transfer the fromToken from the sender to this contract
        IERC20(fromToken).safeTransferFrom(msg.sender, address(this), fromAmount);

        // Calculate the toAmount based on the price oracle
        uint256 fromValueInBase = priceOracle.convertToBaseAsset(fromToken, fromAmount);
        uint256 feeAmount = (fromValueInBase * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 toValueInBase = fromValueInBase - feeAmount;
        toAmount = priceOracle.convertFromBaseAsset(toToken, toValueInBase);

        require(toAmount >= minToAmount, "Slippage too high");

        // Transfer the toToken to the sender
        IERC20(toToken).safeTransfer(msg.sender, toAmount);

        return toAmount;
    }

    /**
     * @dev Swaps an exact amount of input tokens for as many output tokens as possible
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param fromAmount The exact amount of fromToken to swap
     * @param minToAmount The minimum amount of toToken to receive
     * @return toAmount The amount of toToken received
     */
    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount
    ) external returns (uint256 toAmount) {
        require(fromToken != toToken, "Same token");
        require(fromAmount > 0, "Zero amount");

        // Transfer the fromToken from the sender to this contract
        IERC20(fromToken).safeTransferFrom(msg.sender, address(this), fromAmount);

        // Calculate the toAmount based on the price oracle
        uint256 fromValueInBase = priceOracle.convertToBaseAsset(fromToken, fromAmount);
        uint256 feeAmount = (fromValueInBase * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 toValueInBase = fromValueInBase - feeAmount;
        toAmount = priceOracle.convertFromBaseAsset(toToken, toValueInBase);

        require(toAmount >= minToAmount, "Slippage too high");

        // Transfer the toToken to the sender
        IERC20(toToken).safeTransfer(msg.sender, toAmount);

        return toAmount;
    }

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
    ) external view returns (uint256 toAmount) {
        uint256 fromValueInBase = priceOracle.convertToBaseAsset(fromToken, fromAmount);
        uint256 feeAmount = (fromValueInBase * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 toValueInBase = fromValueInBase - feeAmount;
        return priceOracle.convertFromBaseAsset(toToken, toValueInBase);
    }

    /**
     * @dev Withdraws tokens from the DEX
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
