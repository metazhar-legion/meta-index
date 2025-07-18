// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExposureStrategy} from "../../src/interfaces/IExposureStrategy.sol";
import {CommonErrors} from "../../src/errors/CommonErrors.sol";

/**
 * @title MockExposureStrategy
 * @dev Mock implementation of IExposureStrategy for testing
 */
contract MockExposureStrategy is IExposureStrategy {
    using SafeERC20 for IERC20;

    IERC20 public baseAsset;
    string public strategyName;
    StrategyType public strategyType;
    
    // Mock state variables
    uint256 public currentExposure;
    uint256 public totalCollateral;
    uint256 public mockCost = 500; // 5% annual cost
    uint256 public mockRisk = 50;  // Medium risk
    uint256 public maxCapacity = 10000000e6; // $10M capacity
    uint256 public leverage = 200; // 2x leverage
    bool public isActive = true;
    
    // Risk parameters
    RiskParameters public riskParams;
    
    // Performance tracking
    uint256 public totalHarvested;
    uint256 public lastHarvest;
    
    // Mock failure modes for testing
    bool public shouldFailOnOpen;
    bool public shouldFailOnClose;
    bool public shouldFailOnHarvest;
    uint256 public slippagePercent = 50; // 0.5% slippage

    constructor(
        address _baseAsset,
        string memory _name,
        StrategyType _type
    ) {
        baseAsset = IERC20(_baseAsset);
        strategyName = _name;
        strategyType = _type;
        
        // Initialize default risk parameters
        riskParams = RiskParameters({
            maxLeverage: 500,           // 5x max leverage
            maxPositionSize: maxCapacity,
            liquidationBuffer: 1000,    // 10% buffer
            rebalanceThreshold: 500,    // 5% threshold
            slippageLimit: 200,         // 2% max slippage
            emergencyExitEnabled: true
        });
    }

    // ============ VIEW FUNCTIONS ============

    function getExposureInfo() external view override returns (ExposureInfo memory info) {
        info = ExposureInfo({
            strategyType: strategyType,
            name: strategyName,
            underlyingAsset: address(baseAsset),
            leverage: leverage,
            collateralRatio: 5000, // 50% collateral ratio
            currentExposure: currentExposure,
            maxCapacity: maxCapacity,
            currentCost: mockCost,
            riskScore: mockRisk,
            isActive: isActive,
            liquidationPrice: 0 // No liquidation for mock
        });
    }

    function getCostBreakdown() external view override returns (CostBreakdown memory costs) {
        costs = CostBreakdown({
            fundingRate: strategyType == StrategyType.PERPETUAL ? mockCost / 2 : 0,
            borrowRate: strategyType == StrategyType.TRS ? mockCost / 2 : 0,
            managementFee: 10, // 0.1%
            slippageCost: slippagePercent,
            gasCost: 5, // 0.05%
            totalCostBps: mockCost,
            lastUpdated: block.timestamp
        });
    }

    function getRiskParameters() external view override returns (RiskParameters memory params) {
        return riskParams;
    }

    function estimateExposureCost(uint256 amount, uint256 timeHorizon) external view override returns (uint256 estimatedCost) {
        // Simple cost estimation: (amount * cost * timeHorizon) / (365 days * 10000)
        return (amount * mockCost * timeHorizon) / (365 days * 10000);
    }

    function getCurrentExposureValue() external view override returns (uint256 value) {
        // For mock, assume 1:1 value with some variation
        return currentExposure + (currentExposure * 5 / 10000); // 0.05% growth
    }

    function getCollateralRequired(uint256 exposureAmount) external view override returns (uint256 collateralRequired) {
        return (exposureAmount * 5000) / 10000; // 50% collateral requirement
    }

    function getLiquidationPrice() external pure override returns (uint256 liquidationPrice) {
        return 0; // No liquidation for mock strategy
    }

    function canHandleExposure(uint256 amount) external view override returns (bool canHandle, string memory reason) {
        if (!isActive) return (false, "Strategy is inactive");
        if (currentExposure + amount > maxCapacity) return (false, "Exceeds max capacity");
        if (amount == 0) return (false, "Amount is zero");
        return (true, "");
    }

    // ============ STATE-CHANGING FUNCTIONS ============

    function openExposure(uint256 amount) external override returns (bool success, uint256 actualExposure) {
        if (shouldFailOnOpen) return (false, 0);
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (!isActive) revert CommonErrors.NotActive();
        
        // Transfer collateral from caller
        uint256 collateralNeeded = this.getCollateralRequired(amount);
        baseAsset.safeTransferFrom(msg.sender, address(this), collateralNeeded);
        
        // Calculate actual exposure with leverage
        actualExposure = amount * leverage / 100;
        
        // Apply slippage
        uint256 slippageAmount = (actualExposure * slippagePercent) / 10000;
        actualExposure = actualExposure - slippageAmount;
        
        currentExposure += actualExposure;
        totalCollateral += collateralNeeded;
        
        emit ExposureOpened(amount, actualExposure, collateralNeeded);
        return (true, actualExposure);
    }

    function closeExposure(uint256 amount) external override returns (bool success, uint256 actualClosed) {
        if (shouldFailOnClose) return (false, 0);
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (amount > currentExposure) revert CommonErrors.InsufficientBalance();
        
        // Apply slippage
        uint256 slippageAmount = (amount * slippagePercent) / 10000;
        actualClosed = amount - slippageAmount;
        
        // Calculate collateral to release
        uint256 collateralToRelease = (actualClosed * totalCollateral) / currentExposure;
        
        currentExposure -= actualClosed;
        totalCollateral -= collateralToRelease;
        
        // Transfer collateral back to caller
        if (collateralToRelease > 0) {
            baseAsset.safeTransfer(msg.sender, collateralToRelease);
        }
        
        emit ExposureClosed(amount, actualClosed, collateralToRelease);
        return (true, actualClosed);
    }

    function adjustExposure(int256 delta) external override returns (bool success, uint256 newExposure) {
        if (delta > 0) {
            (success, ) = this.openExposure(uint256(delta));
        } else if (delta < 0) {
            (success, ) = this.closeExposure(uint256(-delta));
        } else {
            success = true;
        }
        
        newExposure = currentExposure;
        
        if (success) {
            emit ExposureAdjusted(delta, newExposure);
        }
        
        return (success, newExposure);
    }

    function harvestYield() external override returns (uint256 harvested) {
        if (shouldFailOnHarvest) return 0;
        
        // Mock yield generation: 0.1% of current exposure
        harvested = currentExposure / 1000;
        
        if (harvested > 0) {
            // Mint some mock yield (in real implementation, this would come from protocol)
            totalHarvested += harvested;
            lastHarvest = block.timestamp;
            
            // Transfer yield to caller (for testing, just transfer any available balance)
            uint256 availableBalance = baseAsset.balanceOf(address(this));
            uint256 transferAmount = harvested < availableBalance ? harvested : availableBalance;
            
            if (transferAmount > 0) {
                baseAsset.safeTransfer(msg.sender, transferAmount);
            }
            
            emit YieldHarvested(harvested);
        }
        
        return harvested;
    }

    function emergencyExit() external override returns (uint256 recovered) {
        if (!riskParams.emergencyExitEnabled) revert CommonErrors.NotAllowed();
        
        // Close all exposure
        uint256 exposureToClose = currentExposure;
        if (exposureToClose > 0) {
            (bool success, ) = this.closeExposure(exposureToClose);
            if (!success) {
                // Force close with maximum slippage
                currentExposure = 0;
                recovered = totalCollateral / 2; // 50% recovery in emergency
                totalCollateral = 0;
            } else {
                recovered = baseAsset.balanceOf(address(this));
            }
        }
        
        isActive = false;
        emit EmergencyExit(recovered, "Mock emergency exit");
        return recovered;
    }

    function updateRiskParameters(RiskParameters calldata newParams) external override {
        riskParams = newParams;
        emit RiskParametersUpdated(newParams);
    }

    // ============ MOCK CONFIGURATION FUNCTIONS ============

    function setMockCost(uint256 _cost) external {
        mockCost = _cost;
        emit CostUpdated(_cost, block.timestamp);
    }

    function setMockRisk(uint256 _risk) external {
        mockRisk = _risk;
    }

    function setMaxCapacity(uint256 _capacity) external {
        maxCapacity = _capacity;
    }

    function setLeverage(uint256 _leverage) external {
        leverage = _leverage;
    }

    function setActive(bool _active) external {
        isActive = _active;
    }

    function setSlippagePercent(uint256 _slippage) external {
        slippagePercent = _slippage;
    }

    function setShouldFailOnOpen(bool _shouldFail) external {
        shouldFailOnOpen = _shouldFail;
    }

    function setShouldFailOnClose(bool _shouldFail) external {
        shouldFailOnClose = _shouldFail;
    }

    function setShouldFailOnHarvest(bool _shouldFail) external {
        shouldFailOnHarvest = _shouldFail;
    }

    // ============ UTILITY FUNCTIONS FOR TESTING ============

    function fundStrategy(uint256 amount) external {
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function getBalance() external view returns (uint256) {
        return baseAsset.balanceOf(address(this));
    }

    function simulateExposureGrowth(uint256 growthPercent) external {
        currentExposure = currentExposure + (currentExposure * growthPercent / 10000);
    }

    function simulateExposureLoss(uint256 lossPercent) external {
        uint256 loss = (currentExposure * lossPercent) / 10000;
        currentExposure = currentExposure > loss ? currentExposure - loss : 0;
    }
}