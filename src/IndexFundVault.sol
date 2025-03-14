// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IIndexFundVault} from "./interfaces/IIndexFundVault.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IDEX} from "./interfaces/IDEX.sol";

/**
 * @title IndexFundVault
 * @dev An ERC4626-compliant vault that implements a web3 index fund
 * allowing participants to deposit tokens and invest in a basket of assets.
 * The indices are determined by the DAO governance or the vault owner.
 */
contract IndexFundVault is ERC4626, Ownable, ReentrancyGuard, IIndexFundVault {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    // Target share price in USDC
    // Setting this to 100 means 1 share will be worth ~100 USDC initially
    uint256 private constant TARGET_SHARE_PRICE = 100;

    // Registry that maintains the index composition
    IIndexRegistry public indexRegistry;
    
    // Price oracle and DEX
    IPriceOracle public priceOracle;
    IDEX public dex;
    
    // Rebalancing settings
    uint256 public rebalancingInterval = 7 days;
    uint256 public lastRebalanceTimestamp;
    uint256 public rebalancingThreshold = 5; // 5% deviation triggers rebalance
    
    // Fee structure
    uint256 public managementFeePercentage = 100; // 1% annual (in basis points)
    uint256 public performanceFeePercentage = 1000; // 10% (in basis points)
    uint256 public constant BASIS_POINTS = 10000;
    
    // High watermark for performance fees
    uint256 public highWaterMark;
    
    // Events
    event Rebalanced(uint256 timestamp);
    event IndexRegistryUpdated(address indexed newRegistry);
    event PriceOracleUpdated(address indexed newOracle);
    event DEXUpdated(address indexed newDex);
    event ManagementFeeCollected(uint256 amount);
    event PerformanceFeeCollected(uint256 amount);
    event RebalancingIntervalUpdated(uint256 newInterval);
    event RebalancingThresholdUpdated(uint256 newThreshold);
    event ManagementFeeUpdated(uint256 newFee);
    event PerformanceFeeUpdated(uint256 newFee);

    /**
     * @dev Constructor that initializes the vault with the asset token and a name
     * @param asset_ The underlying asset token (typically a stablecoin)
     * @param registry_ The index registry contract address
     * @param oracle_ The price oracle contract address
     * @param dex_ The DEX contract address
     */
    constructor(
        IERC20 asset_,
        IIndexRegistry registry_,
        IPriceOracle oracle_,
        IDEX dex_
    ) 
        ERC4626(asset_)
        ERC20(
            string(abi.encodePacked("Index Fund Vault ", ERC20(address(asset_)).name())),
            string(abi.encodePacked("ifv", ERC20(address(asset_)).symbol()))
        )
        Ownable(msg.sender)
    {
        indexRegistry = registry_;
        priceOracle = oracle_;
        dex = dex_;
        lastRebalanceTimestamp = block.timestamp;
        highWaterMark = 0;
    }

    /**
     * @dev Updates the index registry address
     * @param newRegistry The new registry contract address
     */
    function setIndexRegistry(IIndexRegistry newRegistry) external onlyOwner {
        require(address(newRegistry) != address(0), "Invalid registry address");
        indexRegistry = newRegistry;
        emit IndexRegistryUpdated(address(newRegistry));
    }

    /**
     * @dev Sets the price oracle address
     * @param newOracle The new price oracle address
     */
    function setPriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid oracle address");
        priceOracle = IPriceOracle(newOracle);
        emit PriceOracleUpdated(newOracle);
    }

    /**
     * @dev Sets the DEX address
     * @param newDex The new DEX address
     */
    function setDEX(address newDex) external onlyOwner {
        require(newDex != address(0), "Invalid DEX address");
        dex = IDEX(newDex);
        emit DEXUpdated(newDex);
    }

    /**
     * @dev Sets the rebalancing interval
     * @param newInterval The new interval in seconds
     */
    function setRebalancingInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Invalid interval");
        rebalancingInterval = newInterval;
        emit RebalancingIntervalUpdated(newInterval);
    }

    /**
     * @dev Sets the rebalancing threshold
     * @param newThreshold The new threshold in basis points
     */
    function setRebalancingThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= 5000, "Invalid threshold"); // Max 50%
        rebalancingThreshold = newThreshold;
        emit RebalancingThresholdUpdated(newThreshold);
    }

    /**
     * @dev Sets the management fee percentage
     * @param newFee The new fee in basis points
     */
    function setManagementFee(uint256 newFee) external onlyOwner {
        require(newFee <= 500, "Fee too high"); // Max 5%
        managementFeePercentage = newFee;
        emit ManagementFeeUpdated(newFee);
    }

    /**
     * @dev Sets the performance fee percentage
     * @param newFee The new fee in basis points
     */
    function setPerformanceFee(uint256 newFee) external onlyOwner {
        require(newFee <= 3000, "Fee too high"); // Max 30%
        performanceFeePercentage = newFee;
        emit PerformanceFeeUpdated(newFee);
    }

    /**
     * @dev Rebalances the index fund according to the current index composition
     * This function can be called by anyone, but only after the rebalancing interval
     * has passed or if the deviation exceeds the threshold
     */
    function rebalance() external nonReentrant {
        require(
            block.timestamp >= lastRebalanceTimestamp + rebalancingInterval || 
            isRebalancingNeeded(),
            "Rebalancing not needed yet"
        );
        
        // Collect fees before rebalancing
        _collectFees();
        
        // Get the current index composition
        (address[] memory tokens, uint256[] memory weights) = indexRegistry.getCurrentIndex();
        require(tokens.length > 0, "Empty index");
        require(tokens.length == weights.length, "Mismatched arrays");
        
        // Calculate the total value of the vault
        uint256 totalValue = totalAssets();
        
        // Rebalance according to the weights
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 targetWeight = weights[i];
            uint256 targetAmount = (totalValue * targetWeight) / BASIS_POINTS;
            
            // Adjust position for this token
            _adjustPosition(token, targetAmount);
        }
        
        lastRebalanceTimestamp = block.timestamp;
        emit Rebalanced(block.timestamp);
    }

    /**
     * @dev Checks if rebalancing is needed based on the deviation threshold
     * @return bool True if rebalancing is needed
     */
    function isRebalancingNeeded() public view returns (bool) {
        (address[] memory tokens, uint256[] memory weights) = indexRegistry.getCurrentIndex();
        if (tokens.length == 0) return false;
        
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return false;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 targetWeight = weights[i];
            uint256 currentBalance = IERC20(token).balanceOf(address(this));
            
            // Get the current value of this token position
            uint256 currentValue = _getTokenValue(token, currentBalance);
            
            // Calculate current weight
            uint256 currentWeight = (currentValue * BASIS_POINTS) / totalValue;
            
            // Check if deviation exceeds threshold
            if (
                currentWeight > targetWeight && 
                currentWeight - targetWeight > rebalancingThreshold
            ) {
                return true;
            }
            if (
                targetWeight > currentWeight && 
                targetWeight - currentWeight > rebalancingThreshold
            ) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * @dev Collects management and performance fees
     */
    function _collectFees() internal {
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return;
        
        // Calculate management fee (pro-rated based on time since last collection)
        uint256 timePassed = block.timestamp - lastRebalanceTimestamp;
        uint256 managementFee = (totalValue * managementFeePercentage * timePassed) / (BASIS_POINTS * 365 days);
        
        if (managementFee > 0) {
            // Mint shares to the owner for the management fee
            _mint(owner(), convertToShares(managementFee));
            emit ManagementFeeCollected(managementFee);
        }
        
        // Calculate performance fee if we've exceeded the high water mark
        if (totalValue > highWaterMark) {
            uint256 profit = totalValue - highWaterMark;
            uint256 performanceFee = (profit * performanceFeePercentage) / BASIS_POINTS;
            
            if (performanceFee > 0) {
                // Mint shares to the owner for the performance fee
                _mint(owner(), convertToShares(performanceFee));
                emit PerformanceFeeCollected(performanceFee);
            }
            
            // Update high water mark
            highWaterMark = totalValue;
        }
    }

    /**
     * @dev Adjusts the position for a specific token to match the target amount
     * @param token The token address
     * @param targetAmount The target amount in the vault's asset terms
     */
    function _adjustPosition(address token, uint256 targetAmount) internal {
        uint256 currentBalance = IERC20(token).balanceOf(address(this));
        uint256 currentValue = _getTokenValue(token, currentBalance);
        
        if (currentValue < targetAmount) {
            // Need to buy more of this token
            uint256 amountToBuy = targetAmount - currentValue;
            _buyToken(token, amountToBuy);
        } else if (currentValue > targetAmount) {
            // Need to sell some of this token
            uint256 amountToSell = currentValue - targetAmount;
            _sellToken(token, amountToSell);
        }
    }

    /**
     * @dev Buys a token using the vault's assets
     * @param token The token to buy
     * @param amount The amount to buy in the vault's asset terms
     */
    function _buyToken(address token, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(asset())) return;
        
        address assetToken = address(asset());
        
        // Use the DEX to buy the token
        require(address(dex) != address(0), "DEX not set");
        
        // Calculate how much of the asset token we need to spend
        uint256 assetAmount = amount;
        
        // Get the expected amount of token we'll receive
        uint256 expectedTokenAmount = dex.getExpectedAmount(assetToken, token, assetAmount);
        require(expectedTokenAmount > 0, "Zero expected amount");
        
        // Approve the DEX to spend the asset token
        IERC20(assetToken).approve(address(dex), assetAmount);
        
        // Execute the swap
        dex.swap(assetToken, token, assetAmount, expectedTokenAmount * 95 / 100); // Allow 5% slippage
    }

    /**
     * @dev Sells a token to get the vault's assets
     * @param token The token to sell
     * @param amount The amount to sell in the vault's asset terms
     */
    function _sellToken(address token, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(asset())) return;
        
        address assetToken = address(asset());
        
        // Use the DEX to sell the token
        require(address(dex) != address(0), "DEX not set");
        require(address(priceOracle) != address(0), "Price oracle not set");
        
        // Calculate how much of the token we need to sell to get the desired amount of asset
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        uint256 tokenAmount = priceOracle.convertFromBaseAsset(token, amount);
        
        // Make sure we don't sell more than we have
        tokenAmount = Math.min(tokenAmount, tokenBalance);
        if (tokenAmount == 0) return;
        
        // Get the expected amount of asset token we'll receive
        uint256 expectedAssetAmount = dex.getExpectedAmount(token, assetToken, tokenAmount);
        require(expectedAssetAmount > 0, "Zero expected amount");
        
        // Check if we've already approved the DEX to spend this token
        uint256 allowance = IERC20(token).allowance(address(this), address(dex));
        if (allowance < tokenAmount) {
            // Reset approval to 0 first (some tokens require this)
            if (allowance > 0) {
                IERC20(token).approve(address(dex), 0);
            }
            // Approve the DEX to spend the token - approve the full balance
            IERC20(token).approve(address(dex), tokenBalance);
        }
        
        // Execute the swap
        dex.swap(token, assetToken, tokenAmount, expectedAssetAmount * 95 / 100); // Allow 5% slippage
    }

    /**
     * @dev Gets the value of a token amount in the vault's asset terms
     * @param token The token address
     * @param amount The token amount
     * @return The value in the vault's asset terms
     */
    function _getTokenValue(address token, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;
        if (token == address(asset())) return amount;
        
        // Use the price oracle to get the value
        require(address(priceOracle) != address(0), "Price oracle not set");
        return priceOracle.convertToBaseAsset(token, amount);
    }

    /**
     * @dev Ensures the vault has enough liquid assets for a withdrawal
     * @param assets The amount of assets needed
     */
    function _ensureLiquidity(uint256 assets) internal {
        uint256 assetBalance = IERC20(asset()).balanceOf(address(this));
        
        if (assetBalance < assets) {
            // Need to sell some tokens to get enough liquidity
            uint256 shortfall = assets - assetBalance;
            
            // Add a safety margin to account for slippage and fees (5%)
            uint256 targetAmount = shortfall + (shortfall * 5 / 100);
            
            // Get the current index composition
            (address[] memory tokens, uint256[] memory weights) = indexRegistry.getCurrentIndex();
            
            // First, try to sell tokens proportionally to their weights
            uint256 remainingShortfall = _sellTokensProportionally(tokens, weights, targetAmount);
            
            // If we still have a shortfall, try to sell any available tokens regardless of weight
            if (remainingShortfall > 0 && remainingShortfall < shortfall) {
                // We made some progress but not enough, try to sell more aggressively
                remainingShortfall = _sellRemainingTokens(tokens, remainingShortfall);
            }
            
            // Final check to ensure we have enough liquidity
            assetBalance = IERC20(asset()).balanceOf(address(this));
            require(assetBalance >= assets, "IndexFundVault: Insufficient liquidity for withdrawal");
        }
    }
    
    /**
     * @dev Sells tokens proportionally to their weights to meet the target amount
     * @param tokens Array of token addresses
     * @param weights Array of token weights
     * @param targetAmount The target amount to raise in asset terms
     * @return remainingShortfall The amount still needed after selling
     */
    function _sellTokensProportionally(
        address[] memory tokens, 
        uint256[] memory weights, 
        uint256 targetAmount
    ) internal returns (uint256) {
        uint256 remainingAmount = targetAmount;
        
        // First pass: try to sell tokens proportionally to their weights
        for (uint256 i = 0; i < tokens.length && remainingAmount > 0; i++) {
            address token = tokens[i];
            uint256 weight = weights[i];
            
            // Skip if token is the asset token
            if (token == asset()) continue;
            
            // Calculate how much of this token to sell
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            
            // Skip if we don't have any of this token
            if (tokenBalance == 0) continue;
            
            // Calculate token value in asset terms
            uint256 tokenValue = _getTokenValue(token, tokenBalance);
            
            // Calculate how much to sell based on weight
            uint256 amountToSell = Math.min(
                (targetAmount * weight) / BASIS_POINTS,
                Math.min(tokenValue, remainingAmount)
            );
            
            if (amountToSell > 0) {
                uint256 received = _executeTokenSale(token, amountToSell);
                remainingAmount = received >= remainingAmount ? 0 : remainingAmount - received;
            }
        }
        
        return remainingAmount;
    }
    
    /**
     * @dev Sells remaining tokens to meet the target amount regardless of weight
     * @param tokens Array of token addresses
     * @param targetAmount The target amount to raise in asset terms
     * @return remainingShortfall The amount still needed after selling
     */
    function _sellRemainingTokens(
        address[] memory tokens, 
        uint256 targetAmount
    ) internal returns (uint256) {
        uint256 remainingAmount = targetAmount;
        
        // Second pass: sell any available tokens to cover the shortfall
        for (uint256 i = 0; i < tokens.length && remainingAmount > 0; i++) {
            address token = tokens[i];
            
            // Skip if token is the asset token
            if (token == asset()) continue;
            
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            
            // Skip if we don't have any of this token
            if (tokenBalance == 0) continue;
            
            // Calculate token value in asset terms
            uint256 tokenValue = _getTokenValue(token, tokenBalance);
            
            if (tokenValue > 0) {
                // Sell up to the remaining amount needed
                uint256 amountToSell = Math.min(tokenValue, remainingAmount);
                
                if (amountToSell > 0) {
                    uint256 received = _executeTokenSale(token, amountToSell);
                    remainingAmount = received >= remainingAmount ? 0 : remainingAmount - received;
                }
            }
        }
        
        return remainingAmount;
    }
    
    /**
     * @dev Executes a token sale with proper error handling
     * @param token The token to sell
     * @param amountToSell The amount to sell in asset terms
     * @return received The amount of asset tokens received
     */
    function _executeTokenSale(address token, uint256 amountToSell) internal returns (uint256) {
        // Explicitly approve the DEX to spend this token
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        uint256 allowance = IERC20(token).allowance(address(this), address(dex));
        
        if (allowance < tokenBalance) {
            // Reset approval to 0 first (some tokens require this)
            if (allowance > 0) {
                IERC20(token).approve(address(dex), 0);
            }
            // Approve the DEX to spend the token - approve the full balance
            IERC20(token).approve(address(dex), tokenBalance);
        }
        
        // Calculate token amount to sell
        uint256 tokenAmountToSell = priceOracle.convertFromBaseAsset(token, amountToSell);
        tokenAmountToSell = Math.min(tokenAmountToSell, tokenBalance);
        
        if (tokenAmountToSell == 0) return 0;
        
        // Get expected amount of asset token
        uint256 expectedAssetAmount = dex.getExpectedAmount(token, asset(), tokenAmountToSell);
        
        if (expectedAssetAmount == 0) return 0;
        
        // Execute the swap with a 5% slippage tolerance
        uint256 minAmount = expectedAssetAmount * 95 / 100;
        
        try dex.swap(token, asset(), tokenAmountToSell, minAmount) returns (uint256 received) {
            return received;
        } catch {
            // If the swap fails with the full amount, try with half the amount
            uint256 halfAmount = tokenAmountToSell / 2;
            if (halfAmount > 0) {
                try dex.swap(token, asset(), halfAmount, 0) returns (uint256 received) {
                    return received;
                } catch {
                    // If it still fails with half the amount, try with a quarter
                    uint256 quarterAmount = halfAmount / 2;
                    if (quarterAmount > 0) {
                        try dex.swap(token, asset(), quarterAmount, 0) returns (uint256 received) {
                            return received;
                        } catch {
                            // If all attempts fail, return 0
                            return 0;
                        }
                    }
                }
            }
        }
        
        return 0;
    }

    /**
     * @dev Returns the total assets managed by the vault
     * This includes the underlying asset and all tokens in the index
     * @return The total assets in the vault's asset terms
     */
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        // Get the balance of the underlying asset
        uint256 assetBalance = IERC20(asset()).balanceOf(address(this));
        
        // Add the value of all tokens in the index
        (address[] memory tokens, ) = indexRegistry.getCurrentIndex();
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            assetBalance += _getTokenValue(token, tokenBalance);
        }
        
        return assetBalance;
    }

    /**
     * @dev Hook that is called before any deposit operation
     * @param assets The amount of assets to deposit
     * @param receiver The address receiving the shares
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        super._deposit(caller, receiver, assets, shares);
        
        // Check if rebalancing is needed after deposit
        if (isRebalancingNeeded() && block.timestamp >= lastRebalanceTimestamp + 1 days) {
            // Don't rebalance too frequently, at least 1 day between rebalances
            // This is to prevent front-running attacks
        }
    }

    /**
     * @dev Hook that is called before any withdrawal operation
     * @param assets The amount of assets to withdraw
     * @param receiver The address receiving the assets
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        // Ensure we have enough liquid assets for withdrawal
        _ensureLiquidity(assets);
        
        super._withdraw(caller, receiver, owner, assets, shares);
        
        // Check if rebalancing is needed after withdrawal
        if (isRebalancingNeeded() && block.timestamp >= lastRebalanceTimestamp + 1 days) {
            // Don't rebalance too frequently, at least 1 day between rebalances
        }
    }

    /**
     * @dev Returns the current index composition
     * @return tokens Array of token addresses
     * @return weights Array of token weights in basis points
     */
    function getCurrentIndex() external view returns (address[] memory tokens, uint256[] memory weights) {
        return indexRegistry.getCurrentIndex();
    }
    
    /**
     * @dev Override the conversion function to make share price more intuitive.
     * This directly controls the initial share price to be around TARGET_SHARE_PRICE.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAssetAmount = totalAssets();
        
        if (supply == 0 || totalAssetAmount == 0) {
            // For the first deposit, set the share price to TARGET_SHARE_PRICE
            // This means 100 USDC = 1 share
            return assets / TARGET_SHARE_PRICE;
        }
        
        // For subsequent deposits, use the standard formula
        return assets.mulDiv(supply, totalAssetAmount, rounding);
    }
    
    /**
     * @dev Override the conversion function to make share price more intuitive.
     * This is the inverse of _convertToShares.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAssetAmount = totalAssets();
        
        if (supply == 0 || totalAssetAmount == 0) {
            // For the first withdrawal (unlikely), maintain the TARGET_SHARE_PRICE
            return shares * TARGET_SHARE_PRICE;
        }
        
        // For subsequent withdrawals, use the standard formula
        return shares.mulDiv(totalAssetAmount, supply, rounding);
    }
}
