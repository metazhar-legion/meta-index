import React, { useState, useEffect, useCallback } from 'react';
import { Box, Button, TextField, Typography, Paper, Grid, Divider, Alert } from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import eventBus, { EVENTS } from '../utils/eventBus';
import ERC20ABI from '../contracts/abis/ERC20.json';
import IndexFundVaultABI from '../contracts/abis/IndexFundVault.json';
import { CONTRACT_ADDRESSES } from '../contracts/addresses';

// Use the centralized contract addresses from the addresses.ts file
const ADDRESSES = {
  // USDC address from CONTRACT_ADDRESSES
  USDC: CONTRACT_ADDRESSES.USDC,
  // Vault address from CONTRACT_ADDRESSES
  VAULT: CONTRACT_ADDRESSES.VAULT,
};

// Only log addresses in development mode
if (process.env.NODE_ENV === 'development') {
  console.log('TestingTools - Contract addresses:', {
    USDC: ADDRESSES.USDC.slice(0, 6) + '...' + ADDRESSES.USDC.slice(-4),
    VAULT: ADDRESSES.VAULT.slice(0, 6) + '...' + ADDRESSES.VAULT.slice(-4)
  });
}

const TestingTools: React.FC = () => {
  const { account, provider, refreshProvider } = useWeb3();
  const [amount, setAmount] = useState<string>('1000');
  const [status, setStatus] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [usdcBalance, setUsdcBalance] = useState<string>('0');
  const [allowance, setAllowance] = useState<string>('0');
  const [vaultBalance, setVaultBalance] = useState<string>('0');
  const [vaultValue, setVaultValue] = useState<string>('0');
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  
  // Get signer when provider changes
  useEffect(() => {
    const getSigner = async () => {
      if (provider) {
        try {
          // Check if the provider is a BrowserProvider (which has getSigner)
          if ('getSigner' in provider && typeof provider.getSigner === 'function') {
            const newSigner = await (provider as ethers.BrowserProvider).getSigner();
            setSigner(newSigner);
          } else {
            console.log('Provider does not have getSigner method');
            setSigner(null);
          }
        } catch (error) {
          console.warn('Error getting signer:', error);
          setSigner(null);
        }
      } else {
        setSigner(null);
      }
    };
    
    getSigner();
  }, [provider]);

  // Format amounts for display (USDC has 6 decimals) with improved error handling
  const formatUSDC = useCallback((amount: bigint | string | number | null | undefined): string => {
    try {
      // Handle different input types
      if (amount === null || amount === undefined) {
        console.warn('Attempted to format null or undefined amount');
        return '0.0';
      }
      
      // Convert to BigInt if needed
      let bigintAmount: bigint;
      if (typeof amount === 'string') {
        bigintAmount = BigInt(amount);
      } else if (typeof amount === 'number') {
        bigintAmount = BigInt(Math.floor(amount));
      } else {
        bigintAmount = amount;
      }
      
      // Format with proper decimals
      return ethers.formatUnits(bigintAmount, 6);
    } catch (error) {
      console.error('Error formatting USDC amount:', error, 'Value was:', amount);
      return 'Error';
    }
  }, []);
  
  // Format ETH amounts for display (18 decimals) with improved error handling
  const formatEther = useCallback((amount: bigint | string | number | null | undefined): string => {
    try {
      // Handle different input types
      if (amount === null || amount === undefined) {
        console.warn('Attempted to format null or undefined amount');
        return '0.0';
      }
      
      // Convert to BigInt if needed
      let bigintAmount: bigint;
      if (typeof amount === 'string') {
        bigintAmount = BigInt(amount);
      } else if (typeof amount === 'number') {
        bigintAmount = BigInt(Math.floor(amount));
      } else {
        bigintAmount = amount;
      }
      
      // First convert to ETH units (divide by 10^18)
      const ethValue = ethers.formatEther(bigintAmount);
      // Then format to a reasonable number of decimals for display
      return Number(ethValue).toFixed(2);
    } catch (error) {
      console.error('Error formatting ETH amount:', error, 'Value was:', amount);
      return 'Error';
    }
  }, []);

  // Parse user input to USDC amount with 6 decimals
  const parseUSDC = (amount: string): bigint => {
    try {
      return ethers.parseUnits(amount, 6);
    } catch (error) {
      console.warn('Error parsing amount:', error);
      return 0n;
    }
  };

  // Helper function to load balances with a specific provider
  const loadBalancesWithProvider = async (currentProvider: ethers.Provider) => {
    setStatus('Loading balances...');
    
    try {
      // Validate inputs first
      if (!currentProvider) {
        throw new Error('Provider is not available');
      }
      
      if (!account) {
        throw new Error('Account is not available');
      }
      
      // Check if we're connected to the right network with timeout protection
      let network;
      try {
        network = await Promise.race([
          currentProvider.getNetwork(),
          new Promise<never>((_, reject) => 
            setTimeout(() => reject(new Error('Network check timed out')), 3000)
          )
        ]);
        // Only log in development mode
        if (process.env.NODE_ENV === 'development') {
          console.log('Network:', network.chainId.toString());
        }
      } catch (networkError) {
        console.error('Network connection error:', networkError instanceof Error ? networkError.message : String(networkError));
        throw new Error('Failed to connect to network');
      }
      
      // Get the latest block number to check blockchain state with timeout protection
      try {
        await Promise.race([
          currentProvider.getBlockNumber(),
          new Promise<never>((_, reject) => 
            setTimeout(() => reject(new Error('Block number request timed out')), 3000)
          )
        ]);
        // Block number check successful, but no need to log it
      } catch (blockError) {
        // Continue despite this error - it's not critical
        console.debug('Block number check failed, continuing anyway');
      }
      
      // Create contract instances - verify they're valid
      let usdcContract;
      let vaultContract;
      
      try {
        usdcContract = new ethers.Contract(ADDRESSES.USDC, ERC20ABI, currentProvider);
        vaultContract = new ethers.Contract(ADDRESSES.VAULT, IndexFundVaultABI, currentProvider);
        
        // Verify contract code exists at the address
        const code = await Promise.race([
          currentProvider.getCode(ADDRESSES.USDC),
          new Promise<never>((_, reject) => 
            setTimeout(() => reject(new Error('getCode request timed out')), 3000)
          )
        ]);
        
        if (code === '0x') {
          throw new Error('No contract code found at USDC address');
        }
      } catch (contractError) {
        const errorMsg = contractError instanceof Error ? contractError.message : String(contractError);
        console.error('Contract initialization error:', errorMsg);
        throw new Error('Failed to initialize contracts');
      }
      
      // Get USDC balance with timeout protection and improved error handling
      try {
        setStatus('Fetching USDC balance...');
        
        // First try with standard contract call
        const balancePromise = Promise.race([
          usdcContract.balanceOf(account),
          new Promise<never>((_, reject) => 
            setTimeout(() => reject(new Error('USDC balance request timed out')), 5000)
          )
        ]);
        
        let balance;
        try {
          balance = await balancePromise;
          // Success - no need to log raw balance
        } catch (initialBalanceError) {
          console.debug('Using fallback method for USDC balance');
          
          // If standard call fails, try with low-level call
          try {
            const iface = new ethers.Interface(['function balanceOf(address) view returns (uint256)']);
            const calldata = iface.encodeFunctionData('balanceOf', [account]);
            
            const rawResult = await currentProvider.call({
              to: ADDRESSES.USDC,
              data: calldata
            });
            
            if (rawResult && rawResult !== '0x') {
              const decodedResult = iface.decodeFunctionResult('balanceOf', rawResult);
              balance = decodedResult[0];
            } else {
              throw new Error('Empty result from low-level call');
            }
          } catch (lowLevelError) {
            console.error('USDC balance retrieval failed');
            throw lowLevelError; // Re-throw to be caught by outer catch
          }
        }
        
        // Validate balance is not null before using it
        if (balance === null || balance === undefined) {
          setUsdcBalance('Error');
        } else {
          // Ensure balance is treated as BigInt
          try {
            // Convert to BigInt if it's not already
            const bigintBalance = typeof balance === 'bigint' ? balance : BigInt(balance.toString());
            setUsdcBalance(formatUSDC(bigintBalance));
          } catch (conversionError) {
            console.error('Error converting USDC balance');
            setUsdcBalance('Error');
          }
        }
      } catch (balanceError) {
        console.error('USDC balance error:', balanceError instanceof Error ? balanceError.message : 'Unknown error');
        setUsdcBalance('Error');
      }
      
      // Get USDC allowance for vault with timeout protection and improved error handling
      try {
        setStatus('Fetching allowance...');
        
        // First try with standard contract call
        const allowancePromise = Promise.race([
          usdcContract.allowance(account, ADDRESSES.VAULT),
          new Promise<never>((_, reject) => 
            setTimeout(() => reject(new Error('USDC allowance request timed out')), 5000)
          )
        ]);
        
        let currentAllowance;
        try {
          currentAllowance = await allowancePromise;
          // Success - no need to log raw allowance
        } catch (initialAllowanceError) {
          // If standard call fails, try with low-level call
          try {
            const iface = new ethers.Interface(['function allowance(address,address) view returns (uint256)']);
            const calldata = iface.encodeFunctionData('allowance', [account, ADDRESSES.VAULT]);
            
            const rawResult = await currentProvider.call({
              to: ADDRESSES.USDC,
              data: calldata
            });
            
            if (rawResult && rawResult !== '0x') {
              const decodedResult = iface.decodeFunctionResult('allowance', rawResult);
              currentAllowance = decodedResult[0];
            } else {
              throw new Error('Empty result from low-level call');
            }
          } catch (lowLevelError) {
            console.error('Allowance retrieval failed');
            throw lowLevelError; // Re-throw to be caught by outer catch
          }
        }
        
        // Validate allowance is not null before using it
        if (currentAllowance === null || currentAllowance === undefined) {
          setAllowance('Error');
        } else {
          // Ensure allowance is treated as BigInt
          try {
            // Convert to BigInt if it's not already
            const bigintAllowance = typeof currentAllowance === 'bigint' ? currentAllowance : BigInt(currentAllowance.toString());
            setAllowance(formatUSDC(bigintAllowance));
          } catch (conversionError) {
            console.error('Error converting allowance value');
            setAllowance('Error');
          }
        }
      } catch (allowanceError) {
        console.error('Allowance error:', allowanceError instanceof Error ? allowanceError.message : 'Unknown error');
        setAllowance('Error');
      }
      
      // Get vault balance if available - with improved error handling
      try {
        setStatus('Fetching vault balance...');
        
        // Get vault balance with timeout protection
        let vaultBalance;
        try {
          const vaultBalancePromise = Promise.race([
            vaultContract.balanceOf(account),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Vault balance request timed out')), 5000)
            )
          ]);
          
          vaultBalance = await vaultBalancePromise;
        } catch (balanceError) {
          // If standard call fails, try with low-level call
          try {
            const iface = new ethers.Interface(['function balanceOf(address) view returns (uint256)']);
            const calldata = iface.encodeFunctionData('balanceOf', [account]);
            
            const rawResult = await currentProvider.call({
              to: ADDRESSES.VAULT,
              data: calldata
            });
            
            if (rawResult && rawResult !== '0x') {
              const decodedResult = iface.decodeFunctionResult('balanceOf', rawResult);
              vaultBalance = decodedResult[0];
            } else {
              throw new Error('Empty result from low-level call');
            }
          } catch (lowLevelError) {
            console.error('Vault balance retrieval failed');
            throw lowLevelError; // Re-throw to be caught by outer catch
          }
        }
        
        // Validate vault balance is not null before using it
        if (vaultBalance === null || vaultBalance === undefined) {
          setVaultBalance('Error');
        } else {
          // Ensure vault balance is treated as BigInt
          try {
            // Convert to BigInt if it's not already
            const bigintBalance = typeof vaultBalance === 'bigint' ? vaultBalance : BigInt(vaultBalance.toString());
            // Format with 6 decimals (not 18) to match the vault contract's implementation
            // and 2 decimal places for display
            console.log('TestingTools: Raw vault balance:', bigintBalance.toString());
            const formattedBalance = Number(ethers.formatUnits(bigintBalance, 6)).toFixed(2);
            console.log('TestingTools: Formatted vault balance:', formattedBalance);
            setVaultBalance(formattedBalance);
          } catch (conversionError) {
            console.error('Error converting vault balance');
            setVaultBalance('Error');
          }
        }
        
        // Get vault USDC value with timeout protection - using maxWithdraw and convertToAssets from ERC4626 standard
        let vaultValue;
        try {
          console.log('Requesting withdrawable amount for account:', account);
          
          // First get the maximum amount of shares that can be withdrawn
          const maxWithdrawPromise = Promise.race([
            vaultContract.maxRedeem(account),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Max withdraw request timed out')), 5000)
            )
          ]);
          
          const maxShares = await maxWithdrawPromise;
          // Then convert those shares to assets (USDC)
          if (maxShares && maxShares > 0n) {
            const assetsPromise = Promise.race([
              vaultContract.convertToAssets(maxShares),
              new Promise<never>((_, reject) => 
                setTimeout(() => reject(new Error('Convert to assets request timed out')), 5000)
              )
            ]);
            
            vaultValue = await assetsPromise;
          } else {
            // If no shares, value is 0
            vaultValue = 0n;
          }
        } catch (valueError) {
          // If the first approach fails, try with maxWithdraw directly
          try {
            const maxWithdrawPromise = Promise.race([
              vaultContract.maxWithdraw(account),
              new Promise<never>((_, reject) => 
                setTimeout(() => reject(new Error('Max withdraw direct request timed out')), 5000)
              )
            ]);
            
            vaultValue = await maxWithdrawPromise;
          } catch (alternativeError) {
            console.error('Failed to calculate withdrawable value');
            throw alternativeError; // Re-throw to be caught by outer catch
          }
        }
        
        // Validate vault value is not null before using it
        if (vaultValue === null || vaultValue === undefined) {
          setVaultValue('Error');
        } else {
          // Ensure vault value is treated as BigInt
          try {
            // Convert to BigInt if it's not already
            const bigintValue = typeof vaultValue === 'bigint' ? vaultValue : BigInt(vaultValue.toString());
            console.log('TestingTools: Raw vault value:', bigintValue.toString());
            // Format with 6 decimals for USDC
            const formattedValue = Number(ethers.formatUnits(bigintValue, 6)).toFixed(2);
            console.log('TestingTools: Formatted vault value:', formattedValue);
            setVaultValue(formattedValue);
          } catch (conversionError) {
            console.error('Error converting vault value');
            setVaultValue('Error');
          }
        }
        
        // Clear status when done
        setStatus('Balances loaded');
        setTimeout(() => setStatus(''), 2000); // Clear status after 2 seconds
      } catch (vaultError) {
        console.error('Vault data error:', vaultError instanceof Error ? vaultError.message : 'Unknown error');
        setVaultBalance('Error');
        setVaultValue('Error');
        setStatus('Error loading data');
      }
    } catch (error) {
      // Set all values to error state
      setUsdcBalance('Error');
      setAllowance('Error');
      setVaultBalance('Error');
      setVaultValue('Error');
      
      // Log a concise error message
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(`Balance loading failed: ${errorMessage}`);
      
      // Set error message for UI
      setError('Failed to load balances: ' + errorMessage);
      setStatus('Error loading data');
      // Don't rethrow - handle it here completely
    }
  };

  // Track last load time to prevent excessive refreshes
  const [lastLoadTime, setLastLoadTime] = useState<number>(0);
  
  // Load USDC balance and allowance with enhanced error handling and recovery
  const loadBalances = useCallback(async () => {
    if (!account || !provider) {
      setError('Please connect your wallet first');
      return;
    }
    
    // Prevent loading more than once every 3 seconds
    const now = Date.now();
    const timeSinceLastLoad = now - lastLoadTime;
    if (timeSinceLastLoad < 3000) {
      console.log(`Skipping balance load, last load was ${timeSinceLastLoad}ms ago`);
      return;
    }
    
    // Update last load time
    setLastLoadTime(now);

    try {
      setStatus('Loading balances...');
      console.log('Loading balances for account:', account);
      
      // Track which provider succeeded for debugging purposes
      let successProvider = '';
      
      try {
        // Try with current provider first
        if (provider) {
          await loadBalancesWithProvider(provider);
          successProvider = 'current';
        }
        setStatus('Balances loaded successfully');
        setError(null);
        
        // Emit event to notify other components to refresh vault stats
        eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
      } catch (initialError) {
        console.error('Error with initial provider, trying fresh provider:', initialError);
        
        // Check for specific error types to provide better user feedback
        const errorStr = String(initialError);
        const isNetworkError = errorStr.includes('network') || errorStr.includes('connection') || 
                              errorStr.includes('timeout') || errorStr.includes('unavailable');
        const isBlockchainSyncError = errorStr.includes('BlockOutOfRange') || 
                                     errorStr.includes('block height') || 
                                     errorStr.includes('sync');
        
        // If that fails, try with a fresh provider
        try {
          if (window.ethereum) {
            console.log('Creating fresh provider from window.ethereum');
            const freshProvider = new ethers.BrowserProvider(window.ethereum as any);
            await loadBalancesWithProvider(freshProvider);
            successProvider = 'fresh';
            setStatus('Balances loaded with fresh provider');
            setError(null);
            
            // Emit event to notify other components to refresh vault stats
            eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
          } else {
            throw new Error('No window.ethereum available');
          }
        } catch (freshProviderError) {
          console.error('Error with fresh provider, trying Web3Context refreshProvider:', freshProviderError);
          
          // If that also fails, try with the Web3Context refreshProvider
          try {
            const refreshedProvider = await refreshProvider();
            if (refreshedProvider) {
              await loadBalancesWithProvider(refreshedProvider);
              successProvider = 'refreshed';
              setStatus('Balances loaded with refreshed provider');
              setError(null);
              
              // Emit event to notify other components to refresh vault stats
              eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
            } else {
              throw new Error('Failed to get refreshed provider');
            }
          } catch (finalError) {
            // If all attempts fail, show a specific error message
            console.error('All provider attempts failed:', finalError);
            
            const finalErrorStr = String(finalError);
            
            // Provide more specific error messages based on error type
            if (isBlockchainSyncError || finalErrorStr.includes('BlockOutOfRange') || finalErrorStr.includes('block height')) {
              setError('Blockchain sync error. Please wait a moment and try again.');
            } else if (isNetworkError || finalErrorStr.includes('network') || finalErrorStr.includes('connection')) {
              setError('Network connection error. Please check your internet connection and try again.');
            } else if (finalErrorStr.includes('user rejected') || finalErrorStr.includes('User denied')) {
              setError('Request was rejected. Please approve the connection request in your wallet.');
            } else {
              setError('Failed to load balances: ' + (finalError instanceof Error ? finalError.message : finalErrorStr));
            }
            setStatus('');
          }
        }
      }
      
      // Log which provider succeeded for debugging
      if (successProvider) {
        console.log(`Successfully loaded balances using ${successProvider} provider`);
      }
      
    } catch (error) {
      console.error('Unexpected error in loadBalances:', error);
      setError('Unexpected error loading balances. Please try again.');
      setStatus('');
    }
  }, [account, provider, refreshProvider, formatUSDC, loadBalancesWithProvider, lastLoadTime]);

  // Mint USDC tokens (this is a test function that only works on local testnet)
  const mintUSDC = async () => {
    if (!account || !signer) {
      setError('Please connect your wallet first');
      return;
    }

    try {
      setStatus('Minting USDC...');
      setError(null);
      
      const usdcContract = new ethers.Contract(ADDRESSES.USDC, ERC20ABI, signer);
      
      // Call the mint function (this only works if the contract has a mint function accessible to the user)
      // In a real ERC20, this would not be available, but for testing it's helpful
      const tx = await usdcContract.mint(account, parseUSDC(amount));
      
      setStatus('Waiting for transaction confirmation...');
      await tx.wait();
      
      setStatus(`Successfully minted ${amount} USDC`);
      
      // Refresh balances
      await loadBalances();
      
      // Emit event to notify other components that a transaction was completed
      eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
    } catch (error) {
      console.warn('Error minting USDC:', error);
      setError('Failed to mint USDC. Make sure you have the right permissions.');
      setStatus('');
    }
  };

  // Approve USDC for the vault
  const approveUSDC = async () => {
    if (!account || !signer) {
      setError('Please connect your wallet first');
      return;
    }

    try {
      setStatus('Approving USDC...');
      setError(null);
      
      const usdcContract = new ethers.Contract(ADDRESSES.USDC, ERC20ABI, signer);
      
      // Approve the vault to spend USDC
      const tx = await usdcContract.approve(ADDRESSES.VAULT, parseUSDC(amount));
      
      setStatus('Waiting for transaction confirmation...');
      await tx.wait();
      
      setStatus(`Successfully approved ${amount} USDC for the vault`);
      
      // Refresh allowance
      await loadBalances();
      
      // Emit event to notify other components that a transaction was completed
      eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
    } catch (error) {
      console.warn('Error approving USDC:', error);
      setError('Failed to approve USDC');
      setStatus('');
    }
  };

  // Deposit USDC to the vault
  const depositToVault = async () => {
    if (!account || !signer) {
      setError('Please connect your wallet first');
      return;
    }

    try {
      console.log('TestingTools: Starting deposit process');
      setStatus('Depositing to vault...');
      setError(null);
      
      const vaultContract = new ethers.Contract(ADDRESSES.VAULT, IndexFundVaultABI, signer);
      console.log('TestingTools: Vault contract initialized');
      
      // Deposit USDC to the vault
      console.log(`TestingTools: Depositing ${amount} USDC to vault`);
      const parsedAmount = parseUSDC(amount);
      console.log('TestingTools: Parsed amount:', parsedAmount.toString());
      
      const tx = await vaultContract.deposit(parsedAmount, account);
      console.log('TestingTools: Deposit transaction submitted:', tx.hash);
      
      setStatus('Waiting for transaction confirmation...');
      const receipt = await tx.wait();
      console.log('TestingTools: Transaction confirmed, receipt:', receipt.hash);
      
      setStatus(`Successfully deposited ${amount} USDC to the vault`);
      
      // Refresh balances with a slight delay to ensure blockchain state is updated
      console.log('TestingTools: Refreshing balances after deposit');
      setTimeout(async () => {
        await loadBalances();
        console.log('TestingTools: Balances refreshed');
      }, 1000);
      
      // Emit event to notify other components that a transaction was completed
      console.log('TestingTools: Emitting VAULT_TRANSACTION_COMPLETED event');
      eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
      console.log('TestingTools: Event emitted');
    } catch (error) {
      console.warn('Error depositing to vault:', error);
      setError('Failed to deposit to vault. Make sure you have approved enough USDC.');
      setStatus('');
    }
  };

  // Withdraw from the vault
  const withdrawFromVault = async () => {
    if (!account || !signer) {
      setError('Please connect your wallet first');
      return;
    }

    try {
      setStatus('Withdrawing from vault...');
      setError(null);
      
      const vaultContract = new ethers.Contract(ADDRESSES.VAULT, IndexFundVaultABI, signer);
      
      // Get shares balance
      const sharesBalance = await vaultContract.balanceOf(account);
      
      if (sharesBalance === 0n) {
        setError('You don\'t have any shares to withdraw');
        setStatus('');
        return;
      }
      
      // Display formatted share balance for better UX
      // Use formatUnits with 6 decimals to match the vault contract's implementation
      const formattedShares = Number(ethers.formatUnits(sharesBalance, 6)).toFixed(2);
      console.log(`TestingTools: Withdrawing ${formattedShares} shares`);
      
      // Calculate shares to withdraw based on amount
      // For simplicity, we'll withdraw all shares
      const tx = await vaultContract.redeem(sharesBalance, account, account);
      
      setStatus('Waiting for transaction confirmation...');
      await tx.wait();
      
      setStatus(`Successfully withdrew from the vault`);
      
      // Refresh balances
      await loadBalances();
      
      // Emit event to notify other components that a transaction was completed
      eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
    } catch (error) {
      console.warn('Error withdrawing from vault:', error);
      setError('Failed to withdraw from vault');
      setStatus('');
    }
  };

  // Reset connection and reload balances
  const resetConnection = useCallback(async () => {
    setStatus('Resetting connection...');
    setError(null);
    
    try {
      // First try using the Web3Context refreshProvider
      console.log('Attempting to refresh provider via Web3Context...');
      
      // Add a timeout to the refreshProvider call
      const freshProvider = await Promise.race([
        refreshProvider(),
        new Promise<null>((_, reject) => 
          setTimeout(() => reject(new Error('Provider refresh timed out')), 5000)
        )
      ]);
      
      if (freshProvider) {
        try {
          // Force a network check with timeout
          const network = await Promise.race([
            freshProvider.getNetwork(),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Network check timed out')), 3000)
            )
          ]);
          console.log('Reconnected to network:', network.chainId.toString());
          
          // Get a fresh block number with timeout
          const blockNumber = await Promise.race([
            freshProvider.getBlockNumber(),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Block number request timed out')), 3000)
            )
          ]);
          console.log('Current block number after refresh:', blockNumber);
          
          setStatus('Connection refreshed successfully');
          
          // Wait a moment before loading balances
          await new Promise(resolve => setTimeout(resolve, 1000));
          await loadBalances();
          
          // Emit vault transaction event to update vault stats
          eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
          return;
        } catch (networkError) {
          console.error('Error checking network after provider refresh:', networkError);
          // Continue to the next method if this fails
        }
      }
      
      // If Web3Context refreshProvider fails, try with window.ethereum directly
      if (window.ethereum) {
        console.log('Refreshing connection with window.ethereum directly...');
        
        try {
          // Request accounts again to force a refresh with timeout
          await Promise.race([
            window.ethereum.request({ method: 'eth_requestAccounts' }),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Request accounts timed out')), 5000)
            )
          ]);
          
          // Create a fresh provider
          const manualProvider = new ethers.BrowserProvider(window.ethereum);
          
          // Force a network check with timeout
          const network = await Promise.race([
            manualProvider.getNetwork(),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Network check timed out')), 3000)
            )
          ]);
          console.log('Reconnected to network:', network.chainId.toString());
          
          // Get a fresh block number with timeout
          const blockNumber = await Promise.race([
            manualProvider.getBlockNumber(),
            new Promise<never>((_, reject) => 
              setTimeout(() => reject(new Error('Block number request timed out')), 3000)
            )
          ]);
          console.log('Current block number after reset:', blockNumber);
          
          // Emit an event to notify other components to refresh their data
          eventBus.emit(EVENTS.WALLET_CONNECTED, { account, provider: manualProvider });
          
          setStatus('Connection reset successfully via window.ethereum');
          
          // Wait a moment before loading balances
          await new Promise(resolve => setTimeout(resolve, 1000));
          
          // Try to load balances with the new provider directly
          try {
            await loadBalancesWithProvider(manualProvider);
            setStatus('Balances loaded successfully after reset');
            setError(null);
            
            // Emit vault transaction event to update vault stats
            eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
          } catch (balanceError) {
            console.error('Error loading balances after reset:', balanceError);
            setStatus('Connection reset, but balances failed to load');
            setError('Failed to load balances after reset. Try again in a moment.');
          }
        } catch (manualError) {
          console.error('Error with manual provider refresh:', manualError);
          throw manualError;
        }
      } else {
        throw new Error('No window.ethereum available');
      }
    } catch (error) {
      console.error('Error resetting connection:', error);
      setError('Failed to reset connection. Please refresh the page manually.');
      setStatus('');
    }
  }, [account, refreshProvider, loadBalances]);
  
  // Load balances when component mounts or account changes
  React.useEffect(() => {
    if (account && provider) {
      loadBalances();
    }
  }, [account, provider, loadBalances]);

  if (!account) {
    return (
      <Paper sx={{ p: 3, mt: 3 }}>
        <Typography variant="h6">Testing Tools</Typography>
        <Alert severity="info" sx={{ mt: 2 }}>Please connect your wallet to use the testing tools</Alert>
      </Paper>
    );
  }

  return (
    <Paper sx={{ p: 3, mt: 3 }}>
      <Typography variant="h6">Testing Dev Tools</Typography>
      <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 2 }}>
        These tools are for testing purposes only
      </Typography>
      
      <Divider sx={{ my: 2 }} />
      
      <Grid container spacing={2} alignItems="center">
        <Grid item xs={12} sm={6}>
          <TextField
            label="Amount (USDC)"
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            fullWidth
            InputProps={{
              inputProps: { min: 0 }
            }}
          />
        </Grid>
        
        <Grid item xs={12} sm={6}>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
              <Typography variant="body2">
                USDC Balance: {usdcBalance}
              </Typography>
              <Typography variant="body2">
                Allowance: {allowance}
              </Typography>
            </Box>
            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
              <Typography variant="body2" fontWeight="bold">
                Vault Balance: {vaultBalance} shares
              </Typography>
              <Typography variant="body2" fontWeight="bold">
                Value: {vaultValue} USDC
              </Typography>
            </Box>
          </Box>
        </Grid>
      </Grid>
      
      <Box sx={{ mt: 2, display: 'flex', flexWrap: 'wrap', gap: 2 }}>
        <Button variant="contained" color="primary" onClick={mintUSDC}>
          Mint USDC
        </Button>
        <Button variant="contained" color="secondary" onClick={approveUSDC}>
          Approve USDC
        </Button>
        <Button variant="contained" color="success" onClick={depositToVault}>
          Deposit to Vault
        </Button>
        <Button variant="contained" color="warning" onClick={withdrawFromVault}>
          Withdraw from Vault
        </Button>
        <Button variant="outlined" onClick={resetConnection}>
          Reset & Refresh Balances
        </Button>
        <Button 
          variant="contained" 
          color="error" 
          onClick={async () => {
            try {
              setStatus('Force reconnecting...');
              setError(null);
              
              // Store the current account for later comparison
              const previousAccount = account;
              
              // Step 1: Try to disconnect first if possible
              if (window.ethereum && window.ethereum.isConnected && typeof window.ethereum.isConnected === 'function') {
                try {
                  // Some wallets support this method
                  await window.ethereum.request({ method: 'wallet_disconnect' });
                  console.log('Wallet disconnected successfully');
                } catch (disconnectError) {
                  console.log('Wallet disconnect not supported, continuing:', disconnectError);
                }
              }
              
              // Step 2: Wait a moment to allow wallet state to update
              await new Promise(resolve => setTimeout(resolve, 800));
              
              // Step 3: Force a fresh connection with timeout protection
              if (window.ethereum) {
                try {
                  // Request accounts with timeout protection
                  const requestAccountsPromise = Promise.race([
                    window.ethereum.request({ method: 'eth_requestAccounts' }),
                    new Promise((_, reject) => setTimeout(() => reject(new Error('Request accounts timed out')), 10000))
                  ]);
                  
                  // Wait for accounts
                  const accounts = await requestAccountsPromise as string[];
                  console.log('Reconnected accounts:', accounts);
                  
                  if (!accounts || accounts.length === 0) {
                    throw new Error('No accounts returned after reconnection');
                  }
                  
                  // Create a fresh provider
                  const manualProvider = new ethers.BrowserProvider(window.ethereum);
                  
                  // Verify the provider works by checking network and block number
                  const network = await manualProvider.getNetwork();
                  console.log('Network after reconnect:', network.chainId.toString());
                  
                  const blockNumber = await manualProvider.getBlockNumber();
                  console.log('Block number after reconnect:', blockNumber);
                  
                  // Emit an event to notify other components
                  eventBus.emit(EVENTS.WALLET_CONNECTED, { account: accounts[0], provider: manualProvider });
                  
                  setStatus('Force reconnect successful');
                  
                  // Step 4: Wait a moment before loading balances
                  await new Promise(resolve => setTimeout(resolve, 1000));
                  
                  // Step 5: Try to load balances with the new provider
                  try {
                    await loadBalancesWithProvider(manualProvider);
                    console.log('Balances loaded successfully after reconnect');
                  } catch (balanceError) {
                    console.warn('Could not load balances after reconnect:', balanceError);
                    // Don't fail the whole operation if just balance loading fails
                  }
                  
                  // Step 6: Check if account changed and notify user if needed
                  if (accounts[0] && previousAccount && accounts[0].toLowerCase() !== previousAccount.toLowerCase()) {
                    setStatus(`Force reconnect successful - Account changed from ${previousAccount} to ${accounts[0]}`);
                  }
                } catch (connectionError) {
                  console.error('Error during reconnection process:', connectionError);
                  throw connectionError; // Re-throw to be caught by outer catch
                }
              } else {
                throw new Error('No window.ethereum available');
              }
            } catch (error) {
              console.error('Force reconnect failed:', error);
              
              // Provide more specific error messages based on error type
              const errorStr = String(error);
              if (errorStr.includes('user rejected') || errorStr.includes('User denied')) {
                setError('Reconnection was rejected. Please approve the connection request in your wallet.');
              } else if (errorStr.includes('timeout')) {
                setError('Reconnection timed out. Please try again or refresh the page.');
              } else if (errorStr.includes('network') || errorStr.includes('connection')) {
                setError('Network connection error. Please check your internet connection and try again.');
              } else {
                setError('Force reconnect failed: ' + (error instanceof Error ? error.message : errorStr));
              }
              setStatus('');
            }
          }}
        >
          Force Reconnect
        </Button>
      </Box>
      
      {status && (
        <Alert severity="info" sx={{ mt: 2 }}>
          {status}
        </Alert>
      )}
      
      {error && (
        <Alert severity="error" sx={{ mt: 2 }}>
          {error}
        </Alert>
      )}
    </Paper>
  );
};

export default TestingTools;
