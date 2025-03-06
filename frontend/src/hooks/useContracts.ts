import { useEffect, useState } from 'react';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import {
  IndexFundVaultInterface,
  IndexRegistryInterface,
  IndexFundVaultABI,
  IndexRegistryABI,
  ERC20ABI,
  Token
} from '../contracts/contractTypes';

// Contract addresses - these should be updated after deployment
const CONTRACT_ADDRESSES = {
  // Replace with actual deployed contract addresses
  VAULT: '0x0000000000000000000000000000000000000000',
  REGISTRY: '0x0000000000000000000000000000000000000000',
};

export const useContracts = () => {
  const { provider, account, isActive } = useWeb3();
  const [vaultContract, setVaultContract] = useState<IndexFundVaultInterface | null>(null);
  const [registryContract, setRegistryContract] = useState<IndexRegistryInterface | null>(null);
  const [indexTokens, setIndexTokens] = useState<Token[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize contracts when provider is available
  useEffect(() => {
    if (provider && isActive) {
      try {
        const signer = provider.getSigner();
        
        // Initialize vault contract
        const vault = new ethers.Contract(
          CONTRACT_ADDRESSES.VAULT,
          IndexFundVaultABI,
          signer
        ) as unknown as IndexFundVaultInterface;
        
        // Initialize registry contract
        const registry = new ethers.Contract(
          CONTRACT_ADDRESSES.REGISTRY,
          IndexRegistryABI,
          signer
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
            const tokenContract = new ethers.Contract(address, ERC20ABI, provider);
            const [symbol, decimals] = await Promise.all([
              tokenContract.symbol(),
              tokenContract.decimals(),
            ]);
            
            return {
              address,
              symbol,
              decimals,
              weight: ethers.formatUnits(weights[index], 18),
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
    if (!tokenContract || !account) return false;
    
    try {
      const signer = provider?.getSigner();
      const connectedContract = tokenContract.connect(signer);
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
