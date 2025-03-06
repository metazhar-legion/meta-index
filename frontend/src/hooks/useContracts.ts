import { useEffect, useState } from 'react';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
// Provider adapters are no longer needed
import {
  IndexFundVaultInterface,
  IndexRegistryInterface,
  IndexFundVaultABI,
  IndexRegistryABI,
  ERC20ABI,
  Token
} from '../contracts/contractTypes';

import { CONTRACT_ADDRESSES } from '../contracts/addresses';

export const useContracts = () => {
  const { provider, isActive } = useWeb3();
  const [vaultContract, setVaultContract] = useState<IndexFundVaultInterface | null>(null);
  const [registryContract, setRegistryContract] = useState<IndexRegistryInterface | null>(null);
  const [indexTokens, setIndexTokens] = useState<Token[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize contracts when provider is available
  useEffect(() => {
    if (provider && isActive) {
      try {
        // Use the provider directly as it's already an ethers v6 BrowserProvider
        if (!provider) return;
        
        // Initialize vault contract with provider first
        const vault = new ethers.Contract(
          CONTRACT_ADDRESSES.VAULT,
          IndexFundVaultABI,
          provider
        ) as unknown as IndexFundVaultInterface;
        
        // Initialize registry contract with provider first
        const registry = new ethers.Contract(
          CONTRACT_ADDRESSES.REGISTRY,
          IndexRegistryABI,
          provider
        ) as unknown as IndexRegistryInterface;
        
        setVaultContract(vault);
        setRegistryContract(registry);
        setError(null);
      } catch (err) {
        console.error('Error initializing contracts:', err);
        setError('Failed to initialize contracts');
      }
    } else {
      setVaultContract(null);
      setRegistryContract(null);
    }
  }, [provider, isActive]);

  // Load index tokens when registry contract is available
  useEffect(() => {
    const loadIndexTokens = async () => {
      if (registryContract && provider) {
        setIsLoading(true);
        try {
          // Get tokens and weights from registry
          const [tokenAddresses, weights] = await registryContract.getTokensWithWeights();
          
          // Create token contracts and fetch metadata
          const tokenPromises = tokenAddresses.map(async (address, index) => {
            if (!provider) throw new Error('Provider not available');
            const tokenContract = new ethers.Contract(address, ERC20ABI, provider);
            const [symbol, decimals] = await Promise.all([
              tokenContract.symbol(),
              tokenContract.decimals(),
            ]);
            
            return {
              address,
              symbol,
              decimals,
              weight: parseFloat(ethers.formatUnits(weights[index], 18)),
            };
          });
          
          const tokens = await Promise.all(tokenPromises);
          setIndexTokens(tokens);
          setError(null);
        } catch (err) {
          console.error('Error loading index tokens:', err);
          setError('Failed to load index tokens');
        } finally {
          setIsLoading(false);
        }
      }
    };
    
    loadIndexTokens();
  }, [registryContract, provider]);

  return {
    vaultContract,
    registryContract,
    indexTokens,
    isLoading,
    error,
  };
};

// Hook for ERC20 token interactions
export const useERC20 = (tokenAddress: string) => {
  const { provider, account } = useWeb3();
  const [tokenContract, setTokenContract] = useState<ethers.Contract | null>(null);
  const [tokenBalance, setTokenBalance] = useState<string>('0');
  const [tokenSymbol, setTokenSymbol] = useState<string>('');
  const [tokenDecimals, setTokenDecimals] = useState<number>(18);
  const [isLoading, setIsLoading] = useState(false);

  // Initialize token contract
  useEffect(() => {
    if (provider && tokenAddress && tokenAddress !== ethers.ZeroAddress) {
      const contract = new ethers.Contract(tokenAddress, ERC20ABI, provider);
      setTokenContract(contract);
      
      // Load token metadata
      const loadTokenMetadata = async () => {
        try {
          const [symbol, decimals] = await Promise.all([
            contract.symbol(),
            contract.decimals(),
          ]);
          setTokenSymbol(symbol);
          setTokenDecimals(decimals);
        } catch (err) {
          console.error('Error loading token metadata:', err);
        }
      };
      
      loadTokenMetadata();
    } else {
      setTokenContract(null);
    }
  }, [provider, tokenAddress]);

  // Load token balance
  useEffect(() => {
    const loadBalance = async () => {
      if (tokenContract && account) {
        setIsLoading(true);
        try {
          const balance = await tokenContract.balanceOf(account);
          setTokenBalance(ethers.formatUnits(balance, tokenDecimals));
        } catch (err) {
          console.error('Error loading token balance:', err);
        } finally {
          setIsLoading(false);
        }
      }
    };
    
    loadBalance();
    
    // Set up event listener for balance changes
    if (tokenContract && account) {
      const filter = tokenContract.filters.Transfer(account, null);
      const fromFilter = tokenContract.filters.Transfer(null, account);
      
      tokenContract.on(filter, loadBalance);
      tokenContract.on(fromFilter, loadBalance);
      
      return () => {
        tokenContract.off(filter, loadBalance);
        tokenContract.off(fromFilter, loadBalance);
      };
    }
  }, [tokenContract, account, tokenDecimals]);

  // Approve spending of tokens
  const approveTokens = async (spender: string, amount: string): Promise<boolean> => {
    if (!tokenContract) return false;
    
    try {
      if (!provider) return false;
      const signer = await provider.getSigner();
      if (!signer) return false;
      
      // Create a new contract instance with the signer
      const erc20Interface = new ethers.Interface(ERC20ABI);
      const tokenAddress = await tokenContract.getAddress();
      const connectedContract = new ethers.Contract(tokenAddress, erc20Interface, signer);
      const amountInWei = ethers.parseUnits(amount, tokenDecimals);
      
      const tx = await connectedContract.approve(spender, amountInWei);
      await tx.wait();
      return true;
    } catch (err) {
      console.error('Error approving tokens:', err);
      return false;
    }
  };

  return {
    tokenContract,
    tokenBalance,
    tokenSymbol,
    tokenDecimals,
    approveTokens,
    isLoading,
  };
};
