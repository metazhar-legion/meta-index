// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidStaking
 * @dev Interface for liquid staking protocols like Lido or Rocket Pool
 */
interface ILiquidStaking {
    /**
     * @dev Stakes the base asset and mints liquid staking tokens
     * @param amount The amount of base asset to stake
     * @return stakingTokenAmount The amount of liquid staking tokens minted
     */
    function stake(uint256 amount) external returns (uint256 stakingTokenAmount);

    /**
     * @dev Unstakes liquid staking tokens and returns base asset
     * @param amount The amount of liquid staking tokens to unstake
     * @return baseAmount The amount of base asset received
     */
    function unstake(uint256 amount) external returns (uint256 baseAmount);

    /**
     * @dev Gets the current exchange rate between staking tokens and base asset
     * @param stakingTokenAmount The amount of staking tokens
     * @return baseAmount The equivalent amount in base asset
     */
    function getBaseAssetValue(uint256 stakingTokenAmount) external view returns (uint256 baseAmount);

    /**
     * @dev Gets the current APY of the staking protocol
     * @return apy The current APY in basis points (e.g., 450 = 4.50%)
     */
    function getCurrentAPY() external view returns (uint256 apy);

    /**
     * @dev Calculates how many staking tokens are needed to get a specific amount of base asset
     * @param baseAssetAmount The amount of base asset desired
     * @return stakingTokenAmount The amount of staking tokens needed
     */
    function getStakingTokensForBaseAsset(uint256 baseAssetAmount) external view returns (uint256 stakingTokenAmount);

    /**
     * @dev Gets the total amount of base asset staked in the protocol
     * @return totalStaked The total amount staked
     */
    function getTotalStaked() external view returns (uint256 totalStaked);
}
