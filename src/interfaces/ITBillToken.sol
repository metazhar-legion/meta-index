// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITBillToken
 * @dev Interface for tokenized T-Bill protocols
 */
interface ITBillToken {
    /**
     * @dev Deposits base asset to mint T-Bill tokens
     * @param amount The amount of base asset to deposit
     * @return tBillAmount The amount of T-Bill tokens minted
     */
    function deposit(uint256 amount) external returns (uint256 tBillAmount);

    /**
     * @dev Redeems T-Bill tokens for base asset
     * @param amount The amount of T-Bill tokens to redeem
     * @return baseAmount The amount of base asset received
     */
    function redeem(uint256 amount) external returns (uint256 baseAmount);

    /**
     * @dev Gets the current value of T-Bill tokens in base asset
     * @param tBillAmount The amount of T-Bill tokens
     * @return baseAmount The equivalent amount in base asset
     */
    function getBaseAssetValue(uint256 tBillAmount) external view returns (uint256 baseAmount);

    /**
     * @dev Gets the current yield rate of the T-Bill
     * @return yield The current yield in basis points (e.g., 400 = 4.00%)
     */
    function getCurrentYield() external view returns (uint256 yield);

    /**
     * @dev Gets the maturity date of the T-Bill
     * @return maturityDate The timestamp when the T-Bill matures
     */
    function getMaturityDate() external view returns (uint256 maturityDate);
}
