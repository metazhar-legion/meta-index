// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";

/**
 * @title MockYieldStrategy
 * @dev Mock implementation of IYieldStrategy for testing
 */
contract MockYieldStrategy is IYieldStrategy, Ownable {
    using SafeERC20 for IERC20;

    // The underlying asset
    IERC20 public asset;

    // Strategy information
    StrategyInfo private _strategyInfo;

    // Share price (1 share = sharePrice / 1e18 assets)
    uint256 public sharePrice = 1e18;

    // Total shares issued
    uint256 public totalShares;

    // Simulated yield percentage (in basis points)
    uint256 public yieldRate = 500; // 5% by default

    /**
     * @dev Constructor
     * @param _asset The underlying asset
     * @param _name The name of the strategy
     */
    constructor(IERC20 _asset, string memory _name) Ownable(msg.sender) {
        asset = _asset;

        _strategyInfo = StrategyInfo({
            name: _name,
            asset: address(_asset),
            totalDeposited: 0,
            currentValue: 0,
            apy: 500, // 5% APY by default
            lastUpdated: block.timestamp,
            active: true,
            risk: 3 // Moderate risk
        });
    }

    /**
     * @dev Set the share price for testing
     * @param _sharePrice The new share price
     */
    function setSharePrice(uint256 _sharePrice) external onlyOwner {
        sharePrice = _sharePrice;
        _updateStrategyInfo();
    }

    /**
     * @dev Set the yield rate for testing
     * @param _yieldRate The new yield rate in basis points
     */
    function setYieldRate(uint256 _yieldRate) external onlyOwner {
        yieldRate = _yieldRate;
        _strategyInfo.apy = _yieldRate;
    }

    /**
     * @dev Deposits assets into the yield strategy
     * @param amount The amount to deposit
     * @return shares The number of shares received
     */
    function deposit(uint256 amount) external override returns (uint256 shares) {
        if (amount == 0) return 0;

        // Transfer assets from sender
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate shares
        shares = (amount * 1e18) / sharePrice;

        // Update state
        totalShares += shares;
        _strategyInfo.totalDeposited += amount;
        _updateStrategyInfo();

        return shares;
    }

    /**
     * @dev Withdraws assets from the yield strategy
     * @param shares The number of shares to withdraw
     * @return amount The amount withdrawn
     */
    function withdraw(uint256 shares) external override returns (uint256 amount) {
        if (shares == 0 || shares > totalShares) return 0;

        // Calculate amount
        amount = (shares * sharePrice) / 1e18;

        // Update state
        totalShares -= shares;
        _updateStrategyInfo();

        // Transfer assets to sender
        asset.safeTransfer(msg.sender, amount);

        return amount;
    }

    /**
     * @dev Gets the current value of shares
     * @param shares The number of shares
     * @return value The current value of the shares
     */
    function getValueOfShares(uint256 shares) external view override returns (uint256 value) {
        if (shares == 0 || totalShares == 0) return 0;
        return (shares * sharePrice) / 1e18;
    }

    /**
     * @dev Gets the total value of all assets in the strategy
     * @return value The total value
     */
    function getTotalValue() external view override returns (uint256 value) {
        return (totalShares * sharePrice) / 1e18;
    }

    /**
     * @dev Gets the current APY of the strategy
     * @return apy The current APY in basis points
     */
    function getCurrentAPY() external view override returns (uint256 apy) {
        return _strategyInfo.apy;
    }

    /**
     * @dev Gets detailed information about the strategy
     * @return info The strategy information
     */
    function getStrategyInfo() external view override returns (StrategyInfo memory info) {
        return _strategyInfo;
    }

    /**
     * @dev Harvests yield from the strategy
     * @return harvested The amount harvested
     */
    function harvestYield() external override returns (uint256 harvested) {
        // Calculate yield based on current value and yield rate
        uint256 currentValue = (totalShares * sharePrice) / 1e18;
        harvested = (currentValue * yieldRate) / 10000; // Apply yield rate

        // Mint the yield to this contract (simulating yield generation)
        // In a real strategy, this would come from external protocols

        // Transfer harvested yield to caller
        if (harvested > 0 && asset.balanceOf(address(this)) >= harvested) {
            asset.safeTransfer(msg.sender, harvested);
        } else {
            harvested = 0;
        }

        return harvested;
    }

    /**
     * @dev Simulates yield generation for testing
     * @param amount The amount of yield to generate
     */
    function simulateYield(uint256 amount) external onlyOwner {
        // Increase share price to simulate yield
        sharePrice = sharePrice + ((sharePrice * amount) / asset.balanceOf(address(this)));
        _updateStrategyInfo();
    }

    /**
     * @dev Update strategy info based on current state
     */
    function _updateStrategyInfo() private {
        _strategyInfo.currentValue = (totalShares * sharePrice) / 1e18;
        _strategyInfo.lastUpdated = block.timestamp;
    }
}
