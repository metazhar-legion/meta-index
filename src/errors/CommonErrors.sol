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
    error ZeroValue();
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
    error NotAllowed();

    // State errors
    error InvalidState();
    error AlreadyInitialized();
    error NotInitialized();
    error NotActive();
    error TooSoon();
    error EmptyString();

    // Operation errors
    error OperationFailed();
    error OperationPaused();

    // Array errors
    error EmptyArray();
    error MismatchedArrayLengths();
    error LengthMismatch();

    // Token errors
    error TokenAlreadyExists();
    error TokenNotFound();
    error TransferFailed();
    error InsufficientBalance();
    error InsufficientAllowance();
    error SlippageTooHigh();
    error PairNotSupported();

    // General errors
    error AlreadyExists();
    error NotFound();
    error NotSupported();

    // Time-related errors
    error InvalidTimeParameters();
    error TooEarly();
    error TooLate();
    error Expired();

    // Governance errors
    error GovernanceDisabled();
    error ProposalInvalid();
    error ProposalAlreadyExecuted();
    error ProposalCanceled();
    error VotingPeriodActive();
    error VotingPeriodEnded();
    error AlreadyVoted();
    error ProposalRejected();

    // Price errors
    error PriceNotAvailable();
}
