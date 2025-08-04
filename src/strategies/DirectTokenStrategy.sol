// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IExposureStrategy.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IYieldStrategy.sol";
import "../interfaces/IDEXRouter.sol";

/**
 * @title DirectTokenStrategy
 * @dev Strategy for direct RWA token purchases with yield optimization
 * @notice Purchases RWA tokens directly via DEX and optimizes unused capital through yield strategies
 */
contract DirectTokenStrategy is IExposureStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SLIPPAGE_PRECISION = 10000;
    
    // ============ STATE VARIABLES ============
    
    IERC20 public immutable baseAsset;
    IERC20 public immutable rwaToken;
    IPriceOracle public immutable priceOracle;
    
    string public strategyName;
    address public dexRouter;
    
    // Strategy allocation parameters
    uint256 public tokenAllocation = 8000;  // 80% to RWA tokens
    uint256 public yieldAllocation = 2000;  // 20% to yield strategies
    
    // Yield strategy configuration
    IYieldStrategy[] public yieldStrategies;
    uint256[] public yieldAllocations;
    uint256 public totalYieldShares;
    
    // Risk management
    RiskParameters public riskParams;
    
    // Position tracking
    uint256 public currentTokenBalance;
    uint256 public totalInvestedAmount;
    uint256 public lastRebalanceTime;
    
    // Performance tracking
    uint256 public totalTokensPurchased;
    uint256 public totalTokensSold;
    uint256 public totalSlippagePaid;
    uint256 public totalYieldHarvested;
    
    // ============ EVENTS ============
    
    event TokensPurchased(uint256 baseAssetSpent, uint256 tokensReceived, uint256 slippage);
    event TokensSold(uint256 tokensSold, uint256 baseAssetReceived, uint256 slippage);
    event YieldStrategyAdded(address strategy, uint256 allocation);
    event YieldStrategyRemoved(address strategy);
    event AllocationUpdated(uint256 newTokenAllocation, uint256 newYieldAllocation);
    event DEXRouterUpdated(address oldRouter, address newRouter);
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address _baseAsset,
        address _rwaToken,
        address _priceOracle,
        address _dexRouter,
        string memory _strategyName
    ) Ownable(msg.sender) {
        require(_baseAsset != address(0), "Invalid base asset");
        require(_rwaToken != address(0), "Invalid RWA token");
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_dexRouter != address(0), "Invalid DEX router");
        
        baseAsset = IERC20(_baseAsset);
        rwaToken = IERC20(_rwaToken);
        priceOracle = IPriceOracle(_priceOracle);
        dexRouter = _dexRouter;
        strategyName = _strategyName;
        
        // Initialize risk parameters
        riskParams = RiskParameters({
            maxLeverage: 100,           // 1x (no leverage for direct tokens)
            maxPositionSize: 10000000e6, // $10M max position
            liquidationBuffer: 0,       // Not applicable
            rebalanceThreshold: 500,    // 5% threshold
            slippageLimit: 200,         // 2% max slippage
            emergencyExitEnabled: true
        });
        
        lastRebalanceTime = block.timestamp;
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getExposureInfo() external view override returns (ExposureInfo memory) {
        uint256 currentValue = getCurrentExposureValue();
        uint256 costBps = _calculateCurrentCost();
        
        return ExposureInfo({
            strategyType: StrategyType.DIRECT_TOKEN,
            name: strategyName,
            underlyingAsset: address(rwaToken),
            leverage: 100, // 1x leverage (direct ownership)
            collateralRatio: BASIS_POINTS, // 100% collateral (full ownership)
            currentExposure: currentValue,
            maxCapacity: riskParams.maxPositionSize,
            currentCost: costBps,
            riskScore: _calculateRiskScore(),
            isActive: currentTokenBalance > 0,
            liquidationPrice: 0 // No liquidation for direct ownership
        });
    }
    
    function getCostBreakdown() external view override returns (CostBreakdown memory) {
        uint256 managementFee = 15; // 0.15% annual management fee
        uint256 slippageCost = _estimateSlippage(100000e6); // Estimate for $100k trade
        
        return CostBreakdown({
            fundingRate: 0,
            borrowRate: 0,
            managementFee: managementFee,
            slippageCost: slippageCost,
            gasCost: _estimateGasCost(),
            totalCostBps: managementFee + slippageCost,
            lastUpdated: block.timestamp
        });
    }
    
    function getRiskParameters() external view override returns (RiskParameters memory) {
        return riskParams;
    }
    
    function estimateExposureCost(uint256 amount, uint256 timeHorizon) external pure override returns (uint256) {
        if (amount == 0) return 0;
        
        uint256 managementFee = 15; // 0.15% annual
        uint256 slippageCost = _estimateSlippage(amount);
        uint256 gasCost = _estimateGasCost();
        
        // Annualize management fee based on time horizon
        uint256 annualizedManagementCost = (amount * managementFee * timeHorizon) / (BASIS_POINTS * 365 days);
        
        return annualizedManagementCost + slippageCost + gasCost;
    }
    
    function getCurrentExposureValue() public view override returns (uint256) {
        if (currentTokenBalance == 0) return 0;
        
        uint256 tokenPrice = priceOracle.getPrice(address(rwaToken));
        uint256 tokenValue = (currentTokenBalance * tokenPrice) / 1e18;
        
        // Add value from yield strategies
        uint256 yieldValue = _getYieldStrategyValue();
        
        return tokenValue + yieldValue;
    }
    
    function getCollateralRequired(uint256 exposureAmount) external pure override returns (uint256) {
        // Direct token ownership requires 100% collateral
        return exposureAmount;
    }
    
    function getLiquidationPrice() external pure override returns (uint256) {
        // No liquidation for direct token ownership
        return 0;
    }
    
    function canHandleExposure(uint256 amount) external view override returns (bool, string memory) {
        if (amount == 0) {
            return (false, "Amount cannot be zero");
        }
        
        if (amount > riskParams.maxPositionSize) {
            return (false, "Amount exceeds maximum position size");
        }
        
        uint256 currentValue = getCurrentExposureValue();
        if (currentValue + amount > riskParams.maxPositionSize) {
            return (false, "Would exceed maximum position size");
        }
        
        // Check DEX liquidity
        if (!_checkDEXLiquidity(amount)) {
            return (false, "Insufficient DEX liquidity");
        }
        
        return (true, "");
    }
    
    // ============ STATE-CHANGING FUNCTIONS ============
    
    function openExposure(uint256 amount) external override nonReentrant returns (bool, uint256) {
        require(amount > 0, "Amount cannot be zero");
        require(amount <= riskParams.maxPositionSize, "Amount exceeds maximum position size");
        
        // Transfer base asset from caller
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate allocation
        uint256 tokenAmount = (amount * tokenAllocation) / BASIS_POINTS;
        uint256 yieldAmount = amount - tokenAmount;
        
        // Purchase RWA tokens
        uint256 tokensReceived = _purchaseTokens(tokenAmount);
        require(tokensReceived > 0, "Token purchase failed");
        
        // Allocate to yield strategies
        if (yieldAmount > 0) {
            _allocateToYieldStrategies(yieldAmount);
        }
        
        // Update tracking
        currentTokenBalance += tokensReceived;
        totalInvestedAmount += amount;
        totalTokensPurchased += tokensReceived;
        
        uint256 actualExposure = getCurrentExposureValue();
        
        emit ExposureOpened(amount, actualExposure, amount);
        
        return (true, actualExposure);
    }
    
    function closeExposure(uint256 amount) external override nonReentrant returns (bool, uint256) {
        require(amount > 0, "Amount cannot be zero");
        
        uint256 currentValue = getCurrentExposureValue();
        require(amount <= currentValue, "Amount exceeds current exposure");
        
        uint256 closeRatio = (amount * BASIS_POINTS) / currentValue;
        
        // Calculate tokens to sell
        uint256 tokensToSell = (currentTokenBalance * closeRatio) / BASIS_POINTS;
        
        // Sell tokens
        uint256 baseReceived = 0;
        if (tokensToSell > 0) {
            baseReceived = _sellTokens(tokensToSell);
        }
        
        // Withdraw from yield strategies proportionally
        uint256 yieldWithdrawn = _withdrawFromYieldStrategies(closeRatio);
        
        // Update tracking
        currentTokenBalance -= tokensToSell;
        totalTokensSold += tokensToSell;
        totalInvestedAmount = (totalInvestedAmount * (BASIS_POINTS - closeRatio)) / BASIS_POINTS;
        
        uint256 totalRecovered = baseReceived + yieldWithdrawn;
        
        // Transfer recovered amount to caller
        if (totalRecovered > 0) {
            baseAsset.safeTransfer(msg.sender, totalRecovered);
        }
        
        emit ExposureClosed(amount, totalRecovered, totalRecovered);
        
        return (true, totalRecovered);
    }
    
    function adjustExposure(int256 delta) external override nonReentrant returns (bool, uint256) {
        if (delta == 0) {
            return (true, getCurrentExposureValue());
        }
        
        if (delta > 0) {
            // Increase exposure
            uint256 amount = uint256(delta);
            require(amount > 0, "Amount cannot be zero");
            require(amount <= riskParams.maxPositionSize, "Amount exceeds maximum position size");
            
            // Transfer base asset from caller
            baseAsset.safeTransferFrom(msg.sender, address(this), amount);
            
            // Calculate allocation
            uint256 tokenAmount = (amount * tokenAllocation) / BASIS_POINTS;
            uint256 yieldAmount = amount - tokenAmount;
            
            // Purchase RWA tokens
            uint256 tokensReceived = _purchaseTokens(tokenAmount);
            require(tokensReceived > 0, "Token purchase failed");
            
            // Allocate to yield strategies
            if (yieldAmount > 0) {
                _allocateToYieldStrategies(yieldAmount);
            }
            
            // Update tracking
            currentTokenBalance += tokensReceived;
            totalInvestedAmount += amount;
            totalTokensPurchased += tokensReceived;
            
            uint256 newExposure = getCurrentExposureValue();
            emit ExposureOpened(amount, newExposure, amount);
            
            return (true, newExposure);
        } else {
            // Decrease exposure
            uint256 amount = uint256(-delta);
            require(amount > 0, "Amount cannot be zero");
            
            uint256 currentValue = getCurrentExposureValue();
            require(amount <= currentValue, "Amount exceeds current exposure");
            
            uint256 closeRatio = (amount * BASIS_POINTS) / currentValue;
            
            // Calculate tokens to sell
            uint256 tokensToSell = (currentTokenBalance * closeRatio) / BASIS_POINTS;
            
            // Sell tokens
            uint256 baseReceived = 0;
            if (tokensToSell > 0) {
                baseReceived = _sellTokens(tokensToSell);
            }
            
            // Withdraw from yield strategies proportionally
            uint256 yieldWithdrawn = _withdrawFromYieldStrategies(closeRatio);
            
            // Update tracking
            currentTokenBalance -= tokensToSell;
            totalTokensSold += tokensToSell;
            totalInvestedAmount = (totalInvestedAmount * (BASIS_POINTS - closeRatio)) / BASIS_POINTS;
            
            uint256 totalRecovered = baseReceived + yieldWithdrawn;
            
            // Transfer recovered amount to caller
            if (totalRecovered > 0) {
                baseAsset.safeTransfer(msg.sender, totalRecovered);
            }
            
            uint256 newExposure = getCurrentExposureValue();
            emit ExposureClosed(amount, totalRecovered, totalRecovered);
            
            return (true, newExposure);
        }
    }
    
    function harvestYield() external override nonReentrant returns (uint256) {
        uint256 totalHarvested = 0;
        
        // Harvest from yield strategies
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            try yieldStrategies[i].harvestYield() returns (uint256 harvested) {
                totalHarvested += harvested;
            } catch {
                // Continue with other strategies if one fails
            }
        }
        
        totalYieldHarvested += totalHarvested;
        
        emit YieldHarvested(totalHarvested);
        
        return totalHarvested;
    }
    
    function emergencyExit() external override nonReentrant returns (uint256) {
        require(riskParams.emergencyExitEnabled, "Emergency exit disabled");
        
        uint256 totalRecovered = 0;
        
        // Sell all tokens
        if (currentTokenBalance > 0) {
            totalRecovered += _sellTokens(currentTokenBalance);
            currentTokenBalance = 0;
        }
        
        // Emergency withdraw from yield strategies - withdraw all our shares
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            uint256 strategyShares = (totalYieldShares * yieldAllocations[i]) / BASIS_POINTS;
            if (strategyShares > 0) {
                try yieldStrategies[i].withdraw(strategyShares) returns (uint256 recovered) {
                    totalRecovered += recovered;
                } catch {
                    // Continue with other strategies if one fails
                }
            }
        }
        
        // Reset state
        totalInvestedAmount = 0;
        totalYieldShares = 0;
        
        // Transfer recovered amount to owner
        if (totalRecovered > 0) {
            baseAsset.safeTransfer(owner(), totalRecovered);
        }
        
        emit EmergencyExit(totalRecovered, "Emergency exit executed");
        
        return totalRecovered;
    }
    
    function updateRiskParameters(RiskParameters calldata newParams) external override onlyOwner {
        require(newParams.maxLeverage <= 100, "Leverage must be 1x for direct tokens");
        require(newParams.slippageLimit <= 1000, "Slippage limit too high");
        
        riskParams = newParams;
        
        emit RiskParametersUpdated(newParams);
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function addYieldStrategy(address strategy, uint256 allocation) external onlyOwner {
        require(strategy != address(0), "Invalid strategy address");
        require(allocation <= BASIS_POINTS, "Allocation exceeds 100%");
        
        yieldStrategies.push(IYieldStrategy(strategy));
        yieldAllocations.push(allocation);
        
        emit YieldStrategyAdded(strategy, allocation);
    }
    
    function removeYieldStrategy(uint256 index) external onlyOwner {
        require(index < yieldStrategies.length, "Invalid index");
        
        address strategy = address(yieldStrategies[index]);
        
        // Note: In production, should withdraw from strategy before removal
        // This would require tracking shares per strategy
        
        // Remove from arrays
        yieldStrategies[index] = yieldStrategies[yieldStrategies.length - 1];
        yieldAllocations[index] = yieldAllocations[yieldAllocations.length - 1];
        yieldStrategies.pop();
        yieldAllocations.pop();
        
        emit YieldStrategyRemoved(strategy);
    }
    
    function updateAllocation(uint256 newTokenAllocation, uint256 newYieldAllocation) external onlyOwner {
        require(newTokenAllocation + newYieldAllocation == BASIS_POINTS, "Allocations must sum to 100%");
        require(newTokenAllocation >= 5000, "Token allocation too low"); // Minimum 50%
        
        tokenAllocation = newTokenAllocation;
        yieldAllocation = newYieldAllocation;
        
        emit AllocationUpdated(newTokenAllocation, newYieldAllocation);
    }
    
    function updateDEXRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Invalid router address");
        
        address oldRouter = dexRouter;
        dexRouter = newRouter;
        
        emit DEXRouterUpdated(oldRouter, newRouter);
    }
    
    function rebalanceStrategies() external onlyOwner {
        require(
            block.timestamp >= lastRebalanceTime + 1 hours,
            "Rebalance too frequent"
        );
        
        // Implementation would rebalance between token and yield strategies
        // based on performance and market conditions
        
        lastRebalanceTime = block.timestamp;
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _purchaseTokens(uint256 baseAmount) internal returns (uint256) {
        if (baseAmount == 0) return 0;
        
        // Get expected tokens and calculate minimum with slippage protection
        uint256 expectedTokens = _getExpectedTokenAmount(baseAmount);
        uint256 minTokens = (expectedTokens * (SLIPPAGE_PRECISION - riskParams.slippageLimit)) / SLIPPAGE_PRECISION;
        
        // Approve DEX router
        baseAsset.forceApprove(dexRouter, baseAmount);
        
        // Execute swap via DEX router
        uint256 balanceBefore = rwaToken.balanceOf(address(this));
        
        // Call DEX router interface
        IDEXRouter(dexRouter).swapExactTokensForTokens(
            baseAmount,
            minTokens,
            address(baseAsset),
            address(rwaToken)
        );
        
        uint256 tokensReceived = rwaToken.balanceOf(address(this)) - balanceBefore;
        
        // Calculate and track slippage
        uint256 actualSlippage = expectedTokens > tokensReceived ? 
            ((expectedTokens - tokensReceived) * BASIS_POINTS) / expectedTokens : 0;
        totalSlippagePaid += actualSlippage;
        
        emit TokensPurchased(baseAmount, tokensReceived, actualSlippage);
        
        return tokensReceived;
    }
    
    function _sellTokens(uint256 tokenAmount) internal returns (uint256) {
        if (tokenAmount == 0) return 0;
        
        // Get expected base asset and calculate minimum with slippage protection
        uint256 expectedBase = _getExpectedBaseAmount(tokenAmount);
        uint256 minBase = (expectedBase * (SLIPPAGE_PRECISION - riskParams.slippageLimit)) / SLIPPAGE_PRECISION;
        
        // Approve DEX router
        rwaToken.forceApprove(dexRouter, tokenAmount);
        
        // Execute swap
        uint256 balanceBefore = baseAsset.balanceOf(address(this));
        
        // Call DEX router interface
        IDEXRouter(dexRouter).swapExactTokensForTokens(
            tokenAmount,
            minBase,
            address(rwaToken),
            address(baseAsset)
        );
        
        uint256 baseReceived = baseAsset.balanceOf(address(this)) - balanceBefore;
        
        // Calculate and track slippage
        uint256 actualSlippage = expectedBase > baseReceived ? 
            ((expectedBase - baseReceived) * BASIS_POINTS) / expectedBase : 0;
        totalSlippagePaid += actualSlippage;
        
        emit TokensSold(tokenAmount, baseReceived, actualSlippage);
        
        return baseReceived;
    }
    
    function _allocateToYieldStrategies(uint256 amount) internal {
        if (amount == 0 || yieldStrategies.length == 0) return;
        
        uint256 remaining = amount;
        
        for (uint256 i = 0; i < yieldStrategies.length && remaining > 0; i++) {
            uint256 allocation = (amount * yieldAllocations[i]) / BASIS_POINTS;
            if (allocation > remaining) allocation = remaining;
            
            if (allocation > 0) {
                baseAsset.forceApprove(address(yieldStrategies[i]), allocation);
                try yieldStrategies[i].deposit(allocation) returns (uint256 shares) {
                    remaining -= allocation;
                    totalYieldShares += shares;
                } catch {
                    // Continue with other strategies if one fails
                }
            }
        }
    }
    
    function _withdrawFromYieldStrategies(uint256 ratio) internal returns (uint256) {
        uint256 totalWithdrawn = 0;
        
        // For simplicity, calculate shares to withdraw based on total shares and ratio
        uint256 sharesToWithdraw = (totalYieldShares * ratio) / BASIS_POINTS;
        uint256 remainingShares = sharesToWithdraw;
        
        for (uint256 i = 0; i < yieldStrategies.length && remainingShares > 0; i++) {
            // Calculate this strategy's share of withdrawal
            uint256 strategyShares = (sharesToWithdraw * yieldAllocations[i]) / BASIS_POINTS;
            if (strategyShares > remainingShares) strategyShares = remainingShares;
            
            if (strategyShares > 0) {
                try yieldStrategies[i].withdraw(strategyShares) returns (uint256 withdrawn) {
                    totalWithdrawn += withdrawn;
                    totalYieldShares -= strategyShares;
                    remainingShares -= strategyShares;
                } catch {
                    // Continue with other strategies if one fails
                }
            }
        }
        
        return totalWithdrawn;
    }
    
    function _getYieldStrategyValue() internal view returns (uint256) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            try yieldStrategies[i].getTotalValue() returns (uint256 strategyTotal) {
                // Calculate our portion based on our share allocation
                uint256 ourPortion = (strategyTotal * yieldAllocations[i]) / BASIS_POINTS;
                totalValue += ourPortion;
            } catch {
                // Continue with other strategies if one fails
            }
        }
        
        return totalValue;
    }
    
    function _getExpectedTokenAmount(uint256 baseAmount) internal view returns (uint256) {
        // Query DEX for expected output
        return IDEXRouter(dexRouter).getAmountsOut(baseAmount, address(baseAsset), address(rwaToken));
    }
    
    function _getExpectedBaseAmount(uint256 tokenAmount) internal view returns (uint256) {
        // Query DEX for expected output
        return IDEXRouter(dexRouter).getAmountsOut(tokenAmount, address(rwaToken), address(baseAsset));
    }
    
    function _estimateSlippage(uint256 amount) internal pure returns (uint256) {
        // Simplified slippage estimation based on trade size
        // Real implementation would query DEX liquidity
        if (amount <= 10000e6) return 10; // 0.1%
        if (amount <= 100000e6) return 25; // 0.25%
        if (amount <= 1000000e6) return 50; // 0.5%
        return 100; // 1% for large trades
    }
    
    function _estimateGasCost() internal pure returns (uint256) {
        // Simplified gas cost estimation
        return 50e6; // $50 equivalent
    }
    
    function _calculateCurrentCost() internal view returns (uint256) {
        uint256 managementFee = 15; // 0.15%
        uint256 avgSlippage = totalTokensPurchased > 0 ? 
            (totalSlippagePaid * BASIS_POINTS) / totalTokensPurchased : 25; // 0.25% default
        
        return managementFee + avgSlippage;
    }
    
    function _calculateRiskScore() internal view returns (uint256) {
        // Lower risk for direct token ownership
        // Score based on concentration and market volatility
        uint256 baseScore = 30; // Base risk score for direct tokens
        
        // Increase based on position concentration
        uint256 currentValue = getCurrentExposureValue();
        if (currentValue > riskParams.maxPositionSize / 2) {
            baseScore += 20; // Higher concentration increases risk
        }
        
        return baseScore;
    }
    
    function _checkDEXLiquidity(uint256 amount) internal pure returns (bool) {
        // Simplified liquidity check - real implementation would query DEX
        return amount <= 1000000e6; // Assume $1M liquidity limit
    }
    
    
    // ============ VIEW FUNCTIONS FOR EXTERNAL MONITORING ============
    
    function getYieldStrategies() external view returns (address[] memory, uint256[] memory) {
        address[] memory strategies = new address[](yieldStrategies.length);
        for (uint256 i = 0; i < yieldStrategies.length; i++) {
            strategies[i] = address(yieldStrategies[i]);
        }
        return (strategies, yieldAllocations);
    }
    
    function getPerformanceMetrics() external view returns (
        uint256 totalPurchased,
        uint256 totalSold,
        uint256 currentBalance,
        uint256 totalSlippage,
        uint256 yieldHarvested
    ) {
        return (
            totalTokensPurchased,
            totalTokensSold,
            currentTokenBalance,
            totalSlippagePaid,
            totalYieldHarvested
        );
    }
}