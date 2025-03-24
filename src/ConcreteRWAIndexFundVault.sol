// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RWAIndexFundVault} from "./RWAIndexFundVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IDEX} from "./interfaces/IDEX.sol";
import {ICapitalAllocationManager} from "./interfaces/ICapitalAllocationManager.sol";

/**
 * @title ConcreteRWAIndexFundVault
 * @dev Concrete implementation of the RWAIndexFundVault abstract contract
 */
contract ConcreteRWAIndexFundVault is RWAIndexFundVault {
    /**
     * @dev Constructor that initializes the vault with the asset token and a name
     * @param asset_ The underlying asset token (typically a stablecoin)
     * @param registry_ The index registry contract address
     * @param oracle_ The price oracle contract address
     * @param dex_ The DEX contract address
     * @param capitalManager_ The capital allocation manager contract address
     */
    constructor(
        IERC20 asset_,
        IIndexRegistry registry_,
        IPriceOracle oracle_,
        IDEX dex_,
        ICapitalAllocationManager capitalManager_
    ) 
        RWAIndexFundVault(
            asset_,
            registry_,
            oracle_,
            dex_,
            capitalManager_
        )
    {}

    /**
     * @dev Collects management and performance fees
     */
    function _collectFees() internal override {
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return;
        
        // Calculate management fee (annual fee prorated by time since last collection)
        uint256 timeSinceLastCollection = block.timestamp - lastRebalanceTimestamp;
        uint256 managementFee = (totalValue * managementFeePercentage * timeSinceLastCollection) / (BASIS_POINTS * 365 days);
        
        // Calculate performance fee if current value exceeds high watermark
        uint256 performanceFee = 0;
        if (totalValue > highWaterMark && highWaterMark > 0) {
            uint256 gain = totalValue - highWaterMark;
            performanceFee = (gain * performanceFeePercentage) / BASIS_POINTS;
            highWaterMark = totalValue - performanceFee; // Update high watermark
        } else if (highWaterMark == 0) {
            // Initialize high watermark on first collection
            highWaterMark = totalValue;
        }
        
        uint256 totalFee = managementFee + performanceFee;
        if (totalFee == 0) return;
        
        // Convert fee to shares and mint to owner
        uint256 feeShares = convertToShares(totalFee);
        _mint(owner(), feeShares);
        
        if (managementFee > 0) {
            emit ManagementFeeCollected(managementFee);
        }
        
        if (performanceFee > 0) {
            emit PerformanceFeeCollected(performanceFee);
        }
    }

    /**
     * @dev Gets the value of a token in asset terms
     * @param token The token address
     * @param amount The token amount
     * @return value The value in asset terms
     */
    function _getTokenValue(address token, uint256 amount) internal view override returns (uint256 value) {
        if (amount == 0) return 0;
        
        if (token == address(asset())) {
            return amount;
        }
        
        return priceOracle.convertToBaseAsset(token, amount);
    }
}
