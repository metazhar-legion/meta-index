import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { ethers } from 'ethers';
import { BrowserProvider } from 'ethers';
import { InjectedConnector } from '@web3-react/injected-connector';
import { useWeb3React } from '@web3-react/core';

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
  provider: BrowserProvider | null;
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

// Supported chains
export const injected = new InjectedConnector({
  supportedChainIds: [1, 3, 4, 5, 42, 31337], // Mainnet, Ropsten, Rinkeby, Goerli, Kovan, Localhost
});

interface Web3ProviderProps {
  children: ReactNode;
}

export const Web3ContextProvider: React.FC<Web3ProviderProps> = ({ children }) => {
  const { activate, deactivate, account, chainId, active, library } = useWeb3React<BrowserProvider>();
  const [isLoading, setIsLoading] = useState(false);
  const [userRole, setUserRole] = useState<UserRole>(UserRole.INVESTOR);

  // Connect to wallet
  const connect = async () => {
    setIsLoading(true);
    try {
      await activate(injected);
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
      deactivate();
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
          await activate(injected);
        } catch (error) {
          console.error('Error auto-connecting to wallet:', error);
        }
      }
    };
    connectWalletOnPageLoad();
  }, [activate]);

  return (
    <Web3Context.Provider
      value={{
        account,
        chainId,
        connect,
        disconnect,
        isActive: active,
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
