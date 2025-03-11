import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';
import { createLogger } from './logging';

const logger = createLogger('Hooks');

/**
 * Custom hooks for common patterns across components
 */

// Hook for delayed state updates to prevent UI flickering
export function useDelayedUpdate<T>(initialValue: T, delayMs: number = 3000) {
  const [currentValue, setCurrentValue] = useState<T>(initialValue);
  const [pendingValue, setPendingValue] = useState<T | null>(null);
  const [lastUpdateTime, setLastUpdateTime] = useState(Date.now());
  
  // Apply pending value with a smooth transition
  useEffect(() => {
    if (pendingValue !== null) {
      const now = Date.now();
      const timeSinceLastUpdate = now - lastUpdateTime;
      
      if (timeSinceLastUpdate >= delayMs) {
        // If enough time has passed, update immediately
        setCurrentValue(pendingValue);
        setPendingValue(null);
        setLastUpdateTime(now);
      } else {
        // Otherwise, schedule an update after the minimum interval
        const timeToWait = delayMs - timeSinceLastUpdate;
        const timer = setTimeout(() => {
          setCurrentValue(pendingValue);
          setPendingValue(null);
          setLastUpdateTime(Date.now());
        }, timeToWait);
        
        return () => clearTimeout(timer);
      }
    }
  }, [pendingValue, lastUpdateTime, delayMs]);
  
  // Function to update the value with delay
  const updateValue = useCallback((newValue: T, skipDelay: boolean = false) => {
    if (skipDelay) {
      setCurrentValue(newValue);
      setLastUpdateTime(Date.now());
    } else {
      setPendingValue(newValue);
    }
  }, []);
  
  // Force an immediate update
  const forceUpdate = useCallback((newValue: T) => {
    setLastUpdateTime(0); // Reset the last update time
    setPendingValue(newValue);
  }, []);
  
  return {
    value: currentValue,
    updateValue,
    forceUpdate,
    isPending: pendingValue !== null
  };
}

// Hook for handling contract calls with proper error handling and retries
export function useContractCall<T>(
  defaultValue: T,
  maxRetries: number = 3
) {
  const [value, setValue] = useState<T>(defaultValue);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  
  // Function to execute the contract call
  const executeCall = useCallback(async (
    callFn: () => Promise<T>,
    onSuccess?: (result: T) => void,
    skipLoadingState: boolean = false
  ) => {
    if (!skipLoadingState) {
      setLoading(true);
    }
    setError(null);
    
    try {
      // Execute the call
      const result = await callFn();
      
      // Update state with result
      setValue(result);
      
      // Call success callback if provided
      if (onSuccess) {
        onSuccess(result);
      }
      
      // Reset retry count on success
      setRetryCount(0);
      
      return result;
    } catch (err) {
      logger.error('Contract call failed', err);
      
      // Increment retry count
      const newRetryCount = retryCount + 1;
      setRetryCount(newRetryCount);
      
      // Check if we should retry
      if (newRetryCount <= maxRetries) {
        logger.info(`Retrying contract call (${newRetryCount}/${maxRetries})`);
        
        // Add a small delay before retrying
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // Retry the call
        return executeCall(callFn, onSuccess, skipLoadingState);
      }
      
      // Set error state if we've exhausted retries
      setError(err as Error);
      throw err;
    } finally {
      if (!skipLoadingState) {
        setLoading(false);
      }
    }
  }, [retryCount, maxRetries]);
  
  return {
    value,
    loading,
    error,
    executeCall,
    reset: useCallback(() => {
      setValue(defaultValue);
      setLoading(false);
      setError(null);
      setRetryCount(0);
    }, [defaultValue])
  };
}

// Hook for handling blockchain events
export function useBlockchainEvents(
  eventName: string,
  handler: () => void,
  delay: number = 2000
) {
  useEffect(() => {
    // Import eventBus dynamically to avoid circular dependencies
    const { default: eventBus, EVENTS } = require('./eventBus');
    
    // Create the event handler with delay
    const eventHandler = () => {
      // Add a small delay to ensure blockchain state is updated
      setTimeout(() => {
        handler();
      }, delay);
    };
    
    // Subscribe to the event
    const unsubscribe = eventBus.on(eventName, eventHandler);
    
    // Clean up subscription on unmount
    return () => {
      unsubscribe();
    };
  }, [eventName, handler, delay]);
}
