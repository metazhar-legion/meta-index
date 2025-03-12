import { ethers } from 'ethers';
import { createLogger } from './logging';
import { withRetry } from './errors';

const logger = createLogger('ContractUtils');

/**
 * Standardized contract interaction utilities
 */

// Safely initialize a contract with proper error handling
export const initializeContract = async <T extends ethers.Contract>(
  address: string,
  abi: any,
  providerOrSigner: ethers.Provider | ethers.Signer | null,
  requireSigner: boolean = false
): Promise<T | null> => {
  if (!providerOrSigner) {
    logger.warn('No provider or signer available for contract initialization');
    return null;
  }
  
  try {
    // Check if we need a signer but were given a provider
    if (requireSigner && 'provider' in providerOrSigner) {
      // We have a signer, proceed
      return new ethers.Contract(address, abi, providerOrSigner) as T;
    } else if (requireSigner && !('provider' in providerOrSigner)) {
      logger.warn('Signer required but provider was provided');
      return null;
    }
    
    // Create the contract instance
    const contract = new ethers.Contract(address, abi, providerOrSigner) as T;
    
    // Verify the contract is accessible with a simple call
    // This helps catch issues early
    await contract.getAddress();
    
    return contract;
  } catch (error) {
    logger.error(`Failed to initialize contract at ${address}`, error);
    return null;
  }
};

// Safely call a contract read method with proper error handling
export const safeContractCall = async <T>(
  contract: any,
  methodName: string,
  args: any[] = [],
  fallbackValue: T
): Promise<T> => {
  try {
    if (!contract || typeof contract[methodName] !== 'function') {
      logger.error(`Invalid contract or method: ${methodName}`);
      return fallbackValue;
    }
    
    // Call the contract method with the provided arguments
    const result = await contract[methodName](...args);
    
    // In ethers.js v6, some methods might return objects instead of primitive values
    // Ensure we're handling both formats correctly
    let processedResult: any;
    
    if (typeof result === 'object' && result !== null) {
      // For BigNumber or similar objects that have a toString method
      if (typeof result.toString === 'function') {
        logger.debug(`Converting object result to string for ${methodName}`);
        processedResult = result;
      } else if (Array.isArray(result)) {
        // Handle array results
        processedResult = result;
      } else {
        // For other objects, try to extract meaningful data
        logger.debug(`Complex object returned from ${methodName}, using as is`);
        processedResult = result;
      }
    } else {
      // For primitive values
      processedResult = result;
    }
    
    logger.debug(`Contract call successful: ${methodName}`, 
      typeof processedResult === 'object' && processedResult !== null ? 
        (processedResult.toString ? processedResult.toString() : JSON.stringify(processedResult)) : 
        String(processedResult)
    );
    
    return processedResult as T;
  } catch (error) {
    logger.error(`Contract call failed: ${methodName}`, error);
    return fallbackValue;
  }
};

// Safely execute a contract write method (transaction)
export const safeContractTransaction = async <T>(
  contractFn: () => Promise<ethers.ContractTransactionResponse>,
  methodName: string,
  onSuccess?: (receipt: ethers.ContractTransactionReceipt) => Promise<T> | T,
  onError?: (error: any) => void
): Promise<T | null> => {
  try {
    logger.info(`Sending transaction: ${methodName}`);
    
    // Send the transaction
    const tx = await contractFn();
    logger.logTransaction(tx.hash, methodName, 'sent');
    
    // Wait for confirmation
    const receipt = await tx.wait();
    logger.logTransaction(tx.hash, methodName, 'confirmed');
    
    // Call success callback if provided
    if (onSuccess && receipt) {
      return await onSuccess(receipt);
    }
    
    return null;
  } catch (error) {
    logger.error(`Transaction failed: ${methodName}`, error);
    
    // Call error callback if provided
    if (onError) {
      onError(error);
    }
    
    return null;
  }
};

// Get token balance with proper formatting
export const getTokenBalance = async (
  tokenContract: ethers.Contract | null,
  account: string | null,
  decimals: number = 18
): Promise<string> => {
  if (!tokenContract || !account) {
    return '0';
  }
  
  try {
    const balance = await safeContractCall(
      tokenContract,
      'balanceOf',
      [account],
      BigInt(0)
    );
    
    return ethers.formatUnits(balance, decimals);
  } catch (error) {
    logger.error('Failed to get token balance', error);
    return '0';
  }
};

// Check and set token allowance
export const ensureTokenAllowance = async (
  tokenContract: ethers.Contract | null,
  ownerAddress: string | null,
  spenderAddress: string,
  amount: bigint,
  onApprovalNeeded?: () => void,
  onApprovalComplete?: () => void
): Promise<boolean> => {
  if (!tokenContract || !ownerAddress) {
    return false;
  }
  
  try {
    // Check current allowance
    const currentAllowance = await safeContractCall(
      tokenContract,
      'allowance',
      [ownerAddress, spenderAddress],
      BigInt(0)
    );
    
    // If allowance is sufficient, return true
    if (currentAllowance && BigInt(currentAllowance.toString()) >= BigInt(amount.toString())) {
      return true;
    }
    
    // Notify that approval is needed
    if (onApprovalNeeded) {
      onApprovalNeeded();
    }
    
    // Request approval
    await safeContractTransaction(
      () => tokenContract.approve(spenderAddress, amount),
      'approve',
      () => {
        if (onApprovalComplete) {
          onApprovalComplete();
        }
        return true;
      }
    );
    
    return true;
  } catch (error) {
    logger.error('Failed to set token allowance', error);
    return false;
  }
};
