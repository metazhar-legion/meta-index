import React, { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
// Import types
import { metaMask, metaMaskHooks } from '../connectors';
import { ethers } from 'ethers';

// Define user roles
export enum UserRole {
  INVESTOR = 'investor',
  DAO_MEMBER = 'dao_member',
  PORTFOLIO_MANAGER = 'portfolio_manager',
}

// Define Web3 context type
interface Web3ContextType {
  account: string | null;
  chainId: number | null;
  connect: () => Promise<void>;
  disconnect: () => void;
  isActive: boolean;
  isLoading: boolean;
  provider: ethers.BrowserProvider | null;
  userRole: UserRole;
  setUserRole: (role: UserRole) => void;
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
    console.log('getProvider called, rawProviderFromHook:', !!rawProviderFromHook);
    if (!rawProviderFromHook) {
      console.log('No raw provider available');
      return null;
    }
    
    try {
      // Create a minimal provider that only uses the ethereum object
      // This approach completely avoids circular references
      if (typeof window !== 'undefined' && window.ethereum) {
        console.log('Creating provider from window.ethereum');
        console.log('window.ethereum properties:', Object.keys(window.ethereum));
        // Safely check for MetaMask property
        console.log('window.ethereum.isMetaMask:', window.ethereum && 'isMetaMask' in window.ethereum ? window.ethereum.isMetaMask : 'not available');
        // Safely check for chainId - it might not be directly accessible
        try {
          // Try to get the chainId using the request method if available
          if (window.ethereum && 'request' in window.ethereum) {
            // Use type assertion to avoid TypeScript errors
            (window.ethereum as any).request({ method: 'eth_chainId' })
              .then((chainId: string) => console.log('Chain ID from request:', chainId))
              .catch((error: any) => console.error('Error getting chainId:', error));
          }
        } catch (chainIdError) {
          console.error('Error checking chainId:', chainIdError);
        }
        
        const provider = new ethers.BrowserProvider(window.ethereum as any);
        console.log('Provider created successfully');
        return provider;
      } else {
        console.error('No ethereum object found in window');
        return null;
      }
    } catch (error) {
      console.error('Error creating provider:', error);
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
    console.log('Connect wallet called');
    setIsLoading(true);
    try {
      // Clear any previous state
      console.log('Resetting MetaMask state');
      await metaMask.resetState();
      
      // Small delay to ensure clean state
      console.log('Waiting for clean state');
      await new Promise(resolve => setTimeout(resolve, 100));
      
      // Activate the connector
      console.log('Activating MetaMask connector');
      await metaMask.activate();
      console.log('MetaMask activated successfully');
      
      // Create a new provider after successful connection
      console.log('Creating new provider');
      const newProvider = await getProvider();
      if (newProvider) {
        console.log('Provider created successfully, setting library');
        setLibrary(newProvider);
        // Save connection state
        localStorage.setItem('isWalletConnected', 'true');
        console.log('Wallet connection state saved');
      } else {
        console.error('Failed to create provider after connection');
        throw new Error('Failed to create provider after connection');
      }
    } catch (error) {
      console.error('Error connecting to wallet:', error);
      // Make sure to clear any partial state
      localStorage.removeItem('isWalletConnected');
      console.log('Wallet connection state cleared due to error');
    } finally {
      setIsLoading(false);
      console.log('Connect wallet process completed');
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

  // Auto-connect if previously connected
  useEffect(() => {
    // Cleanup flag to prevent state updates after unmount
    let isMounted = true;
    
    const connectWalletOnPageLoad = async () => {
      if (localStorage.getItem('isWalletConnected') === 'true') {
        try {
          if (isMounted) setIsLoading(true);
          
          // Use a timeout to ensure MetaMask has time to initialize
          await new Promise(resolve => setTimeout(resolve, 500));
          
          // Only activate if component is still mounted
          if (isMounted) {
            await metaMask.activate();
            
            // After successful activation, create a new provider
            if (isMounted) {
              // Give a little time for the connection to establish
              await new Promise(resolve => setTimeout(resolve, 300));
              
              // Create provider using window.ethereum directly
              if (typeof window !== 'undefined' && window.ethereum) {
                try {
                  const provider = new ethers.BrowserProvider(window.ethereum as any);
                  setLibrary(provider);
                } catch (providerError) {
                  console.error('Error creating provider during auto-connect:', providerError);
                }
              }
            }
          }
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
      }}
    >
      {children}
    </Web3Context.Provider>
  );
};

// Custom hook to use the Web3 context
export const useWeb3 = () => useContext(Web3Context);
