// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IExposureStrategy} from "../interfaces/IExposureStrategy.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {IPerpetualTrading} from "../interfaces/IPerpetualTrading.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title EnhancedPerpetualStrategy
 * @dev Enhanced perpetual strategy with dynamic leverage optimization and integrated yield strategies
 * @notice Provides leveraged RWA exposure through perpetuals while optimizing capital efficiency
 */
contract EnhancedPerpetualStrategy is IExposureStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant FUNDING_RATE_HISTORY_LENGTH = 168; // 1 week of hourly data
    uint256 public constant MAX_YIELD_STRATEGIES = 3;

    // Core configuration
    IERC20 public immutable baseAsset;
    IPerpetualTrading public perpetualRouter;
    IPriceOracle public priceOracle;
    bytes32 public marketId;
    string public strategyName;

    // Strategy state
    bytes32 public activePositionId;
    uint256 public totalCollateralDeployed;
    uint256 public currentExposureAmount;
    uint256 public totalCapitalAllocated;

    // Dynamic leverage configuration
    uint256 public baseLeverage = 200; // 2x base leverage
    uint256 public maxLeverage = 500;  // 5x max leverage
    uint256 public minLeverage = 100;  // 1x min leverage (no leverage)
    bool public dynamicLeverageEnabled = true;

    // Funding rate optimization
    int256[] public fundingRateHistory;
    uint256 public lastFundingUpdate;
    int256 public fundingRateThreshold = 100; // 1% funding rate threshold (basis points)
    uint256 public leverageAdjustmentFactor = 20; // 20% leverage adjustment per 1% funding

    // Risk management
    RiskParameters public riskParams;

    // Yield strategy integration
    struct YieldAllocation {
        IYieldStrategy strategy;
        uint256 allocation; // Basis points
        uint256 currentDeposit;
        bool isActive;
    }

    YieldAllocation[] public yieldStrategies;
    uint256 public totalYieldCapital;
    uint256 public maxYieldAllocation = 7000; // 70% max to yield when leveraged

    // Performance tracking
    uint256 public totalFundingPaid;
    uint256 public totalYieldEarned;
    uint256 public positionOpenTime;
    uint256 public lastRebalanceTime;

    // Events
    event PositionOpened(bytes32 indexed positionId, uint256 collateral, uint256 leverage, uint256 exposure);
    event PositionClosed(bytes32 indexed positionId, int256 pnl, uint256 collateralReturned);
    event LeverageAdjusted(uint256 oldLeverage, uint256 newLeverage, int256 fundingRate);
    event YieldStrategyAdded(address indexed strategy, uint256 allocation);
    event YieldStrategyRemoved(address indexed strategy);
    event YieldHarvested(uint256 totalYield, uint256 fromStrategies);
    event FundingRateUpdated(int256 newRate, uint256 timestamp);
    event EmergencyLeverageReduction(uint256 oldLeverage, uint256 newLeverage, string reason);
    event CapitalEfficiencyOptimized(uint256 yieldCapital, uint256 exposure, uint256 efficiency);

    /**
     * @dev Constructor
     * @param _baseAsset Base asset for the strategy (e.g., USDC)
     * @param _perpetualRouter Perpetual trading router
     * @param _priceOracle Price oracle for valuations
     * @param _marketId Market identifier for the perpetual (e.g., "SPX-USD")
     * @param _strategyName Human readable strategy name
     */
    constructor(
        address _baseAsset,
        address _perpetualRouter,
        address _priceOracle,
        bytes32 _marketId,
        string memory _strategyName
    ) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        if (_perpetualRouter == address(0)) revert CommonErrors.ZeroAddress();
        if (_priceOracle == address(0)) revert CommonErrors.ZeroAddress();
        if (bytes(_strategyName).length == 0) revert CommonErrors.EmptyString();

        baseAsset = IERC20(_baseAsset);
        perpetualRouter = IPerpetualTrading(_perpetualRouter);
        priceOracle = IPriceOracle(_priceOracle);
        marketId = _marketId;
        strategyName = _strategyName;

        // Initialize risk parameters
        riskParams = RiskParameters({
            maxLeverage: maxLeverage,
            maxPositionSize: 10000000e6, // $10M max position
            liquidationBuffer: 1500,     // 15% liquidation buffer
            rebalanceThreshold: 500,     // 5% rebalance threshold
            slippageLimit: 200,          // 2% max slippage
            emergencyExitEnabled: true
        });

        lastFundingUpdate = block.timestamp;
        lastRebalanceTime = block.timestamp;
    }

    // ============ IEXPOSURESTRATEGY IMPLEMENTATION ============

    function getExposureInfo() external view override returns (ExposureInfo memory info) {
        uint256 currentLeverage = _calculateCurrentLeverage();
        uint256 liquidationPrice = _calculateLiquidationPrice();

        info = ExposureInfo({
            strategyType: StrategyType.PERPETUAL,
            name: strategyName,
            underlyingAsset: _getUnderlyingAsset(),
            leverage: currentLeverage,
            collateralRatio: _calculateCollateralRatio(currentLeverage),
            currentExposure: currentExposureAmount,
            maxCapacity: riskParams.maxPositionSize,
            currentCost: _calculateCurrentCost(),
            riskScore: _calculateRiskScore(),
            isActive: activePositionId != bytes32(0),
            liquidationPrice: liquidationPrice
        });
    }

    function getCostBreakdown() external view override returns (CostBreakdown memory costs) {
        int256 currentFunding = _getCurrentFundingRate();
        uint256 managementFee = 15; // 0.15% annual management fee
        uint256 estimatedSlippage = _estimateSlippage();
        uint256 gasCost = _estimateGasCost();

        costs = CostBreakdown({
            fundingRate: currentFunding >= 0 ? uint256(currentFunding) : 0,
            borrowRate: 0, // Not applicable for perpetuals
            managementFee: managementFee,
            slippageCost: estimatedSlippage,
            gasCost: gasCost,
            totalCostBps: _calculateTotalCostBps(currentFunding, managementFee, estimatedSlippage, gasCost),
            lastUpdated: block.timestamp
        });
    }

    function getRiskParameters() external view override returns (RiskParameters memory) {
        return riskParams;
    }

    function estimateExposureCost(uint256 amount, uint256 timeHorizon) external view override returns (uint256 estimatedCost) {
        uint256 leverage = _calculateOptimalLeverage();
        uint256 exposureAmount = (amount * leverage) / 100;
        
        int256 avgFundingRate = _getAverageFundingRate();
        uint256 annualFundingCost = avgFundingRate > 0 ? 
            (exposureAmount * uint256(avgFundingRate)) / BASIS_POINTS : 0;
        
        uint256 timeBasedCost = (annualFundingCost * timeHorizon) / 365 days;
        uint256 managementCost = (amount * 15 * timeHorizon) / (BASIS_POINTS * 365 days);
        
        return timeBasedCost + managementCost;
    }

    function getCurrentExposureValue() external view override returns (uint256 value) {
        if (activePositionId == bytes32(0)) return 0;
        
        try perpetualRouter.getPositionValue(activePositionId) returns (uint256 positionValue) {
            return positionValue + totalYieldCapital;
        } catch {
            // Fallback calculation
            return totalCollateralDeployed + totalYieldCapital;
        }
    }

    function getCollateralRequired(uint256 exposureAmount) external view override returns (uint256 collateralRequired) {
        uint256 leverage = _calculateOptimalLeverage();
        return (exposureAmount * 100) / leverage;
    }

    function getLiquidationPrice() external view override returns (uint256 liquidationPrice) {
        return _calculateLiquidationPrice();
    }

    function canHandleExposure(uint256 amount) external view override returns (bool canHandle, string memory reason) {
        if (amount == 0) return (false, "Amount cannot be zero");
        
        uint256 leverage = _calculateOptimalLeverage();
        // uint256 requiredCollateral = (amount * 100) / leverage;
        uint256 proposedExposure = (amount * leverage) / 100;
        
        if (currentExposureAmount + proposedExposure > riskParams.maxPositionSize) {
            return (false, "Would exceed maximum position size");
        }
        
        if (leverage > riskParams.maxLeverage) {
            return (false, "Required leverage exceeds maximum allowed");
        }
        
        int256 currentFunding = _getCurrentFundingRate();
        if (currentFunding > fundingRateThreshold * 3) { // 3x threshold
            return (false, "Funding rate too high for new positions");
        }
        
        return (true, "");
    }

    // ============ STATE-CHANGING FUNCTIONS ============

    function openExposure(uint256 amount) external override nonReentrant returns (bool success, uint256 actualExposure) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Check if we can handle this exposure
        (bool canHandle, /* string memory reason */) = this.canHandleExposure(amount);
        if (!canHandle) revert CommonErrors.OperationFailed();
        
        // Transfer base asset from caller
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate optimal leverage and allocation
        uint256 optimalLeverage = _calculateOptimalLeverage();
        (uint256 collateralAmount, uint256 yieldAmount) = _calculateOptimalAllocation(amount, optimalLeverage);
        
        // Open or adjust perpetual position
        actualExposure = _managePosition(collateralAmount, optimalLeverage, true);
        
        // Allocate remaining capital to yield strategies
        if (yieldAmount > 0) {
            _allocateToYieldStrategies(yieldAmount);
        }
        
        // Update state
        totalCapitalAllocated += amount;
        totalCollateralDeployed += collateralAmount;
        currentExposureAmount += actualExposure;
        
        emit ExposureOpened(amount, actualExposure, collateralAmount);
        emit CapitalEfficiencyOptimized(totalYieldCapital, currentExposureAmount, _calculateCapitalEfficiency());
        
        return (true, actualExposure);
    }

    function closeExposure(uint256 amount) external override nonReentrant returns (bool success, uint256 actualClosed) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (amount > currentExposureAmount) revert CommonErrors.InsufficientBalance();
        
        uint256 closeRatio = (amount * BASIS_POINTS) / currentExposureAmount;
        
        // Close portion of perpetual position
        uint256 collateralReturned = _closePositionPortion(closeRatio);
        
        // Withdraw from yield strategies proportionally
        uint256 yieldWithdrawn = _withdrawFromYieldStrategies(closeRatio);
        
        actualClosed = collateralReturned + yieldWithdrawn;
        
        // Update state
        currentExposureAmount -= amount;
        totalCollateralDeployed = totalCollateralDeployed > collateralReturned ? 
            totalCollateralDeployed - collateralReturned : 0;
        totalCapitalAllocated = totalCapitalAllocated > actualClosed ?
            totalCapitalAllocated - actualClosed : 0;
        
        // Transfer assets back to caller
        if (actualClosed > 0) {
            baseAsset.safeTransfer(msg.sender, actualClosed);
        }
        
        emit ExposureClosed(amount, actualClosed, collateralReturned);
        return (true, actualClosed);
    }

    function adjustExposure(int256 delta) external override nonReentrant returns (bool success, uint256 newExposure) {
        if (delta == 0) return (true, currentExposureAmount);
        
        if (delta > 0) {
            // Increase exposure - duplicate openExposure logic without reentrancy guard
            uint256 amount = uint256(delta);
            if (amount == 0) revert CommonErrors.ValueTooLow();
            
            // Check if we can handle this exposure
            (bool canHandle, /* string memory reason */) = this.canHandleExposure(amount);
            if (!canHandle) {
                success = false;
            } else {
                // Transfer base asset from caller
                baseAsset.safeTransferFrom(msg.sender, address(this), amount);
                
                // Calculate optimal leverage and allocation
                uint256 optimalLeverage = _calculateOptimalLeverage();
                (uint256 collateralAmount, uint256 yieldAmount) = _calculateOptimalAllocation(amount, optimalLeverage);
                
                // Open or adjust perpetual position
                uint256 actualExposure = _managePosition(collateralAmount, optimalLeverage, true);
                
                // Allocate remaining capital to yield strategies
                if (yieldAmount > 0) {
                    _allocateToYieldStrategies(yieldAmount);
                }
                
                // Update state
                totalCapitalAllocated += amount;
                totalCollateralDeployed += collateralAmount;
                currentExposureAmount += actualExposure;
                
                emit ExposureOpened(amount, actualExposure, collateralAmount);
                emit CapitalEfficiencyOptimized(totalYieldCapital, currentExposureAmount, _calculateCapitalEfficiency());
                
                success = true;
            }
        } else {
            // Decrease exposure - duplicate closeExposure logic without reentrancy guard
            uint256 reduceAmount = uint256(-delta);
            if (reduceAmount > currentExposureAmount) {
                success = false;
            } else {
                uint256 closeRatio = (reduceAmount * BASIS_POINTS) / currentExposureAmount;
                
                // Close portion of perpetual position
                uint256 collateralReturned = _closePositionPortion(closeRatio);
                
                // Withdraw from yield strategies proportionally
                uint256 yieldWithdrawn = _withdrawFromYieldStrategies(closeRatio);
                
                uint256 actualClosed = collateralReturned + yieldWithdrawn;
                
                // Update state
                currentExposureAmount -= reduceAmount;
                totalCollateralDeployed = totalCollateralDeployed > collateralReturned ? 
                    totalCollateralDeployed - collateralReturned : 0;
                totalCapitalAllocated = totalCapitalAllocated > actualClosed ?
                    totalCapitalAllocated - actualClosed : 0;
                
                // Transfer assets back to caller
                if (actualClosed > 0) {
                    baseAsset.safeTransfer(msg.sender, actualClosed);
                }
                
                emit ExposureClosed(reduceAmount, actualClosed, collateralReturned);
                success = true;
            }
        }
        
        newExposure = currentExposureAmount;
        emit ExposureAdjusted(delta, newExposure);
        
        return (success, newExposure);
    }

    function harvestYield() external override nonReentrant returns (uint256 harvested) {
        uint256 yieldFromStrategies = 0;
        
        // Harvest from yield strategies
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].isActive) {
                try yieldStrategies[i].strategy.harvestYield() returns (uint256 strategyYield) {
                    yieldFromStrategies += strategyYield;
                } catch {
                    // Continue with other strategies
                }
            }
        }
        
        harvested = yieldFromStrategies;
        totalYieldEarned += harvested;
        
        // Transfer yield to caller
        if (harvested > 0) {
            baseAsset.safeTransfer(msg.sender, harvested);
        }
        
        emit YieldHarvested(harvested, yieldFromStrategies);
        return harvested;
    }

    function emergencyExit() external override nonReentrant returns (uint256 recovered) {
        if (!riskParams.emergencyExitEnabled) revert CommonErrors.NotAllowed();
        
        uint256 collateralRecovered = 0;
        uint256 yieldRecovered = 0;
        
        // Close perpetual position
        if (activePositionId != bytes32(0)) {
            try perpetualRouter.closePosition(activePositionId) returns (int256 pnl) {
                collateralRecovered = baseAsset.balanceOf(address(this));
                activePositionId = bytes32(0);
                emit PositionClosed(activePositionId, pnl, collateralRecovered);
            } catch {
                // Position might be stuck - record emergency
                emit EmergencyLeverageReduction(
                    _calculateCurrentLeverage(), 
                    100, 
                    "Emergency exit - position closure failed"
                );
            }
        }
        
        // Emergency withdraw from yield strategies
        yieldRecovered = _emergencyWithdrawFromYieldStrategies();
        
        recovered = collateralRecovered + yieldRecovered;
        
        // Reset state
        currentExposureAmount = 0;
        totalCollateralDeployed = 0;
        totalYieldCapital = 0;
        
        // Transfer recovered assets
        if (recovered > 0) {
            baseAsset.safeTransfer(msg.sender, recovered);
        }
        
        emit EmergencyExit(recovered, "Enhanced perpetual strategy emergency exit");
        return recovered;
    }

    function updateRiskParameters(RiskParameters calldata newParams) external override onlyOwner {
        // Validate parameters
        if (newParams.maxLeverage > 1000) revert CommonErrors.ValueTooHigh(); // Max 10x
        if (newParams.slippageLimit > 1000) revert CommonErrors.ValueTooHigh(); // Max 10%
        
        riskParams = newParams;
        
        // Update internal limits
        maxLeverage = newParams.maxLeverage;
        
        emit RiskParametersUpdated(newParams);
    }

    // ============ PERPETUAL-SPECIFIC FUNCTIONS ============

    /**
     * @dev Updates funding rate and adjusts leverage if needed
     */
    function updateFundingRate() external {
        int256 newFundingRate = _getCurrentFundingRate();
        _addFundingRateToHistory(newFundingRate);
        
        if (dynamicLeverageEnabled && activePositionId != bytes32(0)) {
            _optimizeLeverageForFunding(newFundingRate);
        }
        
        lastFundingUpdate = block.timestamp;
        emit FundingRateUpdated(newFundingRate, block.timestamp);
    }

    /**
     * @dev Manually triggers leverage optimization based on current conditions
     */
    function optimizeLeverage() external onlyOwner returns (uint256 newLeverage) {
        if (activePositionId == bytes32(0)) return baseLeverage;
        
        uint256 currentLeverage = _calculateCurrentLeverage();
        newLeverage = _calculateOptimalLeverage();
        
        if (currentLeverage != newLeverage) {
            _adjustPositionLeverage(newLeverage);
            emit LeverageAdjusted(currentLeverage, newLeverage, _getCurrentFundingRate());
        }
        
        return newLeverage;
    }

    /**
     * @dev Adds a yield strategy for capital efficiency
     */
    function addYieldStrategy(address strategy, uint256 allocation) external onlyOwner {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        if (allocation > BASIS_POINTS) revert CommonErrors.ValueTooHigh();
        if (yieldStrategies.length >= MAX_YIELD_STRATEGIES) revert CommonErrors.ValueTooHigh();
        
        // Validate total allocation doesn't exceed 100%
        uint256 totalAllocation = allocation;
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].isActive) {
                totalAllocation += yieldStrategies[i].allocation;
            }
        }
        if (totalAllocation > BASIS_POINTS) revert CommonErrors.ValueTooHigh();
        
        yieldStrategies.push(YieldAllocation({
            strategy: IYieldStrategy(strategy),
            allocation: allocation,
            currentDeposit: 0,
            isActive: true
        }));
        
        emit YieldStrategyAdded(strategy, allocation);
    }

    /**
     * @dev Removes a yield strategy
     */
    function removeYieldStrategy(address strategy) external onlyOwner {
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (address(yieldStrategies[i].strategy) == strategy) {
                // Withdraw all funds from strategy
                if (yieldStrategies[i].currentDeposit > 0) {
                    try yieldStrategies[i].strategy.withdraw(yieldStrategies[i].currentDeposit) returns (uint256) {
                        totalYieldCapital -= yieldStrategies[i].currentDeposit;
                    } catch {
                        // Strategy might be stuck
                    }
                }
                
                // Remove strategy by swapping with last element
                yieldStrategies[i] = yieldStrategies[yieldStrategies.length - 1];
                yieldStrategies.pop();
                
                emit YieldStrategyRemoved(strategy);
                return;
            }
        }
        revert CommonErrors.NotFound();
    }

    /**
     * @dev Sets dynamic leverage parameters
     */
    function setLeverageParameters(
        uint256 _baseLeverage,
        uint256 _maxLeverage,
        uint256 _minLeverage,
        bool _dynamicEnabled
    ) external onlyOwner {
        if (_baseLeverage < _minLeverage || _baseLeverage > _maxLeverage) revert CommonErrors.InvalidValue();
        if (_maxLeverage > 1000) revert CommonErrors.ValueTooHigh(); // Max 10x
        
        baseLeverage = _baseLeverage;
        maxLeverage = _maxLeverage;
        minLeverage = _minLeverage;
        dynamicLeverageEnabled = _dynamicEnabled;
    }

    /**
     * @dev Sets funding rate parameters
     */
    function setFundingParameters(
        int256 _threshold,
        uint256 _adjustmentFactor
    ) external onlyOwner {
        if (_adjustmentFactor > 100) revert CommonErrors.ValueTooHigh(); // Max 100% adjustment
        
        fundingRateThreshold = _threshold;
        leverageAdjustmentFactor = _adjustmentFactor;
    }

    // ============ VIEW FUNCTIONS ============

    function getYieldStrategies() external view returns (YieldAllocation[] memory) {
        return yieldStrategies;
    }

    function getCurrentLeverage() external view returns (uint256) {
        return _calculateCurrentLeverage();
    }

    function getFundingRateHistory() external view returns (int256[] memory) {
        return fundingRateHistory;
    }

    function getCapitalEfficiency() external view returns (uint256) {
        return _calculateCapitalEfficiency();
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalFunding,
        uint256 totalYield,
        uint256 netReturn,
        uint256 efficiency
    ) {
        totalFunding = totalFundingPaid;
        totalYield = totalYieldEarned;
        netReturn = totalYieldEarned > totalFundingPaid ? 
            totalYieldEarned - totalFundingPaid : 0;
        efficiency = _calculateCapitalEfficiency();
    }

    // ============ INTERNAL FUNCTIONS ============

    function _calculateCurrentLeverage() internal view returns (uint256) {
        if (totalCollateralDeployed == 0 || currentExposureAmount == 0) return baseLeverage;
        return (currentExposureAmount * 100) / totalCollateralDeployed;
    }

    function _calculateOptimalLeverage() internal view returns (uint256) {
        if (!dynamicLeverageEnabled) return baseLeverage;
        
        int256 avgFundingRate = _getAverageFundingRate();
        uint256 leverage = baseLeverage;
        
        // Adjust leverage based on funding rate
        if (avgFundingRate > fundingRateThreshold) {
            // High funding - reduce leverage
            uint256 reduction = (uint256(avgFundingRate) * leverageAdjustmentFactor) / BASIS_POINTS;
            leverage = leverage > reduction ? leverage - reduction : minLeverage;
        } else if (avgFundingRate < -fundingRateThreshold) {
            // Negative funding - increase leverage
            uint256 increase = (uint256(-avgFundingRate) * leverageAdjustmentFactor) / BASIS_POINTS;
            leverage = leverage + increase;
        }
        
        // Ensure within bounds
        if (leverage > maxLeverage) leverage = maxLeverage;
        if (leverage < minLeverage) leverage = minLeverage;
        
        return leverage;
    }

    function _calculateOptimalAllocation(
        uint256 totalAmount, 
        uint256 leverage
    ) internal view returns (uint256 collateralAmount, uint256 yieldAmount) {
        // Calculate collateral needed for desired exposure
        uint256 desiredExposure = totalAmount;
        collateralAmount = (desiredExposure * 100) / leverage;
        
        // Remaining goes to yield strategies (up to max allocation)
        uint256 remainingAmount = totalAmount - collateralAmount;
        uint256 maxYieldAmount = (totalAmount * maxYieldAllocation) / BASIS_POINTS;
        
        yieldAmount = remainingAmount < maxYieldAmount ? remainingAmount : maxYieldAmount;
        
        // If we can't use all for yield, add back to collateral for safety
        if (yieldAmount < remainingAmount) {
            collateralAmount += (remainingAmount - yieldAmount);
        }
        
        return (collateralAmount, yieldAmount);
    }

    function _managePosition(
        uint256 collateralAmount,
        uint256 leverage,
        bool /* isIncrease */
    ) internal returns (uint256 actualExposure) {
        // Approve perpetual router to spend collateral
        baseAsset.approve(address(perpetualRouter), collateralAmount);
        
        if (activePositionId == bytes32(0)) {
            // Open new position
            int256 positionSize = int256((collateralAmount * leverage) / 100);
            
            try perpetualRouter.openPosition(
                marketId,
                positionSize,
                leverage,
                collateralAmount
            ) returns (bytes32 positionId) {
                activePositionId = positionId;
                actualExposure = uint256(positionSize);
                positionOpenTime = block.timestamp;
                
                emit PositionOpened(positionId, collateralAmount, leverage, actualExposure);
            } catch {
                revert CommonErrors.OperationFailed();
            }
        } else {
            // Adjust existing position
            IPerpetualTrading.Position memory currentPos = perpetualRouter.getPosition(activePositionId);
            int256 newSize = currentPos.size + int256((collateralAmount * leverage) / 100);
            
            try perpetualRouter.adjustPosition(
                activePositionId,
                newSize,
                leverage,
                int256(collateralAmount)
            ) returns (bool success) {
                if (success) {
                    actualExposure = uint256(newSize) - uint256(currentPos.size);
                } else {
                    revert CommonErrors.OperationFailed();
                }
            } catch {
                revert CommonErrors.OperationFailed();
            }
        }
        
        return actualExposure;
    }

    function _closePositionPortion(uint256 closeRatio) internal returns (uint256 collateralReturned) {
        if (activePositionId == bytes32(0)) return 0;
        
        if (closeRatio >= BASIS_POINTS) {
            // Close entire position
            try perpetualRouter.closePosition(activePositionId) returns (int256 pnl) {
                collateralReturned = baseAsset.balanceOf(address(this));
                emit PositionClosed(activePositionId, pnl, collateralReturned);
                activePositionId = bytes32(0);
            } catch {
                // Position might be stuck
                return 0;
            }
        } else {
            // Partially close position
            IPerpetualTrading.Position memory currentPos = perpetualRouter.getPosition(activePositionId);
            int256 sizeToClose = (currentPos.size * int256(closeRatio)) / int256(BASIS_POINTS);
            int256 newSize = currentPos.size - sizeToClose;
            
            try perpetualRouter.adjustPosition(
                activePositionId,
                newSize,
                currentPos.leverage,
                -int256((totalCollateralDeployed * closeRatio) / BASIS_POINTS)
            ) returns (bool success) {
                if (success) {
                    collateralReturned = (totalCollateralDeployed * closeRatio) / BASIS_POINTS;
                }
            } catch {
                // Adjustment failed
                return 0;
            }
        }
        
        return collateralReturned;
    }

    function _allocateToYieldStrategies(uint256 amount) internal {
        if (yieldStrategies.length == 0 || amount == 0) return;
        
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (!yieldStrategies[i].isActive) continue;
            
            uint256 allocationAmount = (amount * yieldStrategies[i].allocation) / BASIS_POINTS;
            if (allocationAmount == 0) continue;
            
            baseAsset.approve(address(yieldStrategies[i].strategy), allocationAmount);
            
            try yieldStrategies[i].strategy.deposit(allocationAmount) returns (uint256 /* shares */) {
                yieldStrategies[i].currentDeposit += allocationAmount;
                totalYieldCapital += allocationAmount;
            } catch {
                // Strategy failed - continue with others
            }
        }
    }

    function _withdrawFromYieldStrategies(uint256 withdrawRatio) internal returns (uint256 totalWithdrawn) {
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (!yieldStrategies[i].isActive || yieldStrategies[i].currentDeposit == 0) continue;
            
            uint256 withdrawAmount = (yieldStrategies[i].currentDeposit * withdrawRatio) / BASIS_POINTS;
            if (withdrawAmount == 0) continue;
            
            try yieldStrategies[i].strategy.withdraw(withdrawAmount) returns (uint256 actualWithdrawn) {
                totalWithdrawn += actualWithdrawn;
                yieldStrategies[i].currentDeposit -= withdrawAmount;
                totalYieldCapital = totalYieldCapital > withdrawAmount ? 
                    totalYieldCapital - withdrawAmount : 0;
            } catch {
                // Strategy might be stuck - continue with others
            }
        }
        
        return totalWithdrawn;
    }

    function _emergencyWithdrawFromYieldStrategies() internal returns (uint256 totalRecovered) {
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            if (yieldStrategies[i].currentDeposit > 0) {
                try yieldStrategies[i].strategy.withdraw(yieldStrategies[i].currentDeposit) returns (uint256 recovered) {
                    totalRecovered += recovered;
                } catch {
                    // Strategy emergency might also fail
                }
                yieldStrategies[i].currentDeposit = 0;
            }
        }
        totalYieldCapital = 0;
        return totalRecovered;
    }

    function _getCurrentFundingRate() internal view returns (int256) {
        try perpetualRouter.getFundingRate(marketId) returns (int256 rate) {
            return rate;
        } catch {
            return 0;
        }
    }

    function _getAverageFundingRate() internal view returns (int256) {
        if (fundingRateHistory.length == 0) return 0;
        
        int256 sum = 0;
        uint256 count = Math.min(fundingRateHistory.length, 24); // Last 24 hours
        
        for (uint256 i = fundingRateHistory.length - count; i < fundingRateHistory.length; i++) {
            sum += fundingRateHistory[i];
        }
        
        return sum / int256(count);
    }

    function _addFundingRateToHistory(int256 rate) internal {
        fundingRateHistory.push(rate);
        
        // Keep only recent history
        if (fundingRateHistory.length > FUNDING_RATE_HISTORY_LENGTH) {
            // Shift array left
            for (uint256 i = 0; i < fundingRateHistory.length - 1; i++) {
                fundingRateHistory[i] = fundingRateHistory[i + 1];
            }
            fundingRateHistory.pop();
        }
    }

    function _optimizeLeverageForFunding(int256 currentFunding) internal {
        uint256 currentLeverage = _calculateCurrentLeverage();
        uint256 optimalLeverage = _calculateOptimalLeverage();
        
        // Only adjust if difference is significant
        uint256 leverageDiff = currentLeverage > optimalLeverage ? 
            currentLeverage - optimalLeverage : optimalLeverage - currentLeverage;
        
        if (leverageDiff >= 25) { // 0.25x difference threshold
            _adjustPositionLeverage(optimalLeverage);
            emit LeverageAdjusted(currentLeverage, optimalLeverage, currentFunding);
        }
    }

    function _adjustPositionLeverage(uint256 newLeverage) internal {
        if (activePositionId == bytes32(0)) return;
        
        try perpetualRouter.getPosition(activePositionId) returns (IPerpetualTrading.Position memory /* position */) {
            // Calculate new position size for target leverage
            uint256 newSize = (totalCollateralDeployed * newLeverage) / 100;
            
            perpetualRouter.adjustPosition(
                activePositionId,
                int256(newSize),
                newLeverage,
                0 // No collateral change
            );
        } catch {
            // Leverage adjustment failed
        }
    }

    function _calculateLiquidationPrice() internal view returns (uint256) {
        if (activePositionId == bytes32(0)) return 0;
        
        // Simplified liquidation price calculation
        // In reality, this would be more complex based on the specific perpetual protocol
        uint256 currentLeverage = _calculateCurrentLeverage();
        if (currentLeverage <= 100) return 0; // No liquidation for 1x leverage
        
        // Rough estimate: liquidation occurs at ~90% loss from entry price
        uint256 liquidationBuffer = riskParams.liquidationBuffer;
        return (BASIS_POINTS - liquidationBuffer);
    }

    function _calculateCollateralRatio(uint256 leverage) internal pure returns (uint256) {
        if (leverage <= 100) return BASIS_POINTS; // 100% for no leverage
        return (100 * BASIS_POINTS) / leverage;
    }

    function _calculateCurrentCost() internal view returns (uint256) {
        int256 fundingRate = _getCurrentFundingRate();
        uint256 managementFee = 15; // 0.15%
        
        uint256 totalCost = managementFee;
        if (fundingRate > 0) {
            totalCost += uint256(fundingRate);
        }
        
        return totalCost;
    }

    function _calculateTotalCostBps(
        int256 fundingRate,
        uint256 managementFee,
        uint256 slippage,
        uint256 gasCost
    ) internal pure returns (uint256) {
        uint256 totalCost = managementFee + slippage + gasCost;
        if (fundingRate > 0) {
            totalCost += uint256(fundingRate);
        }
        return totalCost;
    }

    function _calculateRiskScore() internal view returns (uint256) {
        uint256 currentLeverage = _calculateCurrentLeverage();
        int256 avgFunding = _getAverageFundingRate();
        
        // Base risk score based on leverage
        uint256 riskScore = (currentLeverage * 50) / 100; // 50 risk points per 1x leverage
        
        // Adjust for funding rate volatility
        if (avgFunding > fundingRateThreshold) {
            riskScore += 20; // High funding adds risk
        } else if (avgFunding < -fundingRateThreshold) {
            riskScore = riskScore > 10 ? riskScore - 10 : 0; // Negative funding reduces risk
        }
        
        // Cap at 100
        return Math.min(riskScore, 100);
    }

    function _calculateCapitalEfficiency() internal view returns (uint256) {
        if (totalCapitalAllocated == 0) return 0;
        
        uint256 totalValue = currentExposureAmount + totalYieldCapital;
        return (totalValue * BASIS_POINTS) / totalCapitalAllocated;
    }

    function _estimateSlippage() internal view returns (uint256) {
        // Simplified slippage estimation
        // In reality, this would consider order book depth, position size, etc.
        uint256 baseSlippage = 5; // 0.05% base slippage
        
        // Increase slippage for larger positions
        if (currentExposureAmount > 1000000e6) { // > $1M
            baseSlippage += 10; // +0.1%
        }
        
        return baseSlippage;
    }

    function _estimateGasCost() internal pure returns (uint256) {
        // Simplified gas cost estimation in basis points
        return 2; // 0.02% estimated gas cost
    }

    function _getUnderlyingAsset() internal view returns (address) {
        // For perpetuals, the underlying asset is typically the market being tracked
        // This would need to be configured based on the specific market
        return address(baseAsset); // Simplified
    }
}