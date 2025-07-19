// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IExposureStrategy} from "../interfaces/IExposureStrategy.sol";
import {ITRSProvider} from "../interfaces/ITRSProvider.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title TRSExposureStrategy
 * @dev Total Return Swap strategy for RWA exposure with counterparty risk management
 * @notice Provides leveraged RWA exposure through TRS contracts with multiple counterparties
 */
contract TRSExposureStrategy is IExposureStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_COUNTERPARTIES = 5;
    uint256 public constant MAX_CONTRACTS_PER_COUNTERPARTY = 10;
    uint256 public constant QUOTE_VALIDITY_PERIOD = 10 minutes;

    // Core configuration
    IERC20 public immutable baseAsset;
    ITRSProvider public trsProvider;
    IPriceOracle public priceOracle;
    bytes32 public underlyingAssetId;
    string public strategyName;

    // Strategy state
    bytes32[] public activeTRSContracts;
    mapping(bytes32 => bool) public isActiveContract;
    uint256 public totalExposureAmount;
    uint256 public totalCollateralDeployed;
    uint256 public totalCapitalAllocated;

    // Risk management
    RiskParameters public riskParams;

    // Counterparty management
    struct CounterpartyAllocation {
        address counterparty;
        uint256 targetAllocation; // Basis points
        uint256 currentExposure;
        uint256 maxExposure;
        bool isActive;
        uint256 lastQuoteTime;
    }

    CounterpartyAllocation[] public counterpartyAllocations;
    mapping(address => uint256) public counterpartyIndex; // counterparty => index + 1 (0 = not found)

    // Contract management
    struct TRSContractInfo {
        bytes32 contractId;
        address counterparty;
        uint256 notionalAmount;
        uint256 collateralAmount;
        uint256 creationTime;
        uint256 maturityTime;
        ITRSProvider.TRSStatus lastKnownStatus;
    }

    mapping(bytes32 => TRSContractInfo) public contractInfo;

    // Performance tracking
    uint256 public totalBorrowCosts;
    uint256 public totalRealizedPnL;
    uint256 public lastRebalanceTime;
    uint256 public contractCreationCount;

    // Configuration
    uint256 public preferredMaturityDuration = 90 days; // 3 months default
    uint256 public maxSingleContractSize = 1000000e6; // $1M max per contract
    uint256 public rebalanceThreshold = 500; // 5% deviation triggers rebalance
    uint256 public counterpartyConcentrationLimit = 4000; // 40% max per counterparty

    // Events
    event TRSContractCreated(bytes32 indexed contractId, address indexed counterparty, uint256 notionalAmount, uint256 collateralAmount);
    event TRSContractSettled(bytes32 indexed contractId, uint256 finalValue, int256 realizedPnL);
    event CounterpartyAdded(address indexed counterparty, uint256 targetAllocation, uint256 maxExposure);
    event CounterpartyRemoved(address indexed counterparty);
    event ContractsRebalanced(uint256 contractsSettled, uint256 contractsCreated, uint256 totalGasUsed);
    event CollateralOptimized(bytes32 indexed contractId, uint256 collateralBefore, uint256 collateralAfter);

    /**
     * @dev Constructor
     * @param _baseAsset Base asset for collateral (e.g., USDC)
     * @param _trsProvider TRS provider contract
     * @param _priceOracle Price oracle for valuations
     * @param _underlyingAssetId Asset identifier for TRS exposure (e.g., "SP500")
     * @param _strategyName Human readable strategy name
     */
    constructor(
        address _baseAsset,
        address _trsProvider,
        address _priceOracle,
        bytes32 _underlyingAssetId,
        string memory _strategyName
    ) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        if (_trsProvider == address(0)) revert CommonErrors.ZeroAddress();
        if (_priceOracle == address(0)) revert CommonErrors.ZeroAddress();
        if (bytes(_strategyName).length == 0) revert CommonErrors.EmptyString();

        baseAsset = IERC20(_baseAsset);
        trsProvider = ITRSProvider(_trsProvider);
        priceOracle = IPriceOracle(_priceOracle);
        underlyingAssetId = _underlyingAssetId;
        strategyName = _strategyName;

        // Initialize risk parameters
        riskParams = RiskParameters({
            maxLeverage: 300,            // 3x max leverage
            maxPositionSize: 5000000e6,  // $5M max position
            liquidationBuffer: 2000,     // 20% liquidation buffer
            rebalanceThreshold: 500,     // 5% rebalance threshold
            slippageLimit: 300,          // 3% max slippage
            emergencyExitEnabled: true
        });

        lastRebalanceTime = block.timestamp;
    }

    // ============ IEXPOSURESTRATEGY IMPLEMENTATION ============

    function getExposureInfo() external view override returns (ExposureInfo memory info) {
        uint256 currentLeverage = _calculateCurrentLeverage();
        uint256 currentCost = _calculateCurrentCost();
        uint256 riskScore = _calculateRiskScore();

        info = ExposureInfo({
            strategyType: StrategyType.TRS,
            name: strategyName,
            underlyingAsset: _getUnderlyingAsset(),
            leverage: currentLeverage,
            collateralRatio: _calculateCollateralRatio(currentLeverage),
            currentExposure: totalExposureAmount,
            maxCapacity: riskParams.maxPositionSize,
            currentCost: currentCost,
            riskScore: riskScore,
            isActive: activeTRSContracts.length > 0,
            liquidationPrice: 0 // TRS doesn't have direct liquidation price
        });
    }

    function getCostBreakdown() external view override returns (CostBreakdown memory costs) {
        (uint256 avgBorrowRate, uint256 counterpartySpread) = _calculateAverageBorrowRate();
        uint256 managementFee = 20; // 0.20% annual management fee
        uint256 gasCost = _estimateGasCost();

        costs = CostBreakdown({
            fundingRate: 0, // Not applicable for TRS
            borrowRate: avgBorrowRate,
            managementFee: managementFee,
            slippageCost: counterpartySpread,
            gasCost: gasCost,
            totalCostBps: avgBorrowRate + managementFee + counterpartySpread + gasCost,
            lastUpdated: block.timestamp
        });
    }

    function getRiskParameters() external view override returns (RiskParameters memory) {
        return riskParams;
    }

    function estimateExposureCost(uint256 amount, uint256 timeHorizon) external view override returns (uint256 estimatedCost) {
        if (amount == 0 || timeHorizon == 0) return 0;

        // Get best available quote to estimate costs
        ITRSProvider.TRSQuote[] memory quotes = trsProvider.getQuotesForEstimation(
            underlyingAssetId,
            amount,
            preferredMaturityDuration,
            200 // 2x leverage
        );

        if (quotes.length == 0) return type(uint256).max; // No quotes available

        // Find best quote (lowest borrow rate)
        uint256 bestRate = type(uint256).max;
        for (uint256 i = 0; i < quotes.length; i++) {
            if (quotes[i].borrowRate < bestRate) {
                bestRate = quotes[i].borrowRate;
            }
        }

        // Calculate time-based cost
        uint256 annualCost = (amount * bestRate) / BASIS_POINTS;
        uint256 timeBasedCost = (annualCost * timeHorizon) / 365 days;
        
        // Add management fee
        uint256 managementCost = (amount * 20 * timeHorizon) / (BASIS_POINTS * 365 days);
        
        return timeBasedCost + managementCost;
    }

    function getCurrentExposureValue() external view override returns (uint256 value) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            bytes32 contractId = activeTRSContracts[i];
            try trsProvider.getMarkToMarketValue(contractId) returns (uint256 contractValue, int256) {
                totalValue += contractValue;
            } catch {
                // If we can't get MTM, use notional amount as fallback
                TRSContractInfo memory info = contractInfo[contractId];
                totalValue += info.notionalAmount;
            }
        }
        
        return totalValue;
    }

    function getCollateralRequired(uint256 exposureAmount) external view override returns (uint256 collateralRequired) {
        if (exposureAmount == 0) return 0;
        
        // Get quotes to find best collateral requirement
        ITRSProvider.TRSQuote[] memory quotes = trsProvider.getQuotesForEstimation(
            underlyingAssetId,
            exposureAmount,
            preferredMaturityDuration,
            200 // 2x leverage
        );

        if (quotes.length == 0) return exposureAmount; // 100% collateral if no quotes

        // Find minimum collateral requirement
        uint256 minCollateral = type(uint256).max;
        for (uint256 i = 0; i < quotes.length; i++) {
            uint256 required = (exposureAmount * quotes[i].collateralRequirement) / BASIS_POINTS;
            if (required < minCollateral) {
                minCollateral = required;
            }
        }

        return minCollateral;
    }

    function getLiquidationPrice() external pure override returns (uint256) {
        return 0; // TRS contracts don't have direct liquidation prices
    }

    function canHandleExposure(uint256 amount) external view override returns (bool canHandle, string memory reason) {
        if (amount == 0) return (false, "Amount cannot be zero");
        
        if (totalExposureAmount + amount > riskParams.maxPositionSize) {
            return (false, "Would exceed maximum position size");
        }

        // Check if we have active counterparties
        uint256 activeCounterparties = 0;
        for (uint256 i = 0; i < counterpartyAllocations.length; i++) {
            if (counterpartyAllocations[i].isActive) {
                activeCounterparties++;
            }
        }
        
        if (activeCounterparties == 0) {
            return (false, "No active counterparties available");
        }

        // Try to get quotes to see if exposure is feasible
        try trsProvider.getQuotesForEstimation(underlyingAssetId, amount, preferredMaturityDuration, 200) returns (ITRSProvider.TRSQuote[] memory quotes) {
            if (quotes.length == 0) {
                return (false, "No counterparties willing to provide quotes");
            }
            return (true, "");
        } catch {
            return (false, "Unable to request quotes from TRS provider");
        }
    }

    // ============ STATE-CHANGING FUNCTIONS ============

    function openExposure(uint256 amount) external override nonReentrant returns (bool success, uint256 actualExposure) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Check capacity
        (bool canHandle, ) = this.canHandleExposure(amount);
        if (!canHandle) revert CommonErrors.OperationFailed();

        // Transfer base asset from caller
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Get quotes from TRS provider
        ITRSProvider.TRSQuote[] memory quotes = trsProvider.requestQuotes(
            underlyingAssetId,
            amount,
            preferredMaturityDuration,
            200 // 2x leverage
        );

        if (quotes.length == 0) revert CommonErrors.OperationFailed();

        // Select best quote (lowest borrow rate with acceptable counterparty)
        (ITRSProvider.TRSQuote memory bestQuote, bool found) = _selectBestQuote(quotes, amount);
        if (!found) revert CommonErrors.OperationFailed();

        // Calculate collateral needed
        uint256 collateralNeeded = (amount * bestQuote.collateralRequirement) / BASIS_POINTS;
        if (collateralNeeded > amount) revert CommonErrors.InsufficientBalance();

        // Approve TRS provider to spend collateral
        baseAsset.approve(address(trsProvider), collateralNeeded);

        // Create TRS contract
        try trsProvider.createTRSContract(bestQuote.quoteId, collateralNeeded) returns (bytes32 contractId) {
            // Store contract info
            uint256 notionalAmount = (collateralNeeded * BASIS_POINTS) / bestQuote.collateralRequirement;
            
            contractInfo[contractId] = TRSContractInfo({
                contractId: contractId,
                counterparty: bestQuote.counterparty,
                notionalAmount: notionalAmount,
                collateralAmount: collateralNeeded,
                creationTime: block.timestamp,
                maturityTime: block.timestamp + preferredMaturityDuration,
                lastKnownStatus: ITRSProvider.TRSStatus.ACTIVE
            });

            // Update state
            activeTRSContracts.push(contractId);
            isActiveContract[contractId] = true;
            totalExposureAmount += notionalAmount;
            totalCollateralDeployed += collateralNeeded;
            totalCapitalAllocated += amount;
            contractCreationCount++;

            // Update counterparty allocation
            _updateCounterpartyExposure(bestQuote.counterparty, notionalAmount, true);

            // Return unused capital to caller
            uint256 unusedCapital = amount - collateralNeeded;
            if (unusedCapital > 0) {
                baseAsset.safeTransfer(msg.sender, unusedCapital);
            }

            emit ExposureOpened(amount, notionalAmount, collateralNeeded);
            emit TRSContractCreated(contractId, bestQuote.counterparty, notionalAmount, collateralNeeded);

            return (true, notionalAmount);
        } catch {
            revert CommonErrors.OperationFailed();
        }
    }

    function _closeExposureInternal(uint256 amount) internal returns (bool success, uint256 actualClosed) {
        if (amount == 0) return (false, 0);
        if (amount > totalExposureAmount) return (false, 0);

        uint256 remainingToClose = amount;
        uint256 totalRecovered = 0;

        // Close contracts starting from smallest to largest
        bytes32[] memory sortedContracts = _sortContractsBySize();
        
        for (uint256 i = 0; i < sortedContracts.length && remainingToClose > 0; i++) {
            bytes32 contractId = sortedContracts[i];
            if (!isActiveContract[contractId]) continue;

            TRSContractInfo memory info = contractInfo[contractId];
            
            // Always try to close the contract if we need to close any amount
            // TRS contracts typically need to be closed entirely
            try trsProvider.terminateContract(contractId) returns (uint256 finalValue, uint256 collateralReturned) {
                totalRecovered += collateralReturned;
                
                // Determine how much exposure we actually closed
                uint256 exposureClosed = info.notionalAmount > remainingToClose ? 
                    remainingToClose : info.notionalAmount;
                remainingToClose = remainingToClose > exposureClosed ? 
                    remainingToClose - exposureClosed : 0;
                
                _removeActiveContract(contractId);
                _updateCounterpartyExposure(info.counterparty, info.notionalAmount, false);
                
                // Calculate realized P&L
                int256 realizedPnL = int256(finalValue) - int256(info.notionalAmount);
                totalRealizedPnL = realizedPnL >= 0 ? 
                    totalRealizedPnL + uint256(realizedPnL) : 
                    totalRealizedPnL;

                emit TRSContractSettled(contractId, finalValue, realizedPnL);
                
                // If this contract was larger than what we wanted to close, break
                if (info.notionalAmount >= amount) {
                    break;
                }
            } catch {
                // Skip failed contract and continue
                continue;
            }
        }

        actualClosed = amount - remainingToClose;
        
        // Update state
        totalExposureAmount = totalExposureAmount > actualClosed ? totalExposureAmount - actualClosed : 0;
        totalCollateralDeployed = totalCollateralDeployed > totalRecovered ? 
            totalCollateralDeployed - totalRecovered : 0;
        totalCapitalAllocated = totalCapitalAllocated > actualClosed ?
            totalCapitalAllocated - actualClosed : 0;

        // Transfer recovered assets to caller
        if (totalRecovered > 0) {
            baseAsset.safeTransfer(msg.sender, totalRecovered);
        }

        emit ExposureClosed(amount, actualClosed, totalRecovered);
        return (true, actualClosed);
    }

    function closeExposure(uint256 amount) external override nonReentrant returns (bool success, uint256 actualClosed) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (amount > totalExposureAmount) revert CommonErrors.InsufficientBalance();

        return _closeExposureInternal(amount);
    }

    function adjustExposure(int256 delta) external override nonReentrant returns (bool success, uint256 newExposure) {
        if (delta == 0) return (true, totalExposureAmount);
        
        if (delta > 0) {
            // Transfer tokens from user first
            baseAsset.safeTransferFrom(msg.sender, address(this), uint256(delta));
            
            // Use internal implementation to avoid reentrancy and msg.sender issues
            try this._openExposureWithTokens(uint256(delta)) returns (bool _success, uint256 _actualExposure) {
                success = _success;
            } catch {
                success = false;
            }
        } else {
            uint256 reduceAmount = uint256(-delta);
            if (reduceAmount <= totalExposureAmount) {
                (success, ) = _closeExposureInternal(reduceAmount);
            } else {
                success = false;
            }
        }
        
        newExposure = totalExposureAmount;
        emit ExposureAdjusted(delta, newExposure);
        
        return (success, newExposure);
    }

    function harvestYield() external override nonReentrant returns (uint256 harvested) {
        // TRS contracts don't generate harvestable yield - P&L is realized on settlement
        // This function marks all contracts to market and returns 0
        
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            bytes32 contractId = activeTRSContracts[i];
            try trsProvider.markToMarket(contractId) {
                // Mark to market successful
            } catch {
                // Continue with other contracts
            }
        }
        
        emit YieldHarvested(0);
        return 0;
    }

    function emergencyExit() external override nonReentrant returns (uint256 recovered) {
        if (!riskParams.emergencyExitEnabled) revert CommonErrors.NotAllowed();
        
        uint256 totalRecovered = 0;
        
        // Terminate all active contracts
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            bytes32 contractId = activeTRSContracts[i];
            if (!isActiveContract[contractId]) continue;
            
            try trsProvider.terminateContract(contractId) returns (uint256, uint256 collateralReturned) {
                totalRecovered += collateralReturned;
                isActiveContract[contractId] = false;
            } catch {
                // Contract might be stuck - continue with others
            }
        }
        
        // Reset state
        delete activeTRSContracts;
        totalExposureAmount = 0;
        totalCollateralDeployed = 0;
        
        // Transfer all recovered assets
        if (totalRecovered > 0) {
            baseAsset.safeTransfer(msg.sender, totalRecovered);
        }
        
        emit EmergencyExit(totalRecovered, "TRS strategy emergency exit");
        return totalRecovered;
    }

    function updateRiskParameters(RiskParameters calldata newParams) external override onlyOwner {
        // Validate parameters
        if (newParams.maxLeverage > 1000) revert CommonErrors.ValueTooHigh(); // Max 10x
        if (newParams.slippageLimit > 1000) revert CommonErrors.ValueTooHigh(); // Max 10%
        
        riskParams = newParams;
        emit RiskParametersUpdated(newParams);
    }

    // ============ TRS-SPECIFIC FUNCTIONS ============

    /**
     * @dev Adds a counterparty for TRS allocation
     */
    function addCounterparty(
        address counterparty,
        uint256 targetAllocation,
        uint256 maxExposure
    ) external onlyOwner {
        if (counterparty == address(0)) revert CommonErrors.ZeroAddress();
        if (targetAllocation > BASIS_POINTS) revert CommonErrors.ValueTooHigh();
        if (counterpartyAllocations.length >= MAX_COUNTERPARTIES) revert CommonErrors.ValueTooHigh();
        if (counterpartyIndex[counterparty] != 0) revert CommonErrors.AlreadyExists();

        // Verify counterparty exists in TRS provider
        try trsProvider.getCounterpartyInfo(counterparty) {
            // Counterparty exists
        } catch {
            revert CommonErrors.NotFound();
        }

        counterpartyAllocations.push(CounterpartyAllocation({
            counterparty: counterparty,
            targetAllocation: targetAllocation,
            currentExposure: 0,
            maxExposure: maxExposure,
            isActive: true,
            lastQuoteTime: 0
        }));

        counterpartyIndex[counterparty] = counterpartyAllocations.length; // Store index + 1

        emit CounterpartyAdded(counterparty, targetAllocation, maxExposure);
    }

    /**
     * @dev Removes a counterparty
     */
    function removeCounterparty(address counterparty) external onlyOwner {
        uint256 index = counterpartyIndex[counterparty];
        if (index == 0) revert CommonErrors.NotFound();
        
        index--; // Convert back to actual index
        
        CounterpartyAllocation memory allocation = counterpartyAllocations[index];
        if (allocation.currentExposure > 0) revert CommonErrors.InvalidState();

        // Remove by swapping with last element
        counterpartyAllocations[index] = counterpartyAllocations[counterpartyAllocations.length - 1];
        counterpartyIndex[counterpartyAllocations[index].counterparty] = index + 1;
        
        counterpartyAllocations.pop();
        delete counterpartyIndex[counterparty];

        emit CounterpartyRemoved(counterparty);
    }

    /**
     * @dev Rebalances TRS contracts across counterparties
     */
    function rebalanceContracts() external onlyOwner returns (bool success) {
        if (block.timestamp < lastRebalanceTime + 1 hours) revert CommonErrors.TooSoon();
        
        uint256 gasStart = gasleft();
        uint256 contractsSettled = 0;
        uint256 contractsCreated = 0;

        // Check for matured contracts and settle them
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            bytes32 contractId = activeTRSContracts[i];
            if (!isActiveContract[contractId]) continue;
            
            TRSContractInfo memory info = contractInfo[contractId];
            
            if (block.timestamp >= info.maturityTime) {
                try trsProvider.settleContract(contractId) returns (uint256 finalValue, uint256 /*collateralReturned*/) {
                    contractsSettled++;
                    _removeActiveContract(contractId);
                    _updateCounterpartyExposure(info.counterparty, info.notionalAmount, false);
                    
                    int256 realizedPnL = int256(finalValue) - int256(info.notionalAmount);
                    totalRealizedPnL = realizedPnL >= 0 ? 
                        totalRealizedPnL + uint256(realizedPnL) : 
                        totalRealizedPnL;

                    emit TRSContractSettled(contractId, finalValue, realizedPnL);
                } catch {
                    // Settlement failed - contract might be stuck
                }
            }
        }

        lastRebalanceTime = block.timestamp;
        uint256 gasUsed = gasStart - gasleft();
        
        emit ContractsRebalanced(contractsSettled, contractsCreated, gasUsed);
        return true;
    }

    /**
     * @dev Optimizes collateral across active contracts
     */
    function optimizeCollateral() external onlyOwner returns (uint256 totalOptimized) {
        uint256 optimized = 0;
        
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            bytes32 contractId = activeTRSContracts[i];
            if (!isActiveContract[contractId]) continue;
            
            TRSContractInfo memory info = contractInfo[contractId];
            
            // Get current mark-to-market
            try trsProvider.getMarkToMarketValue(contractId) returns (uint256 /*currentValue*/, int256 unrealizedPnL) {
                // Calculate optimal collateral
                uint256 requiredCollateral = trsProvider.calculateCollateralRequirement(
                    info.counterparty,
                    info.notionalAmount,
                    200 // 2x leverage
                );
                
                // If we have significant excess collateral, withdraw some
                if (info.collateralAmount > requiredCollateral * 120 / 100) { // 20% buffer
                    uint256 excessCollateral = info.collateralAmount - requiredCollateral * 110 / 100; // Keep 10% buffer
                    
                    try trsProvider.withdrawCollateral(contractId, excessCollateral) {
                        contractInfo[contractId].collateralAmount -= excessCollateral;
                        optimized += excessCollateral;
                        
                        emit CollateralOptimized(contractId, info.collateralAmount, info.collateralAmount - excessCollateral);
                    } catch {
                        // Withdrawal failed - continue with other contracts
                    }
                }
                
                // If unrealized P&L is significantly negative, might need to post more collateral
                if (unrealizedPnL < 0 && uint256(-unrealizedPnL) > info.collateralAmount / 4) {
                    uint256 additionalCollateral = uint256(-unrealizedPnL) / 2; // Post half the loss as additional collateral
                    
                    if (baseAsset.balanceOf(address(this)) >= additionalCollateral) {
                        baseAsset.approve(address(trsProvider), additionalCollateral);
                        
                        try trsProvider.postCollateral(contractId, additionalCollateral) {
                            contractInfo[contractId].collateralAmount += additionalCollateral;
                            
                            emit CollateralOptimized(contractId, info.collateralAmount, info.collateralAmount + additionalCollateral);
                        } catch {
                            // Posting failed - continue
                        }
                    }
                }
            } catch {
                // MTM failed - continue with other contracts
            }
        }
        
        return optimized;
    }

    // ============ VIEW FUNCTIONS ============

    function getActiveTRSContracts() external view returns (bytes32[] memory) {
        return activeTRSContracts;
    }

    function getCounterpartyAllocations() external view returns (CounterpartyAllocation[] memory) {
        return counterpartyAllocations;
    }

    function getTRSContractInfo(bytes32 contractId) external view returns (TRSContractInfo memory) {
        return contractInfo[contractId];
    }

    function getStrategyPerformance() external view returns (
        uint256 totalContracts,
        uint256 totalBorrowCostsPaid,
        uint256 totalRealizedPnLAmount,
        uint256 averageContractDuration
    ) {
        totalContracts = contractCreationCount;
        totalBorrowCostsPaid = totalBorrowCosts;
        totalRealizedPnLAmount = totalRealizedPnL;
        
        if (activeTRSContracts.length > 0) {
            uint256 totalDuration = 0;
            for (uint256 i = 0; i < activeTRSContracts.length; i++) {
                bytes32 contractId = activeTRSContracts[i];
                TRSContractInfo memory info = contractInfo[contractId];
                totalDuration += (block.timestamp - info.creationTime);
            }
            averageContractDuration = totalDuration / activeTRSContracts.length;
        }
    }

    // ============ INTERNAL FUNCTIONS ============

    function _openExposureWithTokens(uint256 amount) external returns (bool success, uint256 actualExposure) {
        // This function is called internally via external call to avoid reentrancy issues
        // The tokens should already be in the contract
        require(msg.sender == address(this), "Only self-call allowed");
        
        if (amount == 0) return (false, 0);
        
        // Check capacity
        (bool canHandle, ) = this.canHandleExposure(amount);
        if (!canHandle) return (false, 0);

        // Get quotes from TRS provider
        ITRSProvider.TRSQuote[] memory quotes = trsProvider.requestQuotes(
            underlyingAssetId,
            amount,
            preferredMaturityDuration,
            200 // 2x leverage
        );

        if (quotes.length == 0) return (false, 0);

        // Select best quote (lowest borrow rate with acceptable counterparty)
        (ITRSProvider.TRSQuote memory bestQuote, bool found) = _selectBestQuote(quotes, amount);
        if (!found) return (false, 0);

        // Calculate collateral needed
        uint256 collateralNeeded = (amount * bestQuote.collateralRequirement) / BASIS_POINTS;
        if (collateralNeeded > amount) return (false, 0);

        // Approve TRS provider to spend collateral
        baseAsset.approve(address(trsProvider), collateralNeeded);

        // Create TRS contract
        try trsProvider.createTRSContract(bestQuote.quoteId, collateralNeeded) returns (bytes32 contractId) {
            // Store contract info
            uint256 notionalAmount = (collateralNeeded * BASIS_POINTS) / bestQuote.collateralRequirement;
            
            contractInfo[contractId] = TRSContractInfo({
                contractId: contractId,
                counterparty: bestQuote.counterparty,
                notionalAmount: notionalAmount,
                collateralAmount: collateralNeeded,
                creationTime: block.timestamp,
                maturityTime: block.timestamp + preferredMaturityDuration,
                lastKnownStatus: ITRSProvider.TRSStatus.ACTIVE
            });

            // Update state
            activeTRSContracts.push(contractId);
            isActiveContract[contractId] = true;
            totalExposureAmount += notionalAmount;
            totalCollateralDeployed += collateralNeeded;
            totalCapitalAllocated += amount;
            contractCreationCount++;

            // Update counterparty allocation
            _updateCounterpartyExposure(bestQuote.counterparty, notionalAmount, true);

            // Return unused capital to caller
            uint256 unusedCapital = amount - collateralNeeded;
            if (unusedCapital > 0) {
                baseAsset.safeTransfer(msg.sender, unusedCapital);
            }

            emit ExposureOpened(amount, notionalAmount, collateralNeeded);
            emit TRSContractCreated(contractId, bestQuote.counterparty, notionalAmount, collateralNeeded);

            return (true, notionalAmount);
        } catch {
            return (false, 0);
        }
    }

    function _selectBestQuote(
        ITRSProvider.TRSQuote[] memory quotes,
        uint256 amount
    ) internal view returns (ITRSProvider.TRSQuote memory bestQuote, bool found) {
        uint256 bestScore = 0;
        int256 bestIndex = -1;
        
        for (uint256 i = 0; i < quotes.length; i++) {
            // Check if quote is still valid
            if (block.timestamp > quotes[i].validUntil) continue;
            
            // Check if counterparty is in our allowed list
            uint256 cpIndex = counterpartyIndex[quotes[i].counterparty];
            if (cpIndex == 0) continue; // Not in our list
            
            CounterpartyAllocation memory allocation = counterpartyAllocations[cpIndex - 1];
            if (!allocation.isActive) continue;
            
            // Check capacity constraints - calculate notional amount from collateral requirement
            uint256 notionalAmount = (amount * BASIS_POINTS) / quotes[i].collateralRequirement;
            if (allocation.currentExposure + notionalAmount > allocation.maxExposure) continue;
            
            // Check concentration limits - use notional amount not collateral amount
            // Only check concentration limits if there's existing exposure
            if (totalExposureAmount > 0) {
                uint256 totalExposureAfter = totalExposureAmount + notionalAmount;
                uint256 newConcentration = ((allocation.currentExposure + notionalAmount) * BASIS_POINTS) / totalExposureAfter;
                if (newConcentration > counterpartyConcentrationLimit) continue;
            }
            
            // Calculate score (lower borrow rate + higher credit rating = better score)
            ITRSProvider.CounterpartyInfo memory cpInfo = trsProvider.getCounterpartyInfo(quotes[i].counterparty);
            uint256 score = (cpInfo.creditRating * 1000) - quotes[i].borrowRate; // Weight credit rating highly
            
            // Adjust score to favor diversification - penalize high concentration
            if (totalExposureAmount > 0) {
                uint256 currentConcentration = (allocation.currentExposure * BASIS_POINTS) / totalExposureAmount;
                if (currentConcentration > 2000) { // Above 20%
                    score = score > (currentConcentration - 2000) ? score - (currentConcentration - 2000) : 0;
                }
            }
            
            if (score > bestScore) {
                bestScore = score;
                bestIndex = int256(i);
            }
        }
        
        if (bestIndex >= 0) {
            bestQuote = quotes[uint256(bestIndex)];
            found = true;
        }
        
        return (bestQuote, found);
    }

    function _updateCounterpartyExposure(address counterparty, uint256 amount, bool isIncrease) internal {
        uint256 index = counterpartyIndex[counterparty];
        if (index == 0) return; // Not in our list
        
        index--; // Convert to actual index
        
        if (isIncrease) {
            counterpartyAllocations[index].currentExposure += amount;
        } else {
            counterpartyAllocations[index].currentExposure = 
                counterpartyAllocations[index].currentExposure > amount ? 
                counterpartyAllocations[index].currentExposure - amount : 0;
        }
    }

    function _removeActiveContract(bytes32 contractId) internal {
        isActiveContract[contractId] = false;
        
        // Remove from active contracts array
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            if (activeTRSContracts[i] == contractId) {
                activeTRSContracts[i] = activeTRSContracts[activeTRSContracts.length - 1];
                activeTRSContracts.pop();
                break;
            }
        }
    }

    function _sortContractsBySize() internal view returns (bytes32[] memory) {
        bytes32[] memory sorted = new bytes32[](activeTRSContracts.length);
        uint256[] memory sizes = new uint256[](activeTRSContracts.length);
        
        // Copy and get sizes
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            sorted[i] = activeTRSContracts[i];
            sizes[i] = contractInfo[activeTRSContracts[i]].notionalAmount;
        }
        
        // Simple bubble sort (acceptable for small arrays)
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (sizes[i] > sizes[j]) {
                    // Swap
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                    (sizes[i], sizes[j]) = (sizes[j], sizes[i]);
                }
            }
        }
        
        return sorted;
    }

    function _calculateCurrentLeverage() internal view returns (uint256) {
        if (totalCollateralDeployed == 0 || totalExposureAmount == 0) return 100;
        return (totalExposureAmount * 100) / totalCollateralDeployed;
    }

    function _calculateCollateralRatio(uint256 leverage) internal pure returns (uint256) {
        if (leverage <= 100) return BASIS_POINTS;
        return (100 * BASIS_POINTS) / leverage;
    }

    function _calculateCurrentCost() internal view returns (uint256) {
        (uint256 avgBorrowRate, uint256 spread) = _calculateAverageBorrowRate();
        return avgBorrowRate + spread + 20; // Add 0.20% management fee
    }

    function _calculateAverageBorrowRate() internal view returns (uint256 avgRate, uint256 spread) {
        if (activeTRSContracts.length == 0) return (300, 50); // Default 3% + 0.5% spread
        
        uint256 totalWeightedRate = 0;
        uint256 totalNotional = 0;
        uint256 minRate = type(uint256).max;
        uint256 maxRate = 0;
        
        for (uint256 i = 0; i < activeTRSContracts.length; i++) {
            bytes32 contractId = activeTRSContracts[i];
            TRSContractInfo memory info = contractInfo[contractId];
            
            // Get current borrow rate from TRS provider
            try trsProvider.getTRSContract(contractId) returns (ITRSProvider.TRSContract memory trsContract) {
                totalWeightedRate += trsContract.borrowRate * info.notionalAmount;
                totalNotional += info.notionalAmount;
                
                if (trsContract.borrowRate < minRate) minRate = trsContract.borrowRate;
                if (trsContract.borrowRate > maxRate) maxRate = trsContract.borrowRate;
            } catch {
                // Use stored info as fallback
                totalWeightedRate += 300 * info.notionalAmount; // 3% default
                totalNotional += info.notionalAmount;
            }
        }
        
        avgRate = totalNotional > 0 ? totalWeightedRate / totalNotional : 300;
        spread = maxRate > minRate ? maxRate - minRate : 50; // 0.5% default spread
        
        return (avgRate, spread);
    }

    function _calculateRiskScore() internal view returns (uint256) {
        uint256 baseRisk = 40; // Base TRS risk
        
        // Increase risk based on leverage
        uint256 leverage = _calculateCurrentLeverage();
        uint256 leverageRisk = (leverage - 100) / 10; // +1 risk per 0.1x leverage above 1x
        
        // Increase risk based on counterparty concentration
        uint256 concentrationRisk = 0;
        for (uint256 i = 0; i < counterpartyAllocations.length; i++) {
            if (totalExposureAmount > 0) {
                uint256 concentration = (counterpartyAllocations[i].currentExposure * BASIS_POINTS) / totalExposureAmount;
                if (concentration > 3000) { // Above 30%
                    concentrationRisk += (concentration - 3000) / 100; // +1 risk per 1% concentration above 30%
                }
            }
        }
        
        // Increase risk based on number of contracts (complexity)
        uint256 complexityRisk = activeTRSContracts.length > 5 ? (activeTRSContracts.length - 5) * 2 : 0;
        
        uint256 totalRisk = baseRisk + leverageRisk + concentrationRisk + complexityRisk;
        return Math.min(totalRisk, 100); // Cap at 100
    }

    function _estimateGasCost() internal pure returns (uint256) {
        return 5; // 0.05% estimated gas cost for TRS operations
    }

    function _getUnderlyingAsset() internal view returns (address) {
        // For TRS, we return the base asset address as a proxy
        return address(baseAsset);
    }
}