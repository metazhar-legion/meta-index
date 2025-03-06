import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
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
  const { useAccount, useChainId, useIsActive, useProvider } = metaMaskHooks;
  const account = useAccount();
  const chainId = useChainId();
  const isActive = useIsActive();
  const rawProvider = useProvider();
  // Use the provider directly if it's available
  const library = rawProvider ? new ethers.BrowserProvider(rawProvider as any) : null;
  const [isLoading, setIsLoading] = useState(false);
  const [userRole, setUserRole] = useState<UserRole>(UserRole.INVESTOR);

  // Connect to wallet
  const connect = async () => {
    setIsLoading(true);
    try {
      await metaMask.activate();
      localStorage.setItem('isWalletConnected', 'true');
    } catch (error) {
      console.error('Error connecting to wallet:', error);
    } finally {
      setIsLoading(false);
    }
  };

  // Disconnect wallet
  const disconnect = () => {
    try {
      metaMask.resetState();
      localStorage.removeItem('isWalletConnected');
    } catch (error) {
      console.error('Error disconnecting wallet:', error);
    }
  };

  // Auto-connect if previously connected
  useEffect(() => {
    const connectWalletOnPageLoad = async () => {
      if (localStorage.getItem('isWalletConnected') === 'true') {
        try {
          await metaMask.activate();
        } catch (error) {
          console.error('Error auto-connecting to wallet:', error);
        }
      }
    };
    connectWalletOnPageLoad();
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
