// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseVault} from "./BaseVault.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";
import {IAssetWrapper} from "./interfaces/IAssetWrapper.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IDEX} from "./interfaces/IDEX.sol";

/**
 * @title IndexFundVaultV2
 * @dev An ERC4626-compliant vault that implements a web3 index fund
 * with support for various asset types through the IAssetWrapper interface.
 * This allows RWAs and other complex assets to be treated uniformly.
 */
contract IndexFundVaultV2 is BaseVault {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    // Struct to hold asset information
    struct AssetInfo {
        IAssetWrapper wrapper;
        uint256 weight; // Weight in basis points (e.g., 2000 = 20%)
        bool active;
    }
    
    // Make the struct public so it can be accessed in tests
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points
    
    // Asset registry
    address[] public assetList;
    mapping(address => AssetInfo) public assets;
    
    // Price oracle and DEX
    IPriceOracle public priceOracle;
    IDEX public dex;
    
    // Minimum time between rebalances
    uint256 public rebalanceInterval = 1 days;
    uint256 public lastRebalance;
    
    // Rebalance threshold in basis points (e.g., 500 = 5%)
    uint256 public rebalanceThreshold = 500;
    
    // Events
    event AssetAdded(address indexed assetAddress, uint256 weight);
    event AssetRemoved(address indexed assetAddress);
    event AssetWeightUpdated(address indexed assetAddress, uint256 oldWeight, uint256 newWeight);
    event Rebalanced();
    event RebalanceIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event RebalanceThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PriceOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DEXUpdated(address indexed oldDEX, address indexed newDEX);
    
    /**
     * @dev Get information about an asset
     * @param assetAddress The address of the asset wrapper
     * @return wrapper The address of the asset wrapper
     * @return weight The weight of the asset in basis points
     * @return active Whether the asset is active
     */
    function getAssetInfo(address assetAddress) external view returns (address wrapper, uint256 weight, bool active) {
        AssetInfo memory info = assets[assetAddress];
        return (address(info.wrapper), info.weight, info.active);
    }
    
    /**
     * @dev Constructor that initializes the vault with the asset token and dependencies
     * @param asset_ The underlying asset token (typically a stablecoin)
     * @param feeManager_ The fee manager contract address
     * @param priceOracle_ The price oracle contract address
     * @param dex_ The DEX contract address
     */
    constructor(
        IERC20 asset_,
        IFeeManager feeManager_,
        IPriceOracle priceOracle_,
        IDEX dex_
    ) 
        BaseVault(asset_, feeManager_)
    {
        if (address(priceOracle_) == address(0)) revert CommonErrors.ZeroAddress();
        if (address(dex_) == address(0)) revert CommonErrors.ZeroAddress();
        
        priceOracle = priceOracle_;
        dex = dex_;
        lastRebalance = block.timestamp;
    }
    
    /**
     * @dev Add a new asset to the index
     * @param assetAddress The address of the asset wrapper
     * @param weight The weight of the asset in basis points
     */
    function addAsset(address assetAddress, uint256 weight) external onlyOwner {
        if (assetAddress == address(0)) revert CommonErrors.ZeroAddress();
        if (weight == 0) revert CommonErrors.ValueTooLow();
        if (assets[assetAddress].active) revert CommonErrors.TokenAlreadyExists();
        
        // Validate the asset wrapper
        IAssetWrapper wrapper = IAssetWrapper(assetAddress);
        if (wrapper.getBaseAsset() != address(asset())) revert CommonErrors.InvalidValue();
        
        // Update total weight and ensure it doesn't exceed 100%
        uint256 totalWeight = getTotalWeight();
        if (totalWeight + weight > BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        // Add the asset to the registry
        assets[assetAddress] = AssetInfo({
            wrapper: wrapper,
            weight: weight,
            active: true
        });
        
        assetList.push(assetAddress);
        
        emit AssetAdded(assetAddress, weight);
    }
    
    /**
     * @dev Remove an asset from the index
     * @param assetAddress The address of the asset wrapper to remove
     */
    function removeAsset(address assetAddress) external onlyOwner {
        if (!assets[assetAddress].active) revert CommonErrors.TokenNotFound();
        
        // Withdraw all capital from the asset wrapper
        IAssetWrapper wrapper = assets[assetAddress].wrapper;
        uint256 assetValue = wrapper.getValueInBaseAsset();
        
        if (assetValue > 0) {
            wrapper.withdrawCapital(assetValue);
        }
        
        // Mark the asset as inactive
        assets[assetAddress].active = false;
        assets[assetAddress].weight = 0;
        
        // Remove from assetList
        for (uint256 i = 0; i < assetList.length; i++) {
            if (assetList[i] == assetAddress) {
                assetList[i] = assetList[assetList.length - 1];
                assetList.pop();
                break;
            }
        }
        
        emit AssetRemoved(assetAddress);
    }
    
    /**
     * @dev Update the weight of an asset in the index
     * @param assetAddress The address of the asset wrapper
     * @param newWeight The new weight in basis points
     */
    function updateAssetWeight(address assetAddress, uint256 newWeight) external onlyOwner {
        if (!assets[assetAddress].active) revert CommonErrors.TokenNotFound();
        if (newWeight == 0) revert CommonErrors.ValueTooLow();
        
        uint256 oldWeight = assets[assetAddress].weight;
        
        // Calculate new total weight
        uint256 totalWeight = getTotalWeight() - oldWeight + newWeight;
        if (totalWeight > BASIS_POINTS) revert CommonErrors.TotalExceeds100Percent();
        
        // Update the weight
        assets[assetAddress].weight = newWeight;
        
        emit AssetWeightUpdated(assetAddress, oldWeight, newWeight);
    }
    
    /**
     * @dev Rebalance the assets according to their target weights
     */
    function rebalance() external nonReentrant {
        if (paused()) revert CommonErrors.OperationPaused();
        
        // Check if enough time has passed since the last rebalance
        if (block.timestamp < lastRebalance + rebalanceInterval) {
            // Allow rebalancing if the deviation exceeds the threshold
            if (!isRebalanceNeeded()) revert CommonErrors.TooEarly();
        }
        
        // Collect fees before rebalancing
        collectFees();
        
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return;
        
        // Calculate target allocations
        for (uint256 i = 0; i < assetList.length; i++) {
            address assetAddress = assetList[i];
            AssetInfo storage assetInfo = assets[assetAddress];
            
            if (!assetInfo.active) continue;
            
            uint256 targetValue = (totalValue * assetInfo.weight) / BASIS_POINTS;
            uint256 currentValue = assetInfo.wrapper.getValueInBaseAsset();
            
            if (currentValue < targetValue) {
                // Need to allocate more to this asset
                uint256 amountToAllocate = targetValue - currentValue;
                
                // Ensure we have enough base asset
                uint256 baseAssetBalance = IERC20(asset()).balanceOf(address(this));
                if (baseAssetBalance < amountToAllocate) {
                    // Withdraw from other assets
                    _withdrawFromOtherAssets(assetAddress, amountToAllocate - baseAssetBalance);
                }
                
                // Allocate to the asset
                IERC20(asset()).approve(assetAddress, amountToAllocate);
                assetInfo.wrapper.allocateCapital(amountToAllocate);
            } else if (currentValue > targetValue) {
                // Need to withdraw from this asset
                uint256 amountToWithdraw = currentValue - targetValue;
                assetInfo.wrapper.withdrawCapital(amountToWithdraw);
            }
        }
        
        lastRebalance = block.timestamp;
        emit Rebalanced();
    }
    
    /**
     * @dev Check if rebalance is needed based on deviation from target weights
     * @return needed Whether rebalance is needed
     */
    function isRebalanceNeeded() public view returns (bool) {
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return false;
        
        for (uint256 i = 0; i < assetList.length; i++) {
            address assetAddress = assetList[i];
            AssetInfo storage assetInfo = assets[assetAddress];
            
            if (!assetInfo.active) continue;
            
            uint256 targetValue = (totalValue * assetInfo.weight) / BASIS_POINTS;
            uint256 currentValue = assetInfo.wrapper.getValueInBaseAsset();
            
            // Calculate deviation in basis points
            uint256 deviation;
            if (currentValue > targetValue) {
                deviation = ((currentValue - targetValue) * BASIS_POINTS) / targetValue;
            } else {
                deviation = ((targetValue - currentValue) * BASIS_POINTS) / targetValue;
            }
            
            // If any asset deviates more than the threshold, rebalance is needed
            if (deviation > rebalanceThreshold) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Set the rebalance interval
     * @param interval The new interval in seconds
     */
    function setRebalanceInterval(uint256 interval) external onlyOwner {
        uint256 oldInterval = rebalanceInterval;
        rebalanceInterval = interval;
        
        emit RebalanceIntervalUpdated(oldInterval, interval);
    }
    
    /**
     * @dev Set the rebalance threshold
     * @param threshold The new threshold in basis points
     */
    function setRebalanceThreshold(uint256 threshold) external onlyOwner {
        if (threshold > BASIS_POINTS) revert CommonErrors.ValueTooHigh();
        
        uint256 oldThreshold = rebalanceThreshold;
        rebalanceThreshold = threshold;
        
        emit RebalanceThresholdUpdated(oldThreshold, threshold);
    }
    
    /**
     * @dev Update the price oracle
     * @param newPriceOracle The new price oracle address
     */
    function updatePriceOracle(IPriceOracle newPriceOracle) external onlyOwner {
        if (address(newPriceOracle) == address(0)) revert CommonErrors.ZeroAddress();
        
        address oldPriceOracle = address(priceOracle);
        priceOracle = newPriceOracle;
        
        emit PriceOracleUpdated(oldPriceOracle, address(newPriceOracle));
    }
    
    /**
     * @dev Update the DEX
     * @param newDEX The new DEX address
     */
    function updateDEX(IDEX newDEX) external onlyOwner {
        if (address(newDEX) == address(0)) revert CommonErrors.ZeroAddress();
        
        address oldDEX = address(dex);
        dex = newDEX;
        
        emit DEXUpdated(oldDEX, address(newDEX));
    }
    
    /**
     * @dev Get the total weight of all active assets
     * @return totalWeight The total weight in basis points
     */
    function getTotalWeight() public view returns (uint256 totalWeight) {
        for (uint256 i = 0; i < assetList.length; i++) {
            if (assets[assetList[i]].active) {
                totalWeight += assets[assetList[i]].weight;
            }
        }
        return totalWeight;
    }
    
    /**
     * @dev Get all active assets
     * @return activeAssets Array of active asset addresses
     */
    function getActiveAssets() external view returns (address[] memory activeAssets) {
        uint256 activeCount = 0;
        
        // Count active assets
        for (uint256 i = 0; i < assetList.length; i++) {
            if (assets[assetList[i]].active) {
                activeCount++;
            }
        }
        
        // Create array of active assets
        activeAssets = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < assetList.length; i++) {
            if (assets[assetList[i]].active) {
                activeAssets[index] = assetList[i];
                index++;
            }
        }
        
        return activeAssets;
    }
    
    /**
     * @dev Calculate the total assets in the vault
     * This includes the base asset balance and the value of all asset wrappers
     */
    function totalAssets() public view override returns (uint256) {
        // Start with the base asset balance
        uint256 total = IERC20(asset()).balanceOf(address(this));
        
        // Add the value of all asset wrappers
        for (uint256 i = 0; i < assetList.length; i++) {
            address assetAddress = assetList[i];
            if (assets[assetAddress].active) {
                total += assets[assetAddress].wrapper.getValueInBaseAsset();
            }
        }
        
        return total;
    }
    
    /**
     * @dev Withdraw from other assets to rebalance
     * @param excludeAsset Asset to exclude from withdrawal
     * @param amount Amount to withdraw
     */
    function _withdrawFromOtherAssets(address excludeAsset, uint256 amount) internal {
        uint256 remaining = amount;
        
        // Calculate total value of other assets
        uint256 totalOtherValue = 0;
        for (uint256 i = 0; i < assetList.length; i++) {
            address assetAddress = assetList[i];
            if (assetAddress != excludeAsset && assets[assetAddress].active) {
                totalOtherValue += assets[assetAddress].wrapper.getValueInBaseAsset();
            }
        }
        
        if (totalOtherValue == 0) return;
        
        // Withdraw proportionally from other assets
        for (uint256 i = 0; i < assetList.length; i++) {
            address assetAddress = assetList[i];
            if (assetAddress != excludeAsset && assets[assetAddress].active) {
                uint256 assetValue = assets[assetAddress].wrapper.getValueInBaseAsset();
                uint256 withdrawAmount = (remaining * assetValue) / totalOtherValue;
                
                if (withdrawAmount > 0) {
                    assets[assetAddress].wrapper.withdrawCapital(withdrawAmount);
                }
            }
        }
    }
    
    /**
     * @dev Harvest yield from all asset wrappers
     * @return totalHarvested The total amount harvested
     */
    function harvestYield() external nonReentrant returns (uint256 totalHarvested) {
        if (paused()) revert CommonErrors.OperationPaused();
        
        for (uint256 i = 0; i < assetList.length; i++) {
            address assetAddress = assetList[i];
            if (assets[assetAddress].active) {
                totalHarvested += assets[assetAddress].wrapper.harvestYield();
            }
        }
        
        return totalHarvested;
    }
}
