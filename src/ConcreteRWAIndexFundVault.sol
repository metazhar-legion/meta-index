// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RWAIndexFundVault} from "./RWAIndexFundVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IDEX} from "./interfaces/IDEX.sol";
import {ICapitalAllocationManager} from "./interfaces/ICapitalAllocationManager.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

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
        RWAIndexFundVault(
            asset_,
            registry_,
            oracle_,
            dex_,
            capitalManager_,
            feeManager_
        )
    {}

    /**
     * @dev Collects management and performance fees using the fee manager
     */
    function _collectFees() internal override {
        uint256 totalValue = totalAssets();
        if (totalValue == 0) return;
        
        // Use fee manager to calculate fees
        uint256 managementFee = feeManager.calculateManagementFee(
            address(this),
            totalValue,
            block.timestamp
        );
        
        // Calculate performance fee using the fee manager
        uint256 currentSharePrice = convertToAssets(10**decimals());
        uint256 performanceFee = feeManager.calculatePerformanceFee(
            address(this),
            currentSharePrice,
            totalSupply(),
            decimals()
        );
        
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
