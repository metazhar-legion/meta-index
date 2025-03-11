import React from 'react';
import { Alert, AlertTitle, Snackbar, Box } from '@mui/material';

/**
 * Standardized error handling utilities
 */

// Parse error messages from various sources
export const parseErrorMessage = (error: any): string => {
  if (!error) return 'An unknown error occurred';
  
  // Handle ethers.js errors
  if (error.reason) return error.reason;
  if (error.message) {
    // Clean up common ethers.js error messages
    const message = error.message;
    if (message.includes('user rejected transaction')) {
      return 'Transaction was rejected';
    }
    if (message.includes('insufficient funds')) {
      return 'Insufficient funds for transaction';
    }
    return message;
  }
  
  // Handle string errors
  if (typeof error === 'string') return error;
  
  // Fallback
  return 'An unexpected error occurred';
};

// Component for displaying contract errors
export const ContractErrorMessage: React.FC<{
  error: any;
  onClose?: () => void;
  severity?: 'error' | 'warning';
}> = ({ error, onClose, severity = 'error' }) => {
  if (!error) return null;
  
  const errorMessage = parseErrorMessage(error);
  
  return (
    <Alert 
      severity={severity} 
      onClose={onClose}
      sx={{ mb: 2 }}
    >
      <AlertTitle>{severity === 'error' ? 'Error' : 'Warning'}</AlertTitle>
      {errorMessage}
    </Alert>
  );
};

// Error toast notification
export const ErrorToast: React.FC<{
  error: any;
  open: boolean;
  onClose: () => void;
}> = ({ error, open, onClose }) => {
  const errorMessage = parseErrorMessage(error);
  
  return (
    <Snackbar
      open={open}
      autoHideDuration={6000}
      onClose={onClose}
      anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
    >
      <Alert onClose={onClose} severity="error" sx={{ width: '100%' }}>
        {errorMessage}
      </Alert>
    </Snackbar>
  );
};

// Retry mechanism for contract calls
export const withRetry = async <T extends any>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  delay: number = 1000
): Promise<T> => {
  let lastError: any;
  
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      
      // Don't retry user rejections
      if (error.message && error.message.includes('user rejected')) {
        throw error;
      }
      
      // Wait before retrying
      if (attempt < maxRetries - 1) {
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  
  throw lastError;
};
