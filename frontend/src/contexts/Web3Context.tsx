import React, { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
// Import types
import { metaMask, metaMaskHooks } from '../connectors';
import { ethers } from 'ethers';

// Define user roles
export enum UserRole {
  INVESTOR = 'investor',
  DAO_MEMBER = 'dao_member',
  PORTFOLIO_MANAGER = 'portfolio_manager',
  COMPOSABLE_RWA_USER = 'composable_rwa_user',
}

// Define Web3 context type
interface Web3ContextType {
  account: string | null;
  chainId: number | null;
  connect: () => Promise<void>;
  disconnect: () => void;
  isActive: boolean;
  isLoading: boolean;
  provider: ethers.Provider | null;
  userRole: UserRole;
  setUserRole: (role: UserRole) => void;
  refreshProvider: () => Promise<ethers.Provider | null>;
}

// Create context with default values
const Web3Context = createContext<Web3ContextType>({
  account: null,
  chainId: null,
  connect: async () => {},
  disconnect: () => {},
  isActive: false,
  isLoading: false,
  provider: null,
  userRole: UserRole.INVESTOR,
  setUserRole: () => {},
  refreshProvider: async () => null,
});

// MetaMask connector is imported from connectors

interface Web3ProviderProps {
  children: ReactNode;
}

export const Web3ContextProvider: React.FC<Web3ProviderProps> = ({ children }) => {
  // Use hooks from metaMask connector
  const { useAccount, useChainId, useIsActive, useProvider } = metaMaskHooks;
  
  // Get values from hooks
  const account = useAccount();
  const chainId = useChainId();
  const isActive = useIsActive();
  
  // Store the provider in state to avoid recreating it on every render
  const [library, setLibrary] = useState<ethers.BrowserProvider | null>(null);
  
  // Get the raw provider from web3-react but don't store it directly
  const rawProviderFromHook = useProvider();
  
  // Create a function to get a provider on demand instead of storing it
  const getProvider = useCallback(async () => {
    if (!rawProviderFromHook) {
      return null;
    }
    
    try {
      // Create a minimal provider that only uses the ethereum object
      // This approach completely avoids circular references
      if (typeof window !== 'undefined' && window.ethereum) {
        // Try to get the chainId using the request method with timeout protection
        try {
          if (window.ethereum && 'request' in window.ethereum) {
            // Use Promise.race to add timeout protection
            await Promise.race([
              window.ethereum.request({ method: 'eth_chainId' }),
              new Promise((_, reject) => setTimeout(() => reject(new Error('chainId request timed out')), 3000))
            ]);
          }
        } catch (chainIdError) {
          // Continue despite this error - it's not critical
        }
        
        // Create provider with timeout protection
        try {
          const provider = new ethers.BrowserProvider(window.ethereum);
          
          // Verify provider is working by checking network with timeout
          await Promise.race([
            provider.getNetwork(),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Network check timed out')), 3000)
            )
          ]);
          
          return provider;
        } catch (providerError) {
          // If provider creation or verification fails, try a different approach
          // Force a refresh of accounts first
          try {
            await window.ethereum.request({ method: 'eth_requestAccounts' });
            const freshProvider = new ethers.BrowserProvider(window.ethereum);
            return freshProvider;
          } catch (alternativeError) {
            return null;
          }
        }
      } else {
        return null;
      }
    } catch (error) {
      return null;
    }
  }, [rawProviderFromHook]);
  
  // Update the provider when the raw provider changes
  useEffect(() => {
    // Cleanup flag to prevent state updates after unmount
    let isMounted = true;
    
    const setupProvider = async () => {
      // Don't try to create a provider if we're not connected
      if (!isActive || !rawProviderFromHook) {
        if (isMounted) setLibrary(null);
        return;
      }
      
      try {
        const provider = await getProvider();
        if (isMounted && provider) {
          setLibrary(provider);
        }
      } catch (error) {
        console.error('Error setting up provider:', error);
        if (isMounted) setLibrary(null);
      }
    };
    
    setupProvider();
    
    // Cleanup function
    return () => {
      isMounted = false;
    };
  }, [rawProviderFromHook, isActive, getProvider]);
  const [isLoading, setIsLoading] = useState(false);
  const [userRole, setUserRole] = useState<UserRole>(UserRole.INVESTOR);

  // Connect to wallet with improved error handling
  const connect = async () => {
    setIsLoading(true);
    try {
      // Clear any previous state
      await metaMask.resetState();
      
      // Small delay to ensure clean state
      await new Promise(resolve => setTimeout(resolve, 100));
      
      // Activate the connector
      await metaMask.activate();
      
      // Create a new provider after successful connection
      const newProvider = await getProvider();
      if (newProvider) {
        setLibrary(newProvider);
        // Save connection state
        localStorage.setItem('isWalletConnected', 'true');
      } else {
        throw new Error('Failed to create provider after connection');
      }
    } catch (error) {
      console.error('Error connecting to wallet:', error);
      // Make sure to clear any partial state
      localStorage.removeItem('isWalletConnected');
    } finally {
      setIsLoading(false);
    }
  };

  // Disconnect wallet with improved error handling
  const disconnect = () => {
    try {
      // Remove from localStorage first
      localStorage.removeItem('isWalletConnected');
      
      // Then reset the connector state
      metaMask.resetState();
      
      // Clear the provider
      setLibrary(null);
    } catch (error) {
      console.error('Error disconnecting wallet:', error);
    }
  };

  // Auto-connect if previously connected with improved reliability
  useEffect(() => {
    // Cleanup flag to prevent state updates after unmount
    let isMounted = true;
    
    const connectWalletOnPageLoad = async () => {
      // Always try to auto-connect if MetaMask is available, even if localStorage isn't set
      // This helps with cases where the user has already connected MetaMask but localStorage was cleared
      const shouldAutoConnect = localStorage.getItem('isWalletConnected') === 'true' || 
                               (typeof window !== 'undefined' && window.ethereum?.isMetaMask);
      
      if (shouldAutoConnect) {
        try {
          if (isMounted) setIsLoading(true);
          
          // Use a timeout to ensure MetaMask has time to initialize
          await new Promise(resolve => setTimeout(resolve, 300));
          
          // Check if MetaMask is unlocked before trying to connect
          let isUnlocked = false;
          try {
            if (window.ethereum?.request) {
              // This will only succeed if the wallet is unlocked
              const accounts = await window.ethereum.request({ method: 'eth_accounts' });
              isUnlocked = Array.isArray(accounts) && accounts.length > 0;
            }
          } catch (error) {
            // Silent fail - no need to log this common check
          }
          
          // Only proceed with activation if MetaMask is unlocked
          if (isUnlocked && isMounted) {
            await metaMask.activate();
            
            // After successful activation, create a new provider
            if (isMounted) {
              // Create provider using window.ethereum directly
              if (typeof window !== 'undefined' && window.ethereum) {
                try {
                  const provider = new ethers.BrowserProvider(window.ethereum as any);
                  setLibrary(provider);
                  // Save connection state on successful auto-connect
                  localStorage.setItem('isWalletConnected', 'true');
                } catch (providerError) {
                  console.error('Error creating provider during auto-connect');
                }
              }
            }
          }
          // No else needed - silently skip auto-connect if conditions aren't met
        } catch (error) {
          console.error('Error auto-connecting to wallet:', error);
          // Clear the localStorage if there was an error
          localStorage.removeItem('isWalletConnected');
        } finally {
          if (isMounted) setIsLoading(false);
        }
      }
    };
    
    // Small delay before auto-connecting to avoid race conditions
    const timeoutId = setTimeout(connectWalletOnPageLoad, 500);
    
    // Cleanup function
    return () => {
      isMounted = false;
      clearTimeout(timeoutId);
    };
  }, []);

  // Track last refresh time to prevent excessive refreshes
  const [lastRefreshTime, setLastRefreshTime] = useState<number>(0);
  
  // Function to refresh the provider - useful for handling BlockOutOfRange errors
  const refreshProvider = useCallback(async () => {
    // Prevent refreshing more than once every 3 seconds
    const now = Date.now();
    const timeSinceLastRefresh = now - lastRefreshTime;
    if (timeSinceLastRefresh < 3000) {
      return library; // Return existing provider if we've refreshed recently
    }
    
    try {
      // Only proceed if we're connected
      if (!isActive) {
        return null;
      }
      
      // Use window.ethereum directly to create a fresh provider
      if (typeof window !== 'undefined' && window.ethereum) {
        try {
          // Request accounts to ensure connection is fresh
          await window.ethereum.request({ method: 'eth_requestAccounts' });
          
          // Create a fresh provider
          const freshProvider = new ethers.BrowserProvider(window.ethereum);
          
          // Check network and block number to verify provider is working
          await freshProvider.getNetwork();
          const latestBlock = await freshProvider.getBlockNumber();
          console.log('Connected to network with latest block:', latestBlock);
          
          // Create a wrapper around the provider to handle block height errors
          const enhancedProvider = freshProvider;
          
          // Store the original call method
          const originalCall = freshProvider.call.bind(freshProvider);
          
          // Override the call method to handle block height errors
          const enhancedCall = async (transaction: ethers.TransactionRequest): Promise<string> => {
            try {
              // First try with the original method
              return await originalCall(transaction);
            } catch (error: any) {
              // Check if this is a block height error
              const errorMsg = error?.message || '';
              const errorData = error?.data?.message || '';
              const isBlockHeightError = 
                errorMsg.includes('block height') || 
                errorMsg.includes('BlockOutOfRange') ||
                errorData.includes('block height') ||
                errorData.includes('BlockOutOfRange');
              
              if (isBlockHeightError) {
                console.log(`Block height error detected, forcing latest block`);
                // Force the transaction to use the latest block
                const txWithLatestBlock = {
                  ...transaction,
                  blockTag: 'latest'
                };
                return await originalCall(txWithLatestBlock);
              }
              
              // Re-throw other errors
              throw error;
            }
          };
          
          // Replace the call method
          (enhancedProvider as any).call = enhancedCall;
          
          // Update the library state
          setLibrary(enhancedProvider);
          
          // Update last refresh time
          setLastRefreshTime(now);
          
          return enhancedProvider;
        } catch (error) {
          console.error('Error refreshing provider:', error);
          return library; // Return existing provider as fallback
        }
      } else {
        return library; // Return existing provider as fallback
      }
    } catch (error) {
      console.error('Unexpected error in refreshProvider:', error);
      return library; // Return existing provider as fallback
    }
  }, [isActive, library]);

  return (
    <Web3Context.Provider
      value={{
        account: account || null,
        chainId: chainId || null,
        connect,
        disconnect,
        isActive: isActive || false,
        isLoading,
        provider: library || null,
        userRole,
        setUserRole,
        refreshProvider,
      }}
    >
      {children}
    </Web3Context.Provider>
  );
};

// Custom hook to use the Web3 context
export const useWeb3 = () => useContext(Web3Context);
