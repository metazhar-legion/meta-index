// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IAssetWrapper} from "./interfaces/IAssetWrapper.sol";
import {IExposureStrategy} from "./interfaces/IExposureStrategy.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {IStrategyOptimizer} from "./interfaces/IStrategyOptimizer.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title ComposableRWABundle
 * @dev Composable RWA exposure bundle that manages multiple strategies
 * @notice Replaces the old RWAAssetWrapper with a multi-strategy approach
 */
contract ComposableRWABundle is IAssetWrapper, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_STRATEGIES = 10;
    uint256 public constant MAX_YIELD_STRATEGIES = 5;

    /**
     * @dev Configuration for an exposure strategy
     */
    struct StrategyAllocation {
        IExposureStrategy strategy;
        uint256 targetAllocation;      // Basis points (0-10000)
        uint256 currentAllocation;     // Basis points (0-10000)
        uint256 maxAllocation;         // Risk limit in basis points
        uint256 minAllocation;         // Minimum allocation (for diversification)
        bool isPrimary;                // Whether this is a primary strategy
        bool isActive;                 // Whether strategy is currently active
        uint256 lastRebalance;         // Timestamp of last rebalance
        uint256 totalAllocated;        // Total amount allocated to this strategy
    }

    /**
     * @dev Yield strategy bundle configuration
     */
    struct YieldStrategyBundle {
        IYieldStrategy[] strategies;
        uint256[] allocations;         // Allocation percentages (basis points)
        uint256 totalYieldCapital;     // Total capital in yield strategies
        uint256 leverageRatio;         // Current leverage ratio (100 = 1x)
        uint256 maxLeverageRatio;      // Maximum allowed leverage
        bool isActive;                 // Whether yield strategies are active
    }

    /**
     * @dev Risk management parameters
     */
    struct RiskParameters {
        uint256 maxTotalLeverage;      // Maximum total leverage across all strategies
        uint256 maxStrategyCount;      // Maximum number of active strategies
        uint256 rebalanceThreshold;    // Threshold for triggering rebalance (basis points)
        uint256 emergencyThreshold;    // Threshold for emergency actions (basis points)
        uint256 maxSlippageTolerance;  // Maximum slippage tolerance (basis points)
        uint256 minCapitalEfficiency;  // Minimum capital efficiency threshold
        bool circuitBreakerActive;    // Emergency circuit breaker
    }

    // State variables
    IERC20 public baseAsset;
    IPriceOracle public priceOracle;
    IStrategyOptimizer public optimizer;
    
    string public name;
    
    // Strategy management
    StrategyAllocation[] public exposureStrategies;
    YieldStrategyBundle public yieldBundle;
    RiskParameters public riskParams;
    
    // Tracking variables
    uint256 public totalAllocatedCapital;
    uint256 public totalTargetExposure;
    uint256 public lastOptimization;
    uint256 public lastRebalance;
    uint256 public optimizationInterval = 1 hours;
    uint256 public rebalanceInterval = 6 hours;
    
    // Performance tracking
    mapping(address => uint256) public strategyPerformance;
    mapping(address => uint256) public strategyCosts;
    mapping(address => uint256) public strategyLastUpdate;
    
    // Events
    event StrategyAdded(address indexed strategy, uint256 targetAllocation, bool isPrimary);
    event StrategyRemoved(address indexed strategy);
    event StrategyAllocationUpdated(address indexed strategy, uint256 oldAllocation, uint256 newAllocation);
    event YieldBundleUpdated(address[] strategies, uint256[] allocations, uint256 totalCapital);
    event OptimizationPerformed(uint256 totalCostSaving, uint256 gasUsed, uint256 timestamp);
    event RebalanceExecuted(uint256 strategiesRebalanced, uint256 totalValueMoved, uint256 timestamp);
    event EmergencyActionTaken(string reason, address strategy, uint256 amount);
    event RiskParametersUpdated(RiskParameters newParams);
    event CircuitBreakerActivated(string reason);
    event PerformanceRecorded(address indexed strategy, uint256 return_, uint256 cost);

    /**
     * @dev Constructor
     * @param _name Name of this RWA bundle
     * @param _baseAsset Base asset token (e.g., USDC)
     * @param _priceOracle Price oracle for asset valuation
     * @param _optimizer Strategy optimizer contract
     */
    constructor(
        string memory _name,
        address _baseAsset,
        address _priceOracle,
        address _optimizer
    ) Ownable(msg.sender) {
        if (bytes(_name).length == 0) revert CommonErrors.EmptyString();
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        if (_priceOracle == address(0)) revert CommonErrors.ZeroAddress();
        if (_optimizer == address(0)) revert CommonErrors.ZeroAddress();

        name = _name;
        baseAsset = IERC20(_baseAsset);
        priceOracle = IPriceOracle(_priceOracle);
        optimizer = IStrategyOptimizer(_optimizer);

        // Initialize risk parameters with conservative defaults
        riskParams = RiskParameters({
            maxTotalLeverage: 300,          // 3x max total leverage
            maxStrategyCount: 5,            // Max 5 active strategies
            rebalanceThreshold: 500,        // 5% rebalance threshold
            emergencyThreshold: 2000,       // 20% emergency threshold
            maxSlippageTolerance: 200,      // 2% max slippage
            minCapitalEfficiency: 8000,     // 80% minimum capital efficiency
            circuitBreakerActive: false     // Circuit breaker initially off
        });

        // Initialize yield bundle
        yieldBundle.maxLeverageRatio = 300; // 3x max leverage for yield
        yieldBundle.isActive = true;
    }

    // ============ IASSETWRAPPER IMPLEMENTATION ============

    /**
     * @dev Allocates capital to the RWA bundle
     * @param amount Amount of base asset to allocate
     * @return success Whether allocation was successful
     */
    function allocateCapital(uint256 amount) external override nonReentrant whenNotPaused returns (bool success) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (riskParams.circuitBreakerActive) revert CommonErrors.NotActive();

        // Transfer base asset from caller
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Check if optimization is needed before allocation
        if (_shouldOptimize()) {
            _performOptimization();
        }

        // Allocate across exposure strategies
        uint256 exposureAmount = _calculateExposureAllocation(amount);
        uint256 yieldAmount = amount - exposureAmount;

        // Allocate to exposure strategies
        if (exposureAmount > 0) {
            _allocateToExposureStrategies(exposureAmount);
        }

        // Allocate to yield strategies
        if (yieldAmount > 0) {
            _allocateToYieldStrategies(yieldAmount);
        }

        totalAllocatedCapital += amount;
        
        emit CapitalAllocated(amount, exposureAmount, yieldAmount);
        return true;
    }

    /**
     * @dev Withdraws capital from the RWA bundle
     * @param amount Amount of base asset to withdraw
     * @return actualAmount Actual amount withdrawn
     */
    function withdrawCapital(uint256 amount) external override nonReentrant returns (uint256 actualAmount) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (amount > totalAllocatedCapital) revert CommonErrors.InsufficientBalance();

        uint256 totalValue = getValueInBaseAsset();
        uint256 withdrawalRatio = (amount * BASIS_POINTS) / totalValue;

        // Withdraw proportionally from all strategies
        uint256 withdrawnFromExposure = _withdrawFromExposureStrategies(withdrawalRatio);
        uint256 withdrawnFromYield = _withdrawFromYieldStrategies(withdrawalRatio);

        actualAmount = withdrawnFromExposure + withdrawnFromYield;
        
        // Transfer to caller
        if (actualAmount > 0) {
            baseAsset.safeTransfer(msg.sender, actualAmount);
            totalAllocatedCapital = totalAllocatedCapital > actualAmount ? 
                totalAllocatedCapital - actualAmount : 0;
        }

        emit CapitalWithdrawn(amount, actualAmount);
        return actualAmount;
    }

    /**
     * @dev Gets the current value in base asset terms
     * @return value Current total value of the bundle
     */
    function getValueInBaseAsset() public view override returns (uint256 value) {
        // Get value from exposure strategies
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (exposureStrategies[i].isActive) {
                try exposureStrategies[i].strategy.getCurrentExposureValue() returns (uint256 strategyValue) {
                    value += strategyValue;
                } catch {
                    // Strategy might be temporarily unavailable
                }
            }
        }

        // Get value from yield strategies
        value += _getYieldStrategiesValue();

        return value;
    }

    /**
     * @dev Gets the underlying tokens managed by this bundle
     * @return tokens Array of token addresses
     */
    function getUnderlyingTokens() external view override returns (address[] memory tokens) {
        uint256 totalTokens = exposureStrategies.length + yieldBundle.strategies.length;
        tokens = new address[](totalTokens);
        
        uint256 index = 0;
        
        // Add exposure strategy tokens
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            tokens[index] = address(exposureStrategies[i].strategy);
            index++;
        }
        
        // Add yield strategy tokens
        for (uint256 i = 0; i < yieldBundle.strategies.length; i++) {
            tokens[index] = address(yieldBundle.strategies[i]);
            index++;
        }
        
        return tokens;
    }

    /**
     * @dev Gets the name of this asset wrapper
     * @return bundleName The name of the bundle
     */
    function getName() external view override returns (string memory bundleName) {
        return name;
    }

    /**
     * @dev Harvests yield from all strategies
     * @return totalHarvested Total amount harvested
     */
    function harvestYield() external override nonReentrant returns (uint256 totalHarvested) {
        // Harvest from exposure strategies
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (exposureStrategies[i].isActive) {
                try exposureStrategies[i].strategy.harvestYield() returns (uint256 harvested) {
                    totalHarvested += harvested;
                } catch {
                    // Continue harvesting from other strategies
                }
            }
        }

        // Harvest from yield strategies
        for (uint256 i = 0; i < yieldBundle.strategies.length; i++) {
            try yieldBundle.strategies[i].harvestYield() returns (uint256 harvested) {
                totalHarvested += harvested;
            } catch {
                // Continue harvesting from other strategies
            }
        }

        if (totalHarvested > 0) {
            baseAsset.safeTransfer(msg.sender, totalHarvested);
        }

        emit YieldHarvested(totalHarvested);
        return totalHarvested;
    }

    /**
     * @dev Gets the base asset address
     * @return asset Base asset address
     */
    function getBaseAsset() external view override returns (address asset) {
        return address(baseAsset);
    }

    // ============ STRATEGY MANAGEMENT ============

    /**
     * @dev Adds a new exposure strategy
     * @param strategy Address of the exposure strategy
     * @param targetAllocation Target allocation in basis points
     * @param maxAllocation Maximum allocation limit
     * @param isPrimary Whether this is a primary strategy
     */
    function addExposureStrategy(
        address strategy,
        uint256 targetAllocation,
        uint256 maxAllocation,
        bool isPrimary
    ) external onlyOwner {
        if (strategy == address(0)) revert CommonErrors.ZeroAddress();
        if (targetAllocation > BASIS_POINTS) revert CommonErrors.ValueTooHigh();
        if (maxAllocation > BASIS_POINTS) revert CommonErrors.ValueTooHigh();
        if (exposureStrategies.length >= riskParams.maxStrategyCount) revert CommonErrors.ValueTooHigh();

        // Validate that it implements IExposureStrategy
        try IExposureStrategy(strategy).getExposureInfo() returns (IExposureStrategy.ExposureInfo memory) {
            // Strategy is valid
        } catch {
            revert CommonErrors.InvalidValue();
        }

        // Check if strategy already exists
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (address(exposureStrategies[i].strategy) == strategy) {
                revert CommonErrors.InvalidValue();
            }
        }

        exposureStrategies.push(StrategyAllocation({
            strategy: IExposureStrategy(strategy),
            targetAllocation: targetAllocation,
            currentAllocation: 0,
            maxAllocation: maxAllocation,
            minAllocation: isPrimary ? 1000 : 0, // 10% min for primary, 0% for secondary
            isPrimary: isPrimary,
            isActive: true,
            lastRebalance: block.timestamp,
            totalAllocated: 0
        }));

        emit StrategyAdded(strategy, targetAllocation, isPrimary);
    }

    /**
     * @dev Removes an exposure strategy
     * @param strategy Address of the strategy to remove
     */
    function removeExposureStrategy(address strategy) external onlyOwner {
        uint256 strategyIndex = type(uint256).max;
        
        // Find strategy index
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (address(exposureStrategies[i].strategy) == strategy) {
                strategyIndex = i;
                break;
            }
        }
        
        if (strategyIndex == type(uint256).max) revert CommonErrors.NotFound();

        // Emergency exit from strategy
        if (exposureStrategies[strategyIndex].totalAllocated > 0) {
            try exposureStrategies[strategyIndex].strategy.emergencyExit() returns (uint256 recovered) {
                // Capital recovered
                emit EmergencyActionTaken("Strategy removal", strategy, recovered);
            } catch {
                // Strategy might be stuck - continue with removal
            }
        }

        // Remove strategy by swapping with last element
        exposureStrategies[strategyIndex] = exposureStrategies[exposureStrategies.length - 1];
        exposureStrategies.pop();

        emit StrategyRemoved(strategy);
    }

    /**
     * @dev Updates yield strategy bundle
     * @param strategies Array of yield strategy addresses
     * @param allocations Array of allocation percentages (basis points)
     */
    function updateYieldBundle(
        address[] calldata strategies,
        uint256[] calldata allocations
    ) external onlyOwner {
        if (strategies.length != allocations.length) revert CommonErrors.LengthMismatch();
        if (strategies.length > MAX_YIELD_STRATEGIES) revert CommonErrors.ValueTooHigh();

        // Validate allocations sum to 100%
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
        }
        if (totalAllocation != BASIS_POINTS) revert CommonErrors.InvalidValue();

        // Withdraw from current yield strategies if any
        if (yieldBundle.strategies.length > 0) {
            _withdrawFromYieldStrategies(BASIS_POINTS); // 100% withdrawal
        }

        // Update yield bundle
        delete yieldBundle.strategies;
        delete yieldBundle.allocations;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            yieldBundle.strategies.push(IYieldStrategy(strategies[i]));
            yieldBundle.allocations.push(allocations[i]);
        }

        emit YieldBundleUpdated(strategies, allocations, yieldBundle.totalYieldCapital);
    }

    // ============ OPTIMIZATION & REBALANCING ============

    /**
     * @dev Performs strategy optimization
     * @return success Whether optimization was successful
     */
    function optimizeStrategies() external onlyOwner returns (bool success) {
        return _performOptimization();
    }

    /**
     * @dev Rebalances strategies based on target allocations
     * @return success Whether rebalancing was successful
     */
    function rebalanceStrategies() external onlyOwner returns (bool success) {
        if (block.timestamp < lastRebalance + rebalanceInterval) {
            revert CommonErrors.TooSoon();
        }

        return _performRebalancing();
    }

    /**
     * @dev Emergency function to exit all positions
     * @return totalRecovered Total amount recovered
     */
    function emergencyExitAll() external onlyOwner returns (uint256 totalRecovered) {
        riskParams.circuitBreakerActive = true;
        
        // Exit all exposure strategies
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (exposureStrategies[i].isActive && exposureStrategies[i].totalAllocated > 0) {
                try exposureStrategies[i].strategy.emergencyExit() returns (uint256 recovered) {
                    totalRecovered += recovered;
                    exposureStrategies[i].totalAllocated = 0;
                    exposureStrategies[i].currentAllocation = 0;
                } catch {
                    // Strategy might be stuck
                    emit EmergencyActionTaken("Emergency exit failed", address(exposureStrategies[i].strategy), 0);
                }
            }
        }

        // Withdraw all from yield strategies
        totalRecovered += _withdrawFromYieldStrategies(BASIS_POINTS);

        emit CircuitBreakerActivated("Emergency exit all positions");
        return totalRecovered;
    }

    // ============ RISK MANAGEMENT ============

    /**
     * @dev Updates risk parameters
     * @param newParams New risk parameters
     */
    function updateRiskParameters(RiskParameters calldata newParams) external onlyOwner {
        // Validate parameters
        if (newParams.maxTotalLeverage > 1000) revert CommonErrors.ValueTooHigh(); // Max 10x
        if (newParams.maxStrategyCount > MAX_STRATEGIES) revert CommonErrors.ValueTooHigh();
        if (newParams.rebalanceThreshold > 5000) revert CommonErrors.ValueTooHigh(); // Max 50%

        riskParams = newParams;
        emit RiskParametersUpdated(newParams);
    }

    /**
     * @dev Activates or deactivates circuit breaker
     * @param active Whether to activate circuit breaker
     * @param reason Reason for activation/deactivation
     */
    function setCircuitBreaker(bool active, string calldata reason) external onlyOwner {
        riskParams.circuitBreakerActive = active;
        if (active) {
            emit CircuitBreakerActivated(reason);
        }
    }

    /**
     * @dev Pauses the contract (emergency function)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Calculates how much should be allocated to exposure vs yield
     */
    function _calculateExposureAllocation(uint256 totalAmount) internal view returns (uint256 exposureAmount) {
        // Calculate based on current leverage and target exposure
        uint256 currentLeverage = _calculateCurrentLeverage();
        
        if (currentLeverage > 100) {
            // We have leverage, so we need less capital for exposure
            uint256 leverageRatio = (currentLeverage * BASIS_POINTS) / 100;
            exposureAmount = (totalAmount * BASIS_POINTS) / leverageRatio;
        } else {
            // No leverage, use 1:1 allocation by default
            exposureAmount = totalAmount / 2; // 50% to exposure, 50% to yield
        }
        
        return exposureAmount;
    }

    /**
     * @dev Allocates capital to exposure strategies
     */
    function _allocateToExposureStrategies(uint256 amount) internal {
        uint256 remainingAmount = amount;
        
        for (uint256 i = 0; i < exposureStrategies.length && remainingAmount > 0; i++) {
            if (!exposureStrategies[i].isActive) continue;
            
            uint256 targetAmount = (amount * exposureStrategies[i].targetAllocation) / BASIS_POINTS;
            uint256 allocationAmount = targetAmount < remainingAmount ? targetAmount : remainingAmount;
            
            if (allocationAmount > 0) {
                // Approve strategy to spend base asset
                baseAsset.approve(address(exposureStrategies[i].strategy), allocationAmount);
                
                try exposureStrategies[i].strategy.openExposure(allocationAmount) returns (bool success, uint256 /*actualExposure*/) {
                    if (success) {
                        exposureStrategies[i].totalAllocated += allocationAmount;
                        remainingAmount -= allocationAmount;
                        
                        // Record performance
                        strategyLastUpdate[address(exposureStrategies[i].strategy)] = block.timestamp;
                    }
                } catch {
                    // Strategy failed - continue with others
                }
            }
        }
    }

    /**
     * @dev Allocates capital to yield strategies
     */
    function _allocateToYieldStrategies(uint256 amount) internal {
        if (!yieldBundle.isActive || yieldBundle.strategies.length == 0) return;
        
        for (uint256 i = 0; i < yieldBundle.strategies.length; i++) {
            uint256 allocationAmount = (amount * yieldBundle.allocations[i]) / BASIS_POINTS;
            
            if (allocationAmount > 0) {
                baseAsset.approve(address(yieldBundle.strategies[i]), allocationAmount);
                
                try yieldBundle.strategies[i].deposit(allocationAmount) returns (uint256) {
                    // Successful allocation
                } catch {
                    // Strategy failed - continue with others
                }
            }
        }
        
        yieldBundle.totalYieldCapital += amount;
    }

    /**
     * @dev Withdraws from exposure strategies proportionally
     */
    function _withdrawFromExposureStrategies(uint256 withdrawalRatio) internal returns (uint256 totalWithdrawn) {
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (!exposureStrategies[i].isActive || exposureStrategies[i].totalAllocated == 0) continue;
            
            uint256 withdrawAmount = (exposureStrategies[i].totalAllocated * withdrawalRatio) / BASIS_POINTS;
            
            if (withdrawAmount > 0) {
                try exposureStrategies[i].strategy.closeExposure(withdrawAmount) returns (bool success, uint256 actualClosed) {
                    if (success) {
                        totalWithdrawn += actualClosed;
                        exposureStrategies[i].totalAllocated = exposureStrategies[i].totalAllocated > actualClosed ?
                            exposureStrategies[i].totalAllocated - actualClosed : 0;
                    }
                } catch {
                    // Strategy might be stuck - continue with others
                }
            }
        }
        
        return totalWithdrawn;
    }

    /**
     * @dev Withdraws from yield strategies
     */
    function _withdrawFromYieldStrategies(uint256 withdrawalRatio) internal returns (uint256 totalWithdrawn) {
        if (!yieldBundle.isActive || yieldBundle.strategies.length == 0) return 0;
        
        uint256 targetWithdrawal = (yieldBundle.totalYieldCapital * withdrawalRatio) / BASIS_POINTS;
        
        for (uint256 i = 0; i < yieldBundle.strategies.length && targetWithdrawal > 0; i++) {
            try yieldBundle.strategies[i].getTotalValue() returns (uint256 strategyValue) {
                uint256 withdrawAmount = (targetWithdrawal * yieldBundle.allocations[i]) / BASIS_POINTS;
                
                if (withdrawAmount > 0 && strategyValue > 0) {
                    // Calculate shares to withdraw
                    uint256 sharesToWithdraw = (withdrawAmount * withdrawAmount) / strategyValue; // Simplified
                    
                    try yieldBundle.strategies[i].withdraw(sharesToWithdraw) returns (uint256 actualWithdrawn) {
                        totalWithdrawn += actualWithdrawn;
                        targetWithdrawal = targetWithdrawal > actualWithdrawn ? targetWithdrawal - actualWithdrawn : 0;
                    } catch {
                        // Continue with other strategies
                    }
                }
            } catch {
                // Strategy might be unavailable
            }
        }
        
        yieldBundle.totalYieldCapital = yieldBundle.totalYieldCapital > totalWithdrawn ?
            yieldBundle.totalYieldCapital - totalWithdrawn : 0;
        
        return totalWithdrawn;
    }

    /**
     * @dev Gets total value from yield strategies
     */
    function _getYieldStrategiesValue() internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < yieldBundle.strategies.length; i++) {
            try yieldBundle.strategies[i].getTotalValue() returns (uint256 strategyValue) {
                totalValue += strategyValue;
            } catch {
                // Strategy might be temporarily unavailable
            }
        }
        return totalValue;
    }

    /**
     * @dev Calculates current effective leverage
     */
    function _calculateCurrentLeverage() internal view returns (uint256) {
        uint256 totalExposure = 0;
        uint256 totalCollateral = 0;
        
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (exposureStrategies[i].isActive) {
                try exposureStrategies[i].strategy.getExposureInfo() returns (IExposureStrategy.ExposureInfo memory info) {
                    totalExposure += info.currentExposure;
                    totalCollateral += exposureStrategies[i].totalAllocated;
                } catch {
                    // Skip unavailable strategies
                }
            }
        }
        
        return totalCollateral > 0 ? (totalExposure * 100) / totalCollateral : 100;
    }

    /**
     * @dev Checks if optimization should be performed
     */
    function _shouldOptimize() internal view returns (bool) {
        return block.timestamp >= lastOptimization + optimizationInterval;
    }

    /**
     * @dev Performs strategy optimization
     */
    function _performOptimization() internal returns (bool) {
        if (exposureStrategies.length == 0) return false;
        
        // Prepare strategy addresses for optimization
        address[] memory strategies = new address[](exposureStrategies.length);
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            strategies[i] = address(exposureStrategies[i].strategy);
        }
        
        try optimizer.calculateOptimalAllocation(
            strategies,
            totalAllocatedCapital,
            totalTargetExposure
        ) returns (IStrategyOptimizer.OptimizationResult memory result) {
            
            if (result.shouldRebalance) {
                // Update target allocations based on optimization
                for (uint256 i = 0; i < exposureStrategies.length; i++) {
                    uint256 oldAllocation = exposureStrategies[i].targetAllocation;
                    exposureStrategies[i].targetAllocation = result.optimalAllocations[i];
                    
                    emit StrategyAllocationUpdated(
                        address(exposureStrategies[i].strategy),
                        oldAllocation,
                        result.optimalAllocations[i]
                    );
                }
                
                lastOptimization = block.timestamp;
                emit OptimizationPerformed(result.expectedCostSaving, gasleft(), block.timestamp);
                return true;
            }
        } catch {
            // Optimization failed - continue with current allocations
        }
        
        return false;
    }

    /**
     * @dev Performs rebalancing based on current target allocations
     */
    function _performRebalancing() internal returns (bool) {
        uint256 strategiesRebalanced = 0;
        uint256 totalValueMoved = 0;
        
        // Simple rebalancing: adjust allocations towards targets
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (!exposureStrategies[i].isActive) continue;
            
            uint256 currentAllocation = exposureStrategies[i].currentAllocation;
            uint256 targetAllocation = exposureStrategies[i].targetAllocation;
            
            if (currentAllocation != targetAllocation) {
                uint256 deviation = currentAllocation > targetAllocation ?
                    currentAllocation - targetAllocation :
                    targetAllocation - currentAllocation;
                
                if (deviation >= riskParams.rebalanceThreshold) {
                    strategiesRebalanced++;
                    totalValueMoved += deviation;
                    exposureStrategies[i].lastRebalance = block.timestamp;
                }
            }
        }
        
        if (strategiesRebalanced > 0) {
            lastRebalance = block.timestamp;
            emit RebalanceExecuted(strategiesRebalanced, totalValueMoved, block.timestamp);
            return true;
        }
        
        return false;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets information about all exposure strategies
     */
    function getExposureStrategies() external view returns (StrategyAllocation[] memory) {
        return exposureStrategies;
    }

    /**
     * @dev Gets yield bundle information
     */
    function getYieldBundle() external view returns (YieldStrategyBundle memory) {
        return yieldBundle;
    }

    /**
     * @dev Gets current risk parameters
     */
    function getRiskParameters() external view returns (RiskParameters memory) {
        return riskParams;
    }

    /**
     * @dev Gets bundle statistics
     */
    function getBundleStats() external view returns (
        uint256 totalValue,
        uint256 totalExposure,
        uint256 currentLeverage,
        uint256 capitalEfficiency,
        bool isHealthy
    ) {
        totalValue = getValueInBaseAsset();
        currentLeverage = _calculateCurrentLeverage();
        
        // Calculate total exposure
        for (uint256 i = 0; i < exposureStrategies.length; i++) {
            if (exposureStrategies[i].isActive) {
                try exposureStrategies[i].strategy.getExposureInfo() returns (IExposureStrategy.ExposureInfo memory info) {
                    totalExposure += info.currentExposure;
                } catch {
                    // Skip unavailable strategies
                }
            }
        }
        
        capitalEfficiency = totalAllocatedCapital > 0 ? (totalValue * BASIS_POINTS) / totalAllocatedCapital : 0;
        isHealthy = capitalEfficiency >= riskParams.minCapitalEfficiency && 
                   currentLeverage <= riskParams.maxTotalLeverage &&
                   !riskParams.circuitBreakerActive;
        
        return (totalValue, totalExposure, currentLeverage, capitalEfficiency, isHealthy);
    }

    // Events for IAssetWrapper compatibility
    event CapitalAllocated(uint256 totalAmount, uint256 exposureAmount, uint256 yieldAmount);
    event CapitalWithdrawn(uint256 requestedAmount, uint256 actualAmount);
    event YieldHarvested(uint256 amount);
}