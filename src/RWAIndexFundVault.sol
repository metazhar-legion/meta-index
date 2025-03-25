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
import {ICapitalAllocationManager} from "./interfaces/ICapitalAllocationManager.sol";
import {IRWASyntheticToken} from "./interfaces/IRWASyntheticToken.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/**
 * @title RWAIndexFundVault
 * @dev An extended ERC4626-compliant vault that implements a web3 index fund
 * with support for Real World Assets (RWAs) and yield strategies.
 * The vault allocates 20% of capital to RWAs backed by perpetuals and 
 * 80% to stable yield strategies.
 */
abstract contract RWAIndexFundVault is ERC4626, Ownable, ReentrancyGuard, IIndexFundVault {
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
    
    // Capital allocation manager
    ICapitalAllocationManager public capitalAllocationManager;
    
    // Fee manager
    IFeeManager public feeManager;
    
    // Rebalancing settings
    uint256 public rebalancingInterval = 7 days;
    uint256 public lastRebalanceTimestamp;
    uint256 public rebalancingThreshold = 5; // 5% deviation triggers rebalance
    
    uint256 public constant BASIS_POINTS = 10000;
    
    // Events
    event Rebalanced(uint256 timestamp);
    event IndexRegistryUpdated(address indexed newRegistry);
    event PriceOracleUpdated(address indexed newOracle);
    event DEXUpdated(address indexed newDex);
    event CapitalAllocationManagerUpdated(address indexed newManager);
    event ManagementFeeCollected(uint256 amount);
    event PerformanceFeeCollected(uint256 amount);
    event RebalancingIntervalUpdated(uint256 newInterval);
    event RebalancingThresholdUpdated(uint256 newThreshold);
    event FeeManagerUpdated(address indexed newFeeManager);
    event RWAAdded(address indexed rwaToken);
    event RWARemoved(address indexed rwaToken);
    event YieldStrategyAdded(address indexed strategy);
    event YieldStrategyRemoved(address indexed strategy);
    
    /**
     * @dev Constructor that initializes the vault with the asset token and a name
     * @param asset_ The underlying asset token (typically a stablecoin)
     * @param registry_ The index registry contract address
     * @param oracle_ The price oracle contract address
     * @param dex_ The DEX contract address
     * @param capitalManager_ The capital allocation manager contract address
     * @param feeManager_ The fee manager contract address
     */
    constructor(
        IERC20 asset_,
        IIndexRegistry registry_,
        IPriceOracle oracle_,
        IDEX dex_,
        ICapitalAllocationManager capitalManager_,
        IFeeManager feeManager_
    ) 
        ERC4626(asset_)
        ERC20(
            string(abi.encodePacked("RWA Index Fund Vault ", ERC20(address(asset_)).name())),
            string(abi.encodePacked("rwa", ERC20(address(asset_)).symbol()))
        )
        Ownable(msg.sender)
    {
        indexRegistry = registry_;
        priceOracle = oracle_;
        dex = dex_;
        capitalAllocationManager = capitalManager_;
        feeManager = feeManager_;
        lastRebalanceTimestamp = block.timestamp;
        
        // Initialize fee collection timestamp in the fee manager
        feeManager.setLastFeeCollectionTimestamp(address(this), block.timestamp);
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
     * @dev Updates the price oracle address
     * @param newOracle The new oracle contract address
     */
    function setPriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Zero address");
        priceOracle = IPriceOracle(newOracle);
        emit PriceOracleUpdated(newOracle);
    }
    
    /**
     * @dev Updates the DEX address
     * @param newDex The new DEX contract address
     */
    function setDEX(address newDex) external onlyOwner {
        require(newDex != address(0), "Zero address");
        dex = IDEX(newDex);
        emit DEXUpdated(newDex);
    }
    
    /**
     * @dev Updates the capital allocation manager address
     * @param newManager The new capital allocation manager contract address
     */
    function setCapitalAllocationManager(ICapitalAllocationManager newManager) external onlyOwner {
        require(address(newManager) != address(0), "Invalid manager address");
        capitalAllocationManager = newManager;
        emit CapitalAllocationManagerUpdated(address(newManager));
    }
    
    /**
     * @dev Updates the rebalancing interval
     * @param newInterval The new interval in seconds
     */
    function setRebalancingInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Invalid interval");
        rebalancingInterval = newInterval;
        emit RebalancingIntervalUpdated(newInterval);
    }
    
    /**
     * @dev Updates the rebalancing threshold
     * @param newThreshold The new threshold in percentage points
     */
    function setRebalancingThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= 50, "Invalid threshold");
        rebalancingThreshold = newThreshold;
        emit RebalancingThresholdUpdated(newThreshold);
    }
    
    /**
     * @dev Updates the fee manager address
     * @param newFeeManager The new fee manager contract address
     */
    function setFeeManager(IFeeManager newFeeManager) external onlyOwner {
        require(address(newFeeManager) != address(0), "Invalid fee manager address");
        feeManager = newFeeManager;
        emit FeeManagerUpdated(address(newFeeManager));
    }
    
    /**
     * @dev Proxy function to set management fee percentage on the fee manager
     * @param newFee The new fee in basis points
     */
    function setManagementFeePercentage(uint256 newFee) external onlyOwner {
        feeManager.setManagementFeePercentage(newFee);
    }
    
    /**
     * @dev Proxy function to set performance fee percentage on the fee manager
     * @param newFee The new fee in basis points
     */
    function setPerformanceFeePercentage(uint256 newFee) external onlyOwner {
        feeManager.setPerformanceFeePercentage(newFee);
    }
    
    /**
     * @dev Adds a new RWA token to the capital allocation manager
     * @param rwaToken The RWA token address
     * @param percentage The allocation percentage within the RWA portion
     */
    function addRWAToken(address rwaToken, uint256 percentage) external onlyOwner {
        require(rwaToken != address(0), "Invalid RWA token address");
        require(percentage > 0 && percentage <= BASIS_POINTS, "Invalid percentage");
        
        capitalAllocationManager.addRWAToken(rwaToken, percentage);
        
        emit RWAAdded(rwaToken);
    }
    
    /**
     * @dev Removes an RWA token from the capital allocation manager
     * @param rwaToken The RWA token address
     */
    function removeRWAToken(address rwaToken) external onlyOwner {
        require(rwaToken != address(0), "Invalid RWA token address");
        
        capitalAllocationManager.removeRWAToken(rwaToken);
        
        emit RWARemoved(rwaToken);
    }
    
    /**
     * @dev Adds a new yield strategy to the capital allocation manager
     * @param strategy The yield strategy address
     * @param percentage The allocation percentage within the yield portion
     */
    function addYieldStrategy(address strategy, uint256 percentage) external onlyOwner {
        require(strategy != address(0), "Invalid strategy address");
        require(percentage > 0 && percentage <= BASIS_POINTS, "Invalid percentage");
        
        capitalAllocationManager.addYieldStrategy(strategy, percentage);
        
        emit YieldStrategyAdded(strategy);
    }
    
    /**
     * @dev Removes a yield strategy from the capital allocation manager
     * @param strategy The yield strategy address
     */
    function removeYieldStrategy(address strategy) external onlyOwner {
        require(strategy != address(0), "Invalid strategy address");
        
        capitalAllocationManager.removeYieldStrategy(strategy);
        
        emit YieldStrategyRemoved(strategy);
    }
    
    /**
     * @dev Sets the overall capital allocation percentages
     * @param rwaPercentage Percentage for RWA synthetics
     * @param yieldPercentage Percentage for yield strategies
     * @param liquidityBufferPercentage Percentage for liquidity buffer
     */
    function setCapitalAllocation(
        uint256 rwaPercentage,
        uint256 yieldPercentage,
        uint256 liquidityBufferPercentage
    ) external onlyOwner {
        require(rwaPercentage + yieldPercentage + liquidityBufferPercentage == BASIS_POINTS, 
                "Percentages must sum to 100%");
        
        capitalAllocationManager.setAllocation(
            rwaPercentage,
            yieldPercentage,
            liquidityBufferPercentage
        );
    }
    
    /**
     * @dev Rebalances the capital allocation
     */
    function rebalanceCapitalAllocation() external {
        require(
            block.timestamp >= lastRebalanceTimestamp + rebalancingInterval ||
            _isRebalancingNeeded(),
            "Rebalancing not needed"
        );
        
        // Collect fees before rebalancing
        _collectFees();
        
        // Rebalance the capital allocation
        capitalAllocationManager.rebalance();
        
        // Update the rebalance timestamp
        lastRebalanceTimestamp = block.timestamp;
        
        emit Rebalanced(block.timestamp);
    }
    
    /**
     * @dev Rebalances the index fund according to the current index composition
     * This function can be called by anyone, but only after the rebalancing interval
     * has passed or if the deviation exceeds the threshold
     */
    function rebalance() external override {
        require(
            block.timestamp >= lastRebalanceTimestamp + rebalancingInterval ||
            _isRebalancingNeeded(),
            "Rebalancing not needed"
        );
        
        // Collect fees before rebalancing
        _collectFees();
        
        // Get the current index composition
        (address[] memory tokens, uint256[] memory weights) = indexRegistry.getCurrentIndex();
        require(tokens.length > 0, "Empty index");
        require(tokens.length == weights.length, "Mismatched arrays");
        
        // Calculate the total assets to allocate to the index (excluding RWA and yield allocations)
        // uint256 totalAssetsValue = totalAssets();
        
        // Get capital allocation
        ICapitalAllocationManager.Allocation memory allocation = capitalAllocationManager.getAllocation();
        
        // Calculate the amount to allocate to the index (remaining after RWA and yield allocations)
        uint256 indexAllocation = (totalAssets() * (BASIS_POINTS - allocation.rwaPercentage - allocation.yieldPercentage - allocation.liquidityBufferPercentage)) / BASIS_POINTS;
        
        // Rebalance the index portion
        _rebalanceIndex(tokens, weights, indexAllocation);
        
        // Rebalance the capital allocation
        capitalAllocationManager.rebalance();
        
        // Update the rebalance timestamp
        lastRebalanceTimestamp = block.timestamp;
        
        emit Rebalanced(block.timestamp);
    }
    
    /**
     * @dev Internal function to rebalance the index portion
     * @param tokens Array of token addresses
     * @param weights Array of token weights
     * @param totalAllocation Total amount to allocate to the index
     */
    function _rebalanceIndex(
        address[] memory tokens,
        uint256[] memory weights,
        uint256 totalAllocation
    ) internal {
        // Calculate target amounts for each token
        uint256[] memory targetAmounts = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            targetAmounts[i] = (totalAllocation * weights[i]) / BASIS_POINTS;
        }
        
        // Adjust positions to match target amounts
        for (uint256 i = 0; i < tokens.length; i++) {
            _adjustPosition(tokens[i], targetAmounts[i]);
        }
    }
    
    /**
     * @dev Adjusts the position of a token to match the target amount
     * @param token The token address
     * @param targetAmount The target amount in asset terms
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
     * @dev Buys a token with the specified amount
     * @param token The token to buy
     * @param amountToBuy The amount to buy in asset terms
     */
    function _buyToken(address token, uint256 amountToBuy) internal {
        if (amountToBuy == 0) return;
        
        // Check if we have enough of the asset token
        uint256 assetBalance = IERC20(asset()).balanceOf(address(this));
        
        if (assetBalance < amountToBuy) {
            // Not enough assets, need to withdraw from yield strategies or sell RWAs
            uint256 amountNeeded = amountToBuy - assetBalance;
            _ensureLiquidity(amountNeeded);
        }
        
        // Buy the token
        IERC20(asset()).approve(address(dex), amountToBuy);
        
        try dex.swapExactInput(
            asset(),
            token,
            amountToBuy,
            0 // Min amount out (should use a real value in production)
        ) returns (uint256 /* amountOut */) {
            // Success
        } catch {
            // Handle failure
            // In production, you would want to implement proper error handling
        }
    }
    
    /**
     * @dev Sells a token for the specified amount
     * @param token The token to sell
     * @param amountToSell The amount to sell in asset terms
     * @return received The amount of asset tokens received
     */
    function _sellToken(address token, uint256 amountToSell) internal returns (uint256 received) {
        if (amountToSell == 0) return 0;
        
        // Calculate how many tokens to sell
        uint256 tokenPrice = priceOracle.getPrice(token);
        uint256 assetPrice = priceOracle.getPrice(asset());
        
        uint256 tokenAmount = (amountToSell * assetPrice) / tokenPrice;
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        
        if (tokenAmount > tokenBalance) {
            tokenAmount = tokenBalance;
        }
        
        if (tokenAmount == 0) return 0;
        
        // Approve the DEX to spend our tokens
        IERC20(token).approve(address(dex), tokenAmount);
        
        // Execute the swap
        try dex.swapExactInput(
            token,
            asset(),
            tokenAmount,
            0 // Min amount out (should use a real value in production)
        ) returns (uint256 amountOut) {
            return amountOut;
        } catch {
            // Handle failure
            return 0;
        }
    }
    
    /**
     * @dev Ensures there is enough liquidity for a withdrawal or purchase
     * @param assets The amount of assets needed
     */
    function _ensureLiquidity(uint256 assets) internal {
        uint256 assetBalance = IERC20(asset()).balanceOf(address(this));
        
        if (assetBalance < assets) {
            // Need to get more liquidity
            uint256 amountNeeded = assets - assetBalance;
            
            // First try to get liquidity from the capital allocation manager
            uint256 bufferValue = capitalAllocationManager.getLiquidityBufferValue();
            
            if (bufferValue >= amountNeeded) {
                // We have enough in the buffer, no need to sell anything
                return;
            }
            
            // If buffer is not enough, we need to withdraw from yield strategies or sell RWAs
            // This is a simplified implementation; in production, you would want to implement
            // a more sophisticated strategy for maintaining liquidity
            
            // For now, we'll just rebalance the capital allocation
            capitalAllocationManager.rebalance();
        }
    }
    
    /**
     * @dev Collects management and performance fees using the fee manager
     */
    function _collectFees() internal virtual {
        // Calculate management fee
        uint256 totalAssetsValue = totalAssets();
        uint256 managementFee = feeManager.calculateManagementFee(
            address(this),
            totalAssetsValue,
            block.timestamp
        );
        
        if (managementFee > 0) {
            // Mint shares to the owner as management fee
            _mint(owner(), convertToShares(managementFee));
            emit ManagementFeeCollected(managementFee);
        }
        
        // Calculate performance fee
        uint256 currentSharePrice = convertToAssets(10**decimals());
        uint256 performanceFee = feeManager.calculatePerformanceFee(
            address(this),
            currentSharePrice,
            totalSupply(),
            decimals()
        );
        
        if (performanceFee > 0) {
            // Mint shares to the owner as performance fee
            _mint(owner(), convertToShares(performanceFee));
            emit PerformanceFeeCollected(performanceFee);
        }
    }
    
    /**
     * @dev Checks if rebalancing is needed based on the deviation threshold
     * @return needed Whether rebalancing is needed
     */
    function _isRebalancingNeeded() internal view returns (bool needed) {
        // Get the current index composition
        (address[] memory tokens, uint256[] memory weights) = indexRegistry.getCurrentIndex();
        
        // Check if any token's current weight deviates from the target weight
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 currentBalance = IERC20(tokens[i]).balanceOf(address(this));
            uint256 currentValue = _getTokenValue(tokens[i], currentBalance);
            
            uint256 totalAssetsValue_ = totalAssets();
            if (totalAssetsValue_ == 0) return false;
            
            uint256 currentWeight = (currentValue * BASIS_POINTS) / totalAssetsValue_;
            uint256 targetWeight = weights[i];
            
            // Calculate the absolute deviation
            uint256 deviation;
            if (currentWeight > targetWeight) {
                deviation = currentWeight - targetWeight;
            } else {
                deviation = targetWeight - currentWeight;
            }
            
            // Check if the deviation exceeds the threshold
            if (deviation * 100 / targetWeight > rebalancingThreshold) {
                return true;
            }
        }
        
        // Check if the capital allocation needs rebalancing
        ICapitalAllocationManager.Allocation memory allocation = capitalAllocationManager.getAllocation();
        
        uint256 totalAssetsValue = totalAssets();
        if (totalAssetsValue == 0) return false;
        
        uint256 rwaValue = capitalAllocationManager.getRWAValue();
        uint256 yieldValue = capitalAllocationManager.getYieldValue();
        uint256 bufferValue = capitalAllocationManager.getLiquidityBufferValue();
        
        uint256 currentRwaPercentage = (rwaValue * BASIS_POINTS) / totalAssetsValue;
        uint256 currentYieldPercentage = (yieldValue * BASIS_POINTS) / totalAssetsValue;
        uint256 currentBufferPercentage = (bufferValue * BASIS_POINTS) / totalAssetsValue;
        
        // Check RWA deviation
        uint256 rwaDeviation;
        if (currentRwaPercentage > allocation.rwaPercentage) {
            rwaDeviation = currentRwaPercentage - allocation.rwaPercentage;
        } else {
            rwaDeviation = allocation.rwaPercentage - currentRwaPercentage;
        }
        
        if (rwaDeviation * 100 / allocation.rwaPercentage > rebalancingThreshold) {
            return true;
        }
        
        // Check yield deviation
        uint256 yieldDeviation;
        if (currentYieldPercentage > allocation.yieldPercentage) {
            yieldDeviation = currentYieldPercentage - allocation.yieldPercentage;
        } else {
            yieldDeviation = allocation.yieldPercentage - currentYieldPercentage;
        }
        
        if (yieldDeviation * 100 / allocation.yieldPercentage > rebalancingThreshold) {
            return true;
        }
        
        // Check buffer deviation
        uint256 bufferDeviation;
        if (currentBufferPercentage > allocation.liquidityBufferPercentage) {
            bufferDeviation = currentBufferPercentage - allocation.liquidityBufferPercentage;
        } else {
            bufferDeviation = allocation.liquidityBufferPercentage - currentBufferPercentage;
        }
        
        if (bufferDeviation * 100 / allocation.liquidityBufferPercentage > rebalancingThreshold) {
            return true;
        }
        
        return false;
    }
    
    /**
     * @dev Gets the value of a token in terms of the asset
     * @param token The token address
     * @param amount The token amount
     * @return value The value in asset terms
     */
    function _getTokenValue(address token, uint256 amount) internal view virtual returns (uint256 value) {
        if (amount == 0) return 0;
        
        uint256 tokenPrice = priceOracle.getPrice(token);
        uint256 assetPrice = priceOracle.getPrice(asset());
        
        return (amount * tokenPrice) / assetPrice;
    }
    
    /**
     * @dev Returns the total assets managed by the vault
     * @return totalManagedAssets The total assets in terms of the underlying asset
     */
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256 totalManagedAssets) {
        // Get the value of assets held directly by the vault
        uint256 directAssets = IERC20(asset()).balanceOf(address(this));
        
        // Get the value of assets managed by the capital allocation manager
        uint256 managedAssets = capitalAllocationManager.getTotalValue();
        
        // Get the value of index tokens held by the vault
        (address[] memory tokens, ) = indexRegistry.getCurrentIndex();
        uint256 indexValue = 0;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            indexValue += _getTokenValue(tokens[i], balance);
        }
        
        return directAssets + managedAssets + indexValue;
    }
    
    /**
     * @dev Returns the current index composition
     * @return tokens Array of token addresses
     * @return weights Array of token weights in basis points
     */
    function getIndexComposition() external view returns (address[] memory tokens, uint256[] memory weights) {
        return indexRegistry.getCurrentIndex();
    }
    
    /**
     * @dev Returns the current index composition (implementation of IIndexFundVault)
     * @return tokens Array of token addresses
     * @return weights Array of token weights in basis points
     */
    function getCurrentIndex() external view returns (address[] memory tokens, uint256[] memory weights) {
        return indexRegistry.getCurrentIndex();
    }
    
    /**
     * @dev Checks if rebalancing is needed based on the deviation threshold
     * @return bool True if rebalancing is needed
     */
    function isRebalancingNeeded() external view returns (bool) {
        // Get current token weights
        (address[] memory tokens, uint256[] memory targetWeights) = indexRegistry.getCurrentIndex();
        
        // Calculate current weights based on token balances
        uint256[] memory currentWeights = new uint256[](tokens.length);
        uint256 totalValue = totalAssets();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            uint256 tokenValue = _getTokenValue(tokens[i], balance);
            totalValue += tokenValue;
        }
        
        if (totalValue == 0) return false;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            uint256 tokenValue = _getTokenValue(tokens[i], balance);
            currentWeights[i] = (tokenValue * 10000) / totalValue;
            
            // Check if deviation exceeds threshold
            if (currentWeights[i] > targetWeights[i] && currentWeights[i] - targetWeights[i] > 0) {
                return true;
            }
            if (targetWeights[i] > currentWeights[i] && targetWeights[i] - currentWeights[i] > 0) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Sets the management fee percentage
     * @param newFee The new fee in basis points
     */
    function setManagementFee(uint256 newFee) external override onlyOwner {
        feeManager.setManagementFeePercentage(newFee);
    }
    
    /**
     * @dev Sets the performance fee percentage
     * @param newFee The new fee in basis points
     */
    function setPerformanceFee(uint256 newFee) external override onlyOwner {
        feeManager.setPerformanceFeePercentage(newFee);
    }
    
    /**
     * @dev Returns the current RWA tokens and their allocations
     * @return rwaTokens Array of RWA token allocations
     */
    function getRWATokens() external view returns (ICapitalAllocationManager.RWAAllocation[] memory rwaTokens) {
        return capitalAllocationManager.getRWATokens();
    }
    
    /**
     * @dev Returns the current yield strategies and their allocations
     * @return strategies Array of yield strategy allocations
     */
    function getYieldStrategies() external view returns (ICapitalAllocationManager.StrategyAllocation[] memory strategies) {
        return capitalAllocationManager.getYieldStrategies();
    }
    
    /**
     * @dev Returns the current capital allocation
     * @return allocation The current allocation
     */
    function getCapitalAllocation() external view returns (ICapitalAllocationManager.Allocation memory allocation) {
        return capitalAllocationManager.getAllocation();
    }
}
