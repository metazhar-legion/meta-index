// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IExposureStrategy
 * @dev Interface for composable RWA exposure strategies
 * @notice Enables different methods of gaining RWA exposure (perpetuals, TRS, direct tokens)
 */
interface IExposureStrategy {
    /**
     * @dev Enum for different types of exposure strategies
     */
    enum StrategyType {
        PERPETUAL,      // Perpetual futures/swaps
        TRS,           // Total Return Swaps
        DIRECT_TOKEN,  // Direct token purchases
        SYNTHETIC_TOKEN, // Synthetic token protocols
        OPTIONS        // Options-based strategies
    }

    /**
     * @dev Comprehensive information about the exposure strategy
     */
    struct ExposureInfo {
        StrategyType strategyType;
        string name;
        address underlyingAsset;    // The RWA being tracked (e.g., SP500)
        uint256 leverage;           // Current leverage (100 = 1x, 200 = 2x)
        uint256 collateralRatio;    // Required collateral as % of exposure (basis points)
        uint256 currentExposure;    // Current exposure amount in base asset terms
        uint256 maxCapacity;        // Maximum exposure this strategy can handle
        uint256 currentCost;        // Current cost in basis points per year
        uint256 riskScore;          // Risk score from 1-100 (higher = riskier)
        bool isActive;              // Whether strategy is currently active
        uint256 liquidationPrice;   // Price at which position gets liquidated (if applicable)
    }

    /**
     * @dev Detailed breakdown of all costs associated with the strategy
     */
    struct CostBreakdown {
        uint256 fundingRate;        // Funding rate for perpetuals (basis points/year)
        uint256 borrowRate;         // Borrow rate for TRS (basis points/year)
        uint256 managementFee;      // Protocol management fee (basis points/year)
        uint256 slippageCost;       // Estimated slippage cost (basis points)
        uint256 gasCost;           // Estimated gas cost in base asset terms
        uint256 totalCostBps;       // Total annualized cost (basis points/year)
        uint256 lastUpdated;        // Timestamp of last cost update
    }

    /**
     * @dev Parameters for risk management and position sizing
     */
    struct RiskParameters {
        uint256 maxLeverage;        // Maximum allowed leverage
        uint256 maxPositionSize;    // Maximum position size in base asset
        uint256 liquidationBuffer;  // Buffer before liquidation (basis points)
        uint256 rebalanceThreshold; // Threshold for rebalancing (basis points)
        uint256 slippageLimit;      // Maximum acceptable slippage (basis points)
        bool emergencyExitEnabled;  // Whether emergency exit is available
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets comprehensive information about this exposure strategy
     * @return info The exposure strategy information
     */
    function getExposureInfo() external view returns (ExposureInfo memory info);

    /**
     * @dev Gets detailed cost breakdown for the strategy
     * @return costs The cost breakdown
     */
    function getCostBreakdown() external view returns (CostBreakdown memory costs);

    /**
     * @dev Gets risk management parameters
     * @return params The risk parameters
     */
    function getRiskParameters() external view returns (RiskParameters memory params);

    /**
     * @dev Estimates the cost of opening/maintaining exposure for a given amount and time
     * @param amount The exposure amount in base asset terms
     * @param timeHorizon The time horizon in seconds
     * @return estimatedCost The estimated cost in base asset terms
     */
    function estimateExposureCost(uint256 amount, uint256 timeHorizon) external view returns (uint256 estimatedCost);

    /**
     * @dev Gets the current value of the exposure position
     * @return value Current exposure value in base asset terms
     */
    function getCurrentExposureValue() external view returns (uint256 value);

    /**
     * @dev Calculates collateral required for a given exposure amount
     * @param exposureAmount The desired exposure amount
     * @return collateralRequired The collateral required in base asset terms
     */
    function getCollateralRequired(uint256 exposureAmount) external view returns (uint256 collateralRequired);

    /**
     * @dev Gets the liquidation price for the current position (if applicable)
     * @return liquidationPrice The price at which liquidation occurs (0 if not applicable)
     */
    function getLiquidationPrice() external view returns (uint256 liquidationPrice);

    /**
     * @dev Checks if the strategy can handle a specific exposure amount
     * @param amount The exposure amount to check
     * @return canHandle Whether the strategy can handle this amount
     * @return reason Reason if cannot handle (empty if can handle)
     */
    function canHandleExposure(uint256 amount) external view returns (bool canHandle, string memory reason);

    // ============ STATE-CHANGING FUNCTIONS ============

    /**
     * @dev Opens exposure for a given amount
     * @param amount The base asset amount to use for exposure
     * @return success Whether the operation was successful
     * @return actualExposure The actual exposure amount achieved
     */
    function openExposure(uint256 amount) external returns (bool success, uint256 actualExposure);

    /**
     * @dev Closes exposure for a given amount
     * @param amount The exposure amount to close (in exposure terms, not base asset)
     * @return success Whether the operation was successful
     * @return actualClosed The actual exposure amount closed
     */
    function closeExposure(uint256 amount) external returns (bool success, uint256 actualClosed);

    /**
     * @dev Adjusts existing exposure by a delta amount
     * @param delta The change in exposure (positive to increase, negative to decrease)
     * @return success Whether the operation was successful
     * @return newExposure The new total exposure amount
     */
    function adjustExposure(int256 delta) external returns (bool success, uint256 newExposure);

    /**
     * @dev Harvests any yield generated by the strategy
     * @return harvested The amount harvested in base asset terms
     */
    function harvestYield() external returns (uint256 harvested);

    /**
     * @dev Emergency exit from the position
     * @return recovered The amount recovered in base asset terms
     */
    function emergencyExit() external returns (uint256 recovered);

    /**
     * @dev Updates risk parameters (only callable by authorized addresses)
     * @param newParams The new risk parameters
     */
    function updateRiskParameters(RiskParameters calldata newParams) external;

    // ============ EVENTS ============

    event ExposureOpened(uint256 amount, uint256 actualExposure, uint256 collateralUsed);
    event ExposureClosed(uint256 amount, uint256 actualClosed, uint256 collateralReleased);
    event ExposureAdjusted(int256 delta, uint256 newExposure);
    event YieldHarvested(uint256 amount);
    event EmergencyExit(uint256 recovered, string reason);
    event RiskParametersUpdated(RiskParameters newParams);
    event CostUpdated(uint256 newCost, uint256 timestamp);
}