// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CommonErrors
 * @notice Library containing common error definitions used across the protocol
 */
library CommonErrors {
    // Access control errors
    error Unauthorized();
    error InvalidCaller();
    
    // Input validation errors
    error ZeroAddress();
    error ZeroAmount();
    error InvalidParameter();
    error InvalidAsset();
    error InvalidToken();
    error InvalidStrategy();
    error InvalidWrapper();
    
    // Operational errors
    error OperationPaused();
    error TooEarly();
    error TooLate();
    error Expired();
    error AlreadyInitialized();
    error NotInitialized();
    error InsufficientBalance();
    error InsufficientCollateral();
    error ExceedsMaximum();
    error BelowMinimum();
    error SlippageTooHigh();
    error DeadlineExpired();
    
    // Position errors
    error NoPositionOpen();
    error PositionAlreadyOpen();
    error PositionLiquidated();
    error CircuitBreakerTriggered();
    
    // System errors
    error TransferFailed();
    error ApprovalFailed();
    error OracleFailure();
    error MathError();
}
