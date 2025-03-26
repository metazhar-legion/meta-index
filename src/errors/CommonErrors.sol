// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CommonErrors
 * @dev Library containing common error definitions used across the protocol
 */
library CommonErrors {
    // Address validation errors
    error ZeroAddress();
    error InvalidAddress();
    
    // Value validation errors
    error InvalidValue();
    error ValueTooLow();
    error ValueTooHigh();
    error ValueOutOfRange(uint256 value, uint256 min, uint256 max);
    
    // Percentage/basis point errors
    error InvalidPercentage();
    error PercentageTooHigh();
    error TotalExceeds100Percent();
    
    // Access control errors
    error Unauthorized();
    error CallerNotOwner();
    
    // State errors
    error InvalidState();
    error AlreadyInitialized();
    error NotInitialized();
    
    // Operation errors
    error OperationFailed();
    error OperationPaused();
    
    // Array errors
    error EmptyArray();
    error MismatchedArrayLengths();
    
    // Token errors
    error TokenAlreadyExists();
    error TokenNotFound();
    error TransferFailed();
    
    // Time-related errors
    error InvalidTimeParameters();
    error TooEarly();
    error TooLate();
    
    // Governance errors
    error GovernanceDisabled();
    error ProposalInvalid();
    error ProposalAlreadyExecuted();
    error ProposalCanceled();
    error VotingPeriodActive();
    error VotingPeriodEnded();
    error AlreadyVoted();
    error ProposalRejected();
}
