// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EnhancedErrors
 * @dev Enhanced error messages with detailed context
 * @notice Quick-win improvement: Better error messages for debugging and user experience
 */
library EnhancedErrors {
    
    // ============ STRATEGY ERRORS ============
    
    error StrategyNotFound(address strategy, string context);
    error StrategyNotActive(address strategy, string reason);
    error StrategyCapacityExceeded(address strategy, uint256 requested, uint256 available);
    error StrategyLeverageTooHigh(address strategy, uint256 requested, uint256 maximum);
    error StrategyInsufficientCollateral(address strategy, uint256 required, uint256 available);
    
    error PositionNotFound(bytes32 positionId, address strategy);
    error PositionAlreadyExists(bytes32 positionId, address strategy);
    error PositionNotLiquidatable(bytes32 positionId, uint256 healthFactor, uint256 threshold);
    error PositionSizeExceeded(bytes32 positionId, uint256 requested, uint256 maximum);
    
    // ============ ORACLE ERRORS ============
    
    error OracleStaleData(address oracle, address asset, uint256 age, uint256 maxAge);
    error OraclePriceDeviation(address oracle, address asset, uint256 deviation, uint256 threshold);
    error OracleNotConfigured(address asset, string oracleType);
    error OracleCircuitBreakerActive(address asset, string reason);
    error OracleFallbackFailed(address asset, uint256 attemptedOracles);
    
    error InvalidPriceData(address oracle, address asset, int256 price);
    error PriceTooVolatile(address asset, uint256 currentPrice, uint256 previousPrice, uint256 maxDeviation);
    
    // ============ FLASH LOAN PROTECTION ERRORS ============
    
    error FlashLoanSuspected(address user, address strategy, uint256 amount, string pattern);
    error SameBlockOperationBlocked(address user, uint256 currentBlock, uint256 amount, uint256 limit);
    error HoldingPeriodNotMet(address user, uint256 remainingTime, uint256 requiredPeriod);
    error SuspiciousPatternDetected(address user, string pattern, uint256 count, uint256 threshold);
    error MEVAttemptBlocked(address user, string mevType, uint256 severity);
    
    error UserNotWhitelisted(address user, address strategy);
    error DailyVolumeLimitExceeded(address user, uint256 currentVolume, uint256 limit);
    error TooManyOperationsInBlock(address user, uint256 operationsCount, uint256 maxAllowed);
    
    // ============ FEE COLLECTION ERRORS ============
    
    error FeeCollectionFailed(address strategy, uint256 attemptedAmount, string reason);
    error FeeDistributionFailed(address recipient, uint256 amount, string reason);
    error FeesNotReady(address strategy, uint256 timeSinceLastCollection, uint256 requiredInterval);
    error InsufficientFeeBalance(address strategy, uint256 requested, uint256 available);
    
    error PerformanceFeeCalculationError(address strategy, uint256 currentValue, uint256 highWaterMark);
    error ManagementFeeCalculationError(address strategy, uint256 timeElapsed, uint256 rate);
    error FeeRateTooHigh(address strategy, uint256 rate, uint256 maximum, string feeType);
    
    // ============ LIQUIDATION ERRORS ============
    
    error LiquidationFailed(bytes32 positionId, address strategy, uint256 amount, string reason);
    error LiquidationAmountTooHigh(bytes32 positionId, uint256 requested, uint256 maximum);
    error InsufficientLiquidationReward(bytes32 positionId, uint256 reward, uint256 minRequired);
    error LiquidationTooEarly(bytes32 positionId, uint256 healthFactor, uint256 threshold);
    
    error KeeperNotAuthorized(address keeper, address strategy);
    error KeeperGasReimbursementFailed(address keeper, uint256 gasUsed, uint256 availablePool);
    error LiquidationHistoryCorrupted(bytes32 positionId, string issue);
    
    // ============ ACCESS CONTROL ERRORS ============
    
    error NotAuthorized(address caller, address required, string action);
    error NotOwner(address caller, address owner);
    error NotOperator(address caller, string operatorType);
    error NotEmergencyOperator(address caller, address emergencyOperator);
    
    error ContractPaused(address contractAddress, string reason);
    error EmergencyModeActive(address contractAddress, string trigger);
    error FunctionDeprecated(string functionName, string alternative);
    
    // ============ VALIDATION ERRORS ============
    
    error InvalidAmount(uint256 amount, uint256 minimum, uint256 maximum, string context);
    error InvalidPercentage(uint256 percentage, string context);
    error InvalidTimeframe(uint256 timeframe, uint256 minimum, uint256 maximum, string context);
    error InvalidAddress(address provided, string expectedType);
    
    error ArrayLengthMismatch(uint256 array1Length, uint256 array2Length, string context);
    error ArrayTooLarge(uint256 arrayLength, uint256 maximum, string context);
    error ArrayEmpty(string arrayName, string context);
    
    error ConfigurationInvalid(string parameter, string reason);
    error ParameterOutOfRange(string parameter, uint256 value, uint256 min, uint256 max);
    
    // ============ INTEGRATION ERRORS ============
    
    error ExternalCallFailed(address target, bytes4 selector, string reason);
    error TokenTransferFailed(address token, address from, address to, uint256 amount);
    error InsufficientAllowance(address token, address owner, address spender, uint256 required, uint256 current);
    error InsufficientBalance(address token, address account, uint256 required, uint256 current);
    
    error DEXSwapFailed(address dex, address tokenIn, address tokenOut, uint256 amountIn, string reason);
    error SlippageExceeded(uint256 expectedAmount, uint256 actualAmount, uint256 maxSlippage);
    error LiquidityInsufficient(address token, uint256 required, uint256 available);
    
    // ============ STATE ERRORS ============
    
    error InvalidState(string currentState, string requiredState, string operation);
    error StateTransitionBlocked(string fromState, string toState, string reason);
    error OperationNotAllowed(string operation, string currentState);
    error ReentrancyDetected(string function_name);
    
    error CooldownPeriodActive(uint256 remainingTime, string operation);
    error DeadlineExceeded(uint256 currentTime, uint256 deadline, string operation);
    error NonceAlreadyUsed(uint256 nonce, address user);
    
    // ============ OPTIMIZATION ERRORS ============
    
    error OptimizationFailed(address strategy, string metric, uint256 current, uint256 target);
    error InsufficientGasForOperation(uint256 gasLeft, uint256 gasRequired, string operation);
    error BatchOperationPartiallyFailed(uint256 successCount, uint256 totalCount, string operation);
    
    error StructPackingFailed(string structName, uint256 value, string fieldName);
    error ConversionOverflow(uint256 value, string fromType, string toType);
    error DataCompressionFailed(bytes data, string reason);

    // ============ ERROR CONTEXT HELPERS ============
    
    /**
     * @dev Creates detailed error context for strategy operations
     */
    function createStrategyContext(
        address strategy,
        address user,
        uint256 amount,
        string memory operation
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Strategy: ", _addressToString(strategy),
                ", User: ", _addressToString(user),
                ", Amount: ", _uint256ToString(amount),
                ", Operation: ", operation
            )
        );
    }
    
    /**
     * @dev Creates detailed error context for oracle operations
     */
    function createOracleContext(
        address oracle,
        address asset,
        uint256 price,
        uint256 timestamp
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Oracle: ", _addressToString(oracle),
                ", Asset: ", _addressToString(asset),
                ", Price: ", _uint256ToString(price),
                ", Timestamp: ", _uint256ToString(timestamp)
            )
        );
    }
    
    /**
     * @dev Creates detailed error context for liquidation operations
     */
    function createLiquidationContext(
        bytes32 positionId,
        address strategy,
        address liquidator,
        uint256 amount
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "PositionId: ", _bytes32ToString(positionId),
                ", Strategy: ", _addressToString(strategy),
                ", Liquidator: ", _addressToString(liquidator),
                ", Amount: ", _uint256ToString(amount)
            )
        );
    }

    // ============ UTILITY FUNCTIONS ============
    
    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
    
    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 32; i++) {
            str[2+i*2] = alphabet[uint8(value[i] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }
}