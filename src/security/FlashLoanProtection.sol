// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title FlashLoanProtection
 * @dev Protection against flash loan attacks and MEV exploitation
 * @notice Implements same-block restrictions and minimum holding periods
 */
contract FlashLoanProtection is Ownable, Pausable {
    using Math for uint256;

    // ============ CONSTANTS ============
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_HOLDING_PERIOD = 24 hours;
    uint256 public constant MAX_SAME_BLOCK_LIMIT = 1000000e6; // $1M
    
    // ============ STRUCTS ============
    
    /**
     * @dev User interaction tracking
     */
    struct UserInteraction {
        uint256 lastInteractionBlock;
        uint256 lastDepositTime;
        uint256 lastWithdrawTime;
        uint256 totalDepositedInBlock;
        uint256 totalWithdrawnInBlock;
        uint256 cumulativeDeposit;
        bool isWhitelisted;
    }
    
    /**
     * @dev Protection parameters for an asset/strategy
     */
    struct ProtectionParams {
        uint256 minHoldingPeriod;        // Minimum holding period in seconds
        uint256 sameBlockLimit;          // Maximum same-block operation size
        uint256 dailyVolumeLimit;        // Maximum daily volume per user
        uint256 suspiciousPatternThreshold; // Threshold for flagging suspicious patterns
        bool enableSameBlockProtection;  // Whether to enforce same-block restrictions
        bool enableHoldingPeriod;        // Whether to enforce holding periods
        bool isActive;                   // Whether protection is active
    }
    
    /**
     * @dev MEV protection configuration
     */
    struct MEVProtection {
        uint256 maxSlippageDeviation;    // Maximum allowed slippage deviation (basis points)
        uint256 priceImpactThreshold;    // Price impact threshold for large trades
        uint256 sandwichDetectionWindow; // Time window for sandwich attack detection
        bool enablePriceImpactCheck;     // Whether to check price impact
        bool enableSandwichProtection;   // Whether to protect against sandwich attacks
    }

    // ============ STATE VARIABLES ============
    
    // User interaction tracking
    mapping(address => UserInteraction) public userInteractions;
    
    // Protection parameters per strategy
    mapping(address => ProtectionParams) public protectionParams;
    
    // MEV protection settings
    MEVProtection public mevProtection;
    
    // Global settings
    uint256 public globalMinHoldingPeriod = 1; // 1 block minimum
    uint256 public globalSameBlockLimit = 100000e6; // $100k
    uint256 public emergencyPauseThreshold = 10; // 10 suspicious patterns
    
    // Whitelisting
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isOperator;
    
    // Pattern detection
    mapping(address => uint256) public suspiciousPatternCount;
    mapping(uint256 => address[]) public suspiciousTransactionsInBlock;
    
    // Emergency controls
    address public emergencyOperator;
    bool public emergencyPauseActive;

    // ============ EVENTS ============
    
    event InteractionRecorded(
        address indexed user,
        address indexed strategy,
        string operationType,
        uint256 amount,
        uint256 blockNumber
    );
    
    event SuspiciousPatternDetected(
        address indexed user,
        address indexed strategy,
        string patternType,
        uint256 amount,
        uint256 blockNumber
    );
    
    event FlashLoanAttemptBlocked(
        address indexed user,
        address indexed strategy,
        uint256 amount,
        string reason
    );
    
    event MEVAttemptDetected(
        address indexed user,
        uint256 blockNumber,
        string mevType,
        uint256 severity
    );
    
    event ProtectionParamsUpdated(
        address indexed strategy,
        ProtectionParams params
    );
    
    event UserWhitelisted(address indexed user, bool status);
    
    event EmergencyPauseTriggered(string reason, uint256 timestamp);

    // ============ MODIFIERS ============
    
    modifier onlyOperator() {
        require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    modifier onlyEmergencyOperator() {
        require(msg.sender == emergencyOperator || msg.sender == owner(), "Not authorized");
        _;
    }
    
    modifier whenNotEmergencyPaused() {
        require(!emergencyPauseActive, "Emergency pause active");
        _;
    }

    // ============ CONSTRUCTOR ============
    
    constructor(address _emergencyOperator) Ownable(msg.sender) {
        require(_emergencyOperator != address(0), "Zero address");
        emergencyOperator = _emergencyOperator;
        
        // Initialize MEV protection with default values
        mevProtection = MEVProtection({
            maxSlippageDeviation: 200,      // 2%
            priceImpactThreshold: 500,      // 5%
            sandwichDetectionWindow: 2,     // 2 blocks
            enablePriceImpactCheck: true,
            enableSandwichProtection: true
        });
    }

    // ============ MAIN PROTECTION FUNCTIONS ============
    
    /**
     * @dev Validates a deposit operation
     * @param user Address of the user
     * @param strategy Address of the strategy
     * @param amount Deposit amount
     */
    function validateDeposit(
        address user,
        address strategy,
        uint256 amount
    ) external onlyOperator whenNotPaused whenNotEmergencyPaused {
        if (isWhitelisted[user]) return; // Skip checks for whitelisted users
        
        UserInteraction storage userInt = userInteractions[user];
        ProtectionParams memory params = protectionParams[strategy];
        
        // Check same-block restrictions
        if (params.enableSameBlockProtection) {
            _checkSameBlockRestrictions(user, strategy, amount, true);
        }
        
        // Check daily volume limits
        _checkDailyVolumeLimit(user, strategy, amount);
        
        // Update user interaction data
        _updateUserInteraction(user, amount, true);
        
        // Detect suspicious patterns
        _detectSuspiciousPatterns(user, strategy, amount, "deposit");
        
        emit InteractionRecorded(user, strategy, "deposit", amount, block.number);
    }
    
    /**
     * @dev Validates a withdrawal operation
     * @param user Address of the user
     * @param strategy Address of the strategy
     * @param amount Withdrawal amount
     */
    function validateWithdrawal(
        address user,
        address strategy,
        uint256 amount
    ) external onlyOperator whenNotPaused whenNotEmergencyPaused {
        if (isWhitelisted[user]) return; // Skip checks for whitelisted users
        
        UserInteraction storage userInt = userInteractions[user];
        ProtectionParams memory params = protectionParams[strategy];
        
        // Check minimum holding period
        if (params.enableHoldingPeriod) {
            _checkHoldingPeriod(user, strategy);
        }
        
        // Check same-block restrictions
        if (params.enableSameBlockProtection) {
            _checkSameBlockRestrictions(user, strategy, amount, false);
        }
        
        // Update user interaction data
        _updateUserInteraction(user, amount, false);
        
        // Detect suspicious patterns
        _detectSuspiciousPatterns(user, strategy, amount, "withdrawal");
        
        emit InteractionRecorded(user, strategy, "withdrawal", amount, block.number);
    }
    
    /**
     * @dev Validates MEV-related parameters for a transaction
     * @param user Address of the user
     * @param expectedSlippage Expected slippage in basis points
     * @param actualSlippage Actual slippage in basis points
     * @param priceImpact Price impact in basis points
     */
    function validateMEVProtection(
        address user,
        uint256 expectedSlippage,
        uint256 actualSlippage,
        uint256 priceImpact
    ) external onlyOperator {
        if (isWhitelisted[user]) return;
        
        // Check slippage deviation
        if (mevProtection.enablePriceImpactCheck) {
            uint256 slippageDeviation = actualSlippage > expectedSlippage ? 
                actualSlippage - expectedSlippage : expectedSlippage - actualSlippage;
                
            if (slippageDeviation > mevProtection.maxSlippageDeviation) {
                emit MEVAttemptDetected(user, block.number, "excessive_slippage", slippageDeviation);
                _incrementSuspiciousPattern(user);
            }
        }
        
        // Check price impact
        if (mevProtection.enablePriceImpactCheck && priceImpact > mevProtection.priceImpactThreshold) {
            emit MEVAttemptDetected(user, block.number, "high_price_impact", priceImpact);
            _incrementSuspiciousPattern(user);
        }
        
        // Check for sandwich attacks
        if (mevProtection.enableSandwichProtection) {
            _checkSandwichAttack(user);
        }
    }

    // ============ INTERNAL PROTECTION LOGIC ============
    
    function _checkSameBlockRestrictions(
        address user,
        address strategy,
        uint256 amount,
        bool isDeposit
    ) internal {
        UserInteraction storage userInt = userInteractions[user];
        ProtectionParams memory params = protectionParams[strategy];
        
        uint256 limit = params.sameBlockLimit > 0 ? params.sameBlockLimit : globalSameBlockLimit;
        
        if (userInt.lastInteractionBlock == block.number) {
            uint256 blockTotal = isDeposit ? 
                userInt.totalDepositedInBlock + amount : 
                userInt.totalWithdrawnInBlock + amount;
                
            if (blockTotal > limit) {
                emit FlashLoanAttemptBlocked(user, strategy, amount, "Same block limit exceeded");
                revert CommonErrors.NotAllowed();
            }
            
            // Check for rapid deposit-withdrawal patterns
            if (userInt.totalDepositedInBlock > 0 && !isDeposit) {
                emit SuspiciousPatternDetected(user, strategy, "rapid_deposit_withdrawal", amount, block.number);
                _incrementSuspiciousPattern(user);
            }
        }
    }
    
    function _checkHoldingPeriod(address user, address strategy) internal view {
        UserInteraction storage userInt = userInteractions[user];
        ProtectionParams memory params = protectionParams[strategy];
        
        uint256 holdingPeriod = params.minHoldingPeriod > 0 ? params.minHoldingPeriod : globalMinHoldingPeriod;
        
        if (block.timestamp < userInt.lastDepositTime + holdingPeriod) {
            revert CommonErrors.TooSoon();
        }
    }
    
    function _checkDailyVolumeLimit(address user, address strategy, uint256 amount) internal {
        ProtectionParams memory params = protectionParams[strategy];
        
        if (params.dailyVolumeLimit > 0) {
            // This would require additional tracking of daily volumes
            // Implementation would track 24-hour rolling windows
            // For now, we'll use a simplified approach based on cumulative deposits
            UserInteraction storage userInt = userInteractions[user];
            
            if (userInt.cumulativeDeposit + amount > params.dailyVolumeLimit) {
                emit SuspiciousPatternDetected(user, strategy, "daily_volume_exceeded", amount, block.number);
                _incrementSuspiciousPattern(user);
            }
        }
    }
    
    function _detectSuspiciousPatterns(
        address user,
        address strategy,
        uint256 amount,
        string memory operationType
    ) internal {
        UserInteraction storage userInt = userInteractions[user];
        
        // Pattern 1: Unusually large transactions
        if (amount > MAX_SAME_BLOCK_LIMIT) {
            emit SuspiciousPatternDetected(user, strategy, "large_transaction", amount, block.number);
            _incrementSuspiciousPattern(user);
        }
        
        // Pattern 2: High frequency operations
        if (userInt.lastInteractionBlock == block.number) {
            suspiciousTransactionsInBlock[block.number].push(user);
            
            if (suspiciousTransactionsInBlock[block.number].length > 5) {
                emit SuspiciousPatternDetected(user, strategy, "high_frequency", amount, block.number);
                _incrementSuspiciousPattern(user);
            }
        }
        
        // Pattern 3: Round number amounts (possible bot behavior)
        if (amount % 1000e6 == 0 && amount >= 1000e6) { // Round millions
            emit SuspiciousPatternDetected(user, strategy, "round_number_bot", amount, block.number);
            _incrementSuspiciousPattern(user);
        }
    }
    
    function _checkSandwichAttack(address user) internal {
        // Look for patterns where user makes transactions before and after other users
        // This is a simplified check - more sophisticated detection would be needed
        UserInteraction storage userInt = userInteractions[user];
        
        uint256 currentBlock = block.number;
        uint256 windowStart = currentBlock > mevProtection.sandwichDetectionWindow ? 
            currentBlock - mevProtection.sandwichDetectionWindow : 0;
            
        // Check if user had transactions in recent blocks (sandwich pattern)
        if (userInt.lastInteractionBlock >= windowStart && 
            userInt.lastInteractionBlock < currentBlock) {
            emit MEVAttemptDetected(user, block.number, "potential_sandwich", 1);
            _incrementSuspiciousPattern(user);
        }
    }
    
    function _updateUserInteraction(address user, uint256 amount, bool isDeposit) internal {
        UserInteraction storage userInt = userInteractions[user];
        
        if (userInt.lastInteractionBlock != block.number) {
            // Reset block counters for new block
            userInt.totalDepositedInBlock = 0;
            userInt.totalWithdrawnInBlock = 0;
        }
        
        userInt.lastInteractionBlock = block.number;
        
        if (isDeposit) {
            userInt.lastDepositTime = block.timestamp;
            userInt.totalDepositedInBlock += amount;
            userInt.cumulativeDeposit += amount;
        } else {
            userInt.lastWithdrawTime = block.timestamp;
            userInt.totalWithdrawnInBlock += amount;
            // Reduce cumulative deposit (but not below zero)
            userInt.cumulativeDeposit = userInt.cumulativeDeposit > amount ? 
                userInt.cumulativeDeposit - amount : 0;
        }
    }
    
    function _incrementSuspiciousPattern(address user) internal {
        suspiciousPatternCount[user]++;
        
        if (suspiciousPatternCount[user] >= emergencyPauseThreshold) {
            emergencyPauseActive = true;
            emit EmergencyPauseTriggered("Too many suspicious patterns detected", block.timestamp);
        }
    }

    // ============ ADMIN FUNCTIONS ============
    
    function setProtectionParams(
        address strategy,
        ProtectionParams calldata params
    ) external onlyOwner {
        require(strategy != address(0), "Zero address");
        require(params.minHoldingPeriod <= MAX_HOLDING_PERIOD, "Holding period too long");
        require(params.sameBlockLimit <= MAX_SAME_BLOCK_LIMIT, "Limit too high");
        
        protectionParams[strategy] = params;
        emit ProtectionParamsUpdated(strategy, params);
    }
    
    function setMEVProtection(MEVProtection calldata _mevProtection) external onlyOwner {
        require(_mevProtection.maxSlippageDeviation <= 1000, "Slippage deviation too high"); // Max 10%
        require(_mevProtection.priceImpactThreshold <= 2000, "Price impact threshold too high"); // Max 20%
        
        mevProtection = _mevProtection;
    }
    
    function setWhitelist(address user, bool status) external onlyOwner {
        isWhitelisted[user] = status;
        emit UserWhitelisted(user, status);
    }
    
    function setOperator(address operator, bool status) external onlyOwner {
        isOperator[operator] = status;
    }
    
    function setGlobalParams(
        uint256 _minHoldingPeriod,
        uint256 _sameBlockLimit,
        uint256 _emergencyThreshold
    ) external onlyOwner {
        require(_minHoldingPeriod <= MAX_HOLDING_PERIOD, "Period too long");
        require(_sameBlockLimit <= MAX_SAME_BLOCK_LIMIT, "Limit too high");
        
        globalMinHoldingPeriod = _minHoldingPeriod;
        globalSameBlockLimit = _sameBlockLimit;
        emergencyPauseThreshold = _emergencyThreshold;
    }
    
    function resetSuspiciousPatterns(address user) external onlyOwner {
        suspiciousPatternCount[user] = 0;
    }
    
    function emergencyPause() external onlyEmergencyOperator {
        emergencyPauseActive = true;
        emit EmergencyPauseTriggered("Manual emergency pause", block.timestamp);
    }
    
    function emergencyUnpause() external onlyOwner {
        emergencyPauseActive = false;
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getUserInteraction(address user) external view returns (UserInteraction memory) {
        return userInteractions[user];
    }
    
    function getProtectionParams(address strategy) external view returns (ProtectionParams memory) {
        return protectionParams[strategy];
    }
    
    function getMEVProtection() external view returns (MEVProtection memory) {
        return mevProtection;
    }
    
    function isOperationAllowed(
        address user,
        address strategy,
        uint256 amount,
        bool isDeposit
    ) external view returns (bool allowed, string memory reason) {
        if (emergencyPauseActive) return (false, "Emergency pause active");
        if (isWhitelisted[user]) return (true, "Whitelisted user");
        
        UserInteraction memory userInt = userInteractions[user];
        ProtectionParams memory params = protectionParams[strategy];
        
        // Check same-block limits
        if (params.enableSameBlockProtection && userInt.lastInteractionBlock == block.number) {
            uint256 limit = params.sameBlockLimit > 0 ? params.sameBlockLimit : globalSameBlockLimit;
            uint256 blockTotal = isDeposit ? 
                userInt.totalDepositedInBlock + amount : 
                userInt.totalWithdrawnInBlock + amount;
                
            if (blockTotal > limit) {
                return (false, "Same block limit exceeded");
            }
        }
        
        // Check holding period for withdrawals
        if (!isDeposit && params.enableHoldingPeriod) {
            uint256 holdingPeriod = params.minHoldingPeriod > 0 ? params.minHoldingPeriod : globalMinHoldingPeriod;
            if (block.timestamp < userInt.lastDepositTime + holdingPeriod) {
                return (false, "Minimum holding period not met");
            }
        }
        
        return (true, "Operation allowed");
    }
}