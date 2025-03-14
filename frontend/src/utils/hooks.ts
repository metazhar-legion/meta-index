import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';
import { createLogger } from './logging';

const logger = createLogger('Hooks');

/**
 * Utility function to perform a deep equality check between two values
 * This is used to prevent unnecessary re-renders when data hasn't changed
 */
function isDeepEqual(obj1: any, obj2: any): boolean {
  // Handle primitive types and null/undefined
  if (obj1 === obj2) return true;
  if (obj1 == null || obj2 == null) return false;
  if (typeof obj1 !== 'object' && typeof obj2 !== 'object') return obj1 === obj2;

  // Get keys of both objects
  const keys1 = Object.keys(obj1);
  const keys2 = Object.keys(obj2);

  // Check if number of keys is the same
  if (keys1.length !== keys2.length) return false;

  // Check if all keys in obj1 exist in obj2 and have the same values
  for (const key of keys1) {
    if (!keys2.includes(key)) return false;
    if (!isDeepEqual(obj1[key], obj2[key])) return false;
  }

  return true;
}

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
    // Only update if the value has actually changed (using deep comparison)
    if (!isDeepEqual(newValue, currentValue)) {
      logger.debug('Value changed, updating state');
      if (skipDelay) {
        setCurrentValue(newValue);
        setLastUpdateTime(Date.now());
      } else {
        setPendingValue(newValue);
      }
    } else {
      logger.debug('Value unchanged, skipping update');
    }
  }, [currentValue]);
  
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
  ): Promise<T> => {
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
  eventConfig: { eventName: string; handler: () => void; delay?: number }
): void;

// Legacy method signature for backward compatibility
export function useBlockchainEvents(
  eventName: string,
  handler: () => void,
  delay?: number
): void;

// Implementation that handles both signatures
export function useBlockchainEvents(
  eventNameOrConfig: string | { eventName: string; handler: () => void; delay?: number },
  handlerOrUndefined?: () => void,
  delayOrUndefined?: number
) {
  useEffect(() => {
    // Import eventBus dynamically to avoid circular dependencies
    const { default: eventBus, EVENTS } = require('./eventBus');
    
    // Determine parameters based on signature used
    let eventName: string;
    let handler: () => void;
    let delay: number = 2000; // Default delay
    
    if (typeof eventNameOrConfig === 'string') {
      // Legacy signature
      eventName = eventNameOrConfig;
      handler = handlerOrUndefined as () => void;
      if (delayOrUndefined !== undefined) {
        delay = delayOrUndefined;
      }
    } else {
      // Object signature
      eventName = eventNameOrConfig.eventName;
      handler = eventNameOrConfig.handler;
      if (eventNameOrConfig.delay !== undefined) {
        delay = eventNameOrConfig.delay;
      }
    }
    
    // Create an event handler with a small delay to ensure blockchain state is updated
    // but without nested timeouts that could cause infinite loops
    const eventHandler = (...args: any[]) => {
      // Log the event reception for debugging
      logger.debug(`Received event ${eventName} with data:`, args[0] || 'No data');
      
      // Add a small delay to ensure blockchain state is updated before handling
      setTimeout(() => {
        // Execute the handler without passing args to avoid TypeScript errors
        // The original handler doesn't expect arguments
        handler();
      }, delay);
    };
    
    // Subscribe to the event
    const unsubscribe = eventBus.on(eventName, eventHandler);
    
    // Clean up subscription on unmount
    return () => {
      unsubscribe();
    };
  }, [eventNameOrConfig, handlerOrUndefined, delayOrUndefined]);
}
