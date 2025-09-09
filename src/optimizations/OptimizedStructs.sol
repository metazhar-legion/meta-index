// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title OptimizedStructs
 * @dev Gas-optimized structs with packed storage
 * @notice Quick-win optimizations through better struct packing
 */
library OptimizedStructs {

    // ============ OPTIMIZED EXPOSURE STRATEGY STRUCTS ============
    
    /**
     * @dev Gas-optimized ExposureInfo struct
     * @notice Original: 9 storage slots, Optimized: 6 storage slots
     */
    struct ExposureInfoOptimized {
        // Slot 1: Combined strategy type, leverage, and flags
        uint8 strategyType;          // 1 byte
        uint16 leverage;             // 2 bytes (up to 655.35x leverage)
        uint16 collateralRatio;      // 2 bytes (basis points, up to 655.35%)
        uint8 riskScore;             // 1 byte (0-255)
        bool isActive;               // 1 byte
        // 7 bytes used, 25 bytes remaining in slot
        
        // Slot 2: Name (32 bytes max)
        bytes32 name;
        
        // Slot 3: Asset address (20 bytes) + current cost (2 bytes) + padding
        address underlyingAsset;     // 20 bytes
        uint16 currentCostBps;       // 2 bytes (up to 655.35%)
        // 22 bytes used, 10 bytes remaining in slot
        
        // Slot 4: Exposure and capacity amounts
        uint128 currentExposure;     // 16 bytes (up to ~3.4e38, sufficient for most use cases)
        uint128 maxCapacity;         // 16 bytes
        
        // Slot 5: Liquidation price
        uint256 liquidationPrice;    // 32 bytes
        
        // Slot 6: Last updated timestamp
        uint48 lastUpdated;          // 6 bytes (sufficient until year ~8.9 million)
        // 6 bytes used, 26 bytes remaining in slot
    }
    
    /**
     * @dev Gas-optimized CostBreakdown struct
     * @notice Original: 7 storage slots, Optimized: 3 storage slots
     */
    struct CostBreakdownOptimized {
        // Slot 1: All rate components (basis points, max 655.35% each)
        uint16 fundingRateBps;       // 2 bytes
        uint16 borrowRateBps;        // 2 bytes
        uint16 managementFeeBps;     // 2 bytes
        uint16 slippageCostBps;      // 2 bytes
        uint16 totalCostBps;         // 2 bytes
        // 10 bytes used, 22 bytes remaining in slot
        
        // Slot 2: Gas cost (4 bytes) + timestamp (6 bytes)
        uint32 gasCostWei;           // 4 bytes (up to ~4.3B wei, sufficient for gas costs)
        uint48 lastUpdated;          // 6 bytes
        // 10 bytes used, 22 bytes remaining in slot
        
        // Slot 3: Reserved for future use
        uint256 reserved;            // 32 bytes
    }
    
    /**
     * @dev Gas-optimized RiskParameters struct
     * @notice Original: 6 storage slots, Optimized: 3 storage slots
     */
    struct RiskParametersOptimized {
        // Slot 1: All percentage/ratio parameters (basis points)
        uint16 maxLeverageBps;       // 2 bytes (up to 655.35x)
        uint16 liquidationBufferBps; // 2 bytes
        uint16 rebalanceThresholdBps; // 2 bytes
        uint16 slippageLimitBps;     // 2 bytes
        bool emergencyExitEnabled;   // 1 byte
        // 9 bytes used, 23 bytes remaining in slot
        
        // Slot 2: Position size limit
        uint128 maxPositionSize;     // 16 bytes
        uint128 reserved1;           // 16 bytes for future use
        
        // Slot 3: Reserved for future parameters
        uint256 reserved2;           // 32 bytes
    }

    // ============ OPTIMIZED STRATEGY OPTIMIZER STRUCTS ============
    
    /**
     * @dev Gas-optimized OptimizationParams struct
     * @notice Packs multiple small values into fewer storage slots
     */
    struct OptimizationParamsOptimized {
        // Slot 1: All basis point parameters
        uint16 minCostSavingBps;     // 2 bytes
        uint16 maxSlippageBps;       // 2 bytes
        uint16 riskPenaltyBps;       // 2 bytes
        uint16 liquidityWeightBps;   // 2 bytes
        uint16 diversificationBonusBps; // 2 bytes
        bool enableEmergencyMode;    // 1 byte
        // 11 bytes used, 21 bytes remaining in slot
        
        // Slot 2: Time and gas parameters
        uint32 timeHorizonSeconds;   // 4 bytes (up to ~136 years)
        uint32 gasThresholdWei;      // 4 bytes (sufficient for gas costs)
        // 8 bytes used, 24 bytes remaining in slot
        
        // Slot 3: Reserved for future use
        uint256 reserved;            // 32 bytes
    }
    
    /**
     * @dev Gas-optimized StrategyScore struct
     * @notice Combines multiple scores into bit-packed format
     */
    struct StrategyScoreOptimized {
        // Slot 1: Strategy address
        address strategy;            // 20 bytes
        uint8 totalScorePercent;     // 1 byte (0-100%)
        bool isRecommended;          // 1 byte
        // 22 bytes used, 10 bytes remaining in slot
        
        // Slot 2: Packed scores (each score 0-255)
        uint8 costScore;             // 1 byte
        uint8 riskScore;             // 1 byte
        uint8 liquidityScore;        // 1 byte
        uint8 reliabilityScore;      // 1 byte
        uint8 capacityScore;         // 1 byte
        // 5 bytes used, 27 bytes remaining in slot
        
        // Slot 3: Reasoning hash (for gas efficiency, store hash instead of string)
        bytes32 reasoningHash;       // 32 bytes
    }

    // ============ OPTIMIZED FLASH LOAN PROTECTION STRUCTS ============
    
    /**
     * @dev Gas-optimized UserInteraction struct
     * @notice Combines timestamps and amounts efficiently
     */
    struct UserInteractionOptimized {
        // Slot 1: Block numbers and flags
        uint32 lastInteractionBlock; // 4 bytes (sufficient for block numbers)
        uint48 lastDepositTime;      // 6 bytes (timestamp)
        uint48 lastWithdrawTime;     // 6 bytes (timestamp)
        bool isWhitelisted;          // 1 byte
        // 15 bytes used, 17 bytes remaining in slot
        
        // Slot 2: Block amounts (using uint128 for large amounts)
        uint128 totalDepositedInBlock;  // 16 bytes
        uint128 totalWithdrawnInBlock;  // 16 bytes
        
        // Slot 3: Cumulative deposit
        uint256 cumulativeDeposit;   // 32 bytes
    }
    
    /**
     * @dev Gas-optimized ProtectionParams struct
     * @notice Combines multiple parameters with appropriate sizing
     */
    struct ProtectionParamsOptimized {
        // Slot 1: Time and limit parameters
        uint32 minHoldingPeriodSeconds;     // 4 bytes
        uint32 collectionIntervalSeconds;   // 4 bytes
        uint128 sameBlockLimitUSD;          // 16 bytes (sufficient for USD amounts)
        uint64 dailyVolumeLimitUSD;         // 8 bytes (up to ~18B USD)
        
        // Slot 2: Thresholds and flags
        uint64 suspiciousPatternThreshold;  // 8 bytes
        bool enableSameBlockProtection;     // 1 byte
        bool enableHoldingPeriod;           // 1 byte
        bool isActive;                      // 1 byte
        // 11 bytes used, 21 bytes remaining in slot
        
        // Slot 3: Reserved for future parameters
        uint256 reserved;                   // 32 bytes
    }

    // ============ UTILITY FUNCTIONS FOR CONVERSIONS ============
    
    /**
     * @dev Converts basis points to uint16 (max 655.35%)
     * @notice Reverts if value exceeds max uint16
     */
    function basisPointsToUint16(uint256 bps) internal pure returns (uint16) {
        require(bps <= type(uint16).max, "Value exceeds uint16 max");
        return uint16(bps);
    }
    
    /**
     * @dev Converts timestamp to uint48 (sufficient until year ~8.9 million)
     * @notice Reverts if timestamp exceeds max uint48
     */
    function timestampToUint48(uint256 timestamp) internal pure returns (uint48) {
        require(timestamp <= type(uint48).max, "Timestamp exceeds uint48 max");
        return uint48(timestamp);
    }
    
    /**
     * @dev Converts amount to uint128 (up to ~3.4e38)
     * @notice Reverts if amount exceeds max uint128
     */
    function amountToUint128(uint256 amount) internal pure returns (uint128) {
        require(amount <= type(uint128).max, "Amount exceeds uint128 max");
        return uint128(amount);
    }
    
    /**
     * @dev Converts block number to uint32 (sufficient for ~4.3B blocks)
     * @notice Reverts if block number exceeds max uint32
     */
    function blockNumberToUint32(uint256 blockNumber) internal pure returns (uint32) {
        require(blockNumber <= type(uint32).max, "Block number exceeds uint32 max");
        return uint32(blockNumber);
    }
    
    /**
     * @dev Expands uint16 basis points back to uint256
     */
    function uint16ToBasisPoints(uint16 value) internal pure returns (uint256) {
        return uint256(value);
    }
    
    /**
     * @dev Expands uint48 timestamp back to uint256
     */
    function uint48ToTimestamp(uint48 value) internal pure returns (uint256) {
        return uint256(value);
    }
    
    /**
     * @dev Expands uint128 amount back to uint256
     */
    function uint128ToAmount(uint128 value) internal pure returns (uint256) {
        return uint256(value);
    }
    
    /**
     * @dev Expands uint32 block number back to uint256
     */
    function uint32ToBlockNumber(uint32 value) internal pure returns (uint256) {
        return uint256(value);
    }

    // ============ STRUCT CONVERSION HELPERS ============
    
    /**
     * @dev Converts original ExposureInfo to optimized version
     * @notice Helper function for migration
     */
    function optimizeExposureInfo(
        uint8 strategyType,
        string memory name,
        address underlyingAsset,
        uint256 leverage,
        uint256 collateralRatio,
        uint256 currentExposure,
        uint256 maxCapacity,
        uint256 currentCost,
        uint256 riskScore,
        bool isActive,
        uint256 liquidationPrice
    ) internal pure returns (ExposureInfoOptimized memory) {
        return ExposureInfoOptimized({
            strategyType: strategyType,
            name: bytes32(bytes(name)),
            underlyingAsset: underlyingAsset,
            leverage: basisPointsToUint16(leverage),
            collateralRatio: basisPointsToUint16(collateralRatio),
            currentExposure: amountToUint128(currentExposure),
            maxCapacity: amountToUint128(maxCapacity),
            currentCostBps: basisPointsToUint16(currentCost),
            riskScore: uint8(riskScore),
            isActive: isActive,
            liquidationPrice: liquidationPrice,
            lastUpdated: timestampToUint48(block.timestamp)
        });
    }
    
    /**
     * @dev Calculates gas savings from struct optimization
     * @notice Helper function to estimate gas savings
     */
    function calculateGasSavings(
        uint256 originalSlots,
        uint256 optimizedSlots,
        uint256 storageOperations
    ) internal pure returns (uint256 gasSaved) {
        // Each storage slot operation costs ~20,000 gas (SSTORE)
        uint256 slotsReduced = originalSlots - optimizedSlots;
        gasSaved = slotsReduced * storageOperations * 20000;
        return gasSaved;
    }
}