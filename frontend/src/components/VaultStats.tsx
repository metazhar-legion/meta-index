import React, { useState, useEffect, useCallback } from 'react';
import { Box, Card, CardContent, Typography, Grid, Skeleton, Divider, Tooltip } from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import eventBus, { EVENTS } from '../utils/eventBus';
import { useContracts } from '../hooks/useContracts';
import { toBigInt } from '../contracts/contractTypes';

const VaultStats: React.FC = () => {
  const { vaultContract, isLoading: contractsLoading } = useContracts();
  const { account, provider, refreshProvider } = useWeb3();
  const [stats, setStats] = useState({
    totalAssets: '0',
    totalShares: '0',
    userShares: '0',
    userAssets: '0',
    sharePrice: '0',
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const MAX_RETRIES = 3;

  // Helper function to check if an error is a BlockOutOfRangeError
  const isBlockOutOfRangeError = useCallback((error: any): boolean => {
    if (!error) return false;
    
    // Handle different error formats
    const errorMessage = typeof error === 'string' 
      ? error 
      : error.message || '';
      
    // Check for nested error data (common in RPC errors)
    const errorData = error.data?.message || '';
    const nestedError = error.error?.message || '';
    
    return errorMessage.includes('BlockOutOfRange') || 
           errorData.includes('BlockOutOfRange') ||
           nestedError.includes('BlockOutOfRange') ||
           errorMessage.includes('block height') ||
           errorData.includes('block height') ||
           nestedError.includes('block height');
  }, []);

  // Helper function to convert various formats to BigInt
  // Define this outside of the component to avoid recreation on every render
  const convertToBigInt = (value: any): bigint => {
    if (typeof value === 'bigint') return value;
    if (typeof value === 'number') return BigInt(value);
    if (typeof value === 'string') {
      if (value.startsWith('0x')) return BigInt(value);
      return BigInt(value);
    }
    if (Array.isArray(value) && value.length > 0) {
      return convertToBigInt(value[0]);
    }
    return BigInt(0);
  };

  // Memoize the loadVaultStats function to prevent recreation on every render
  const loadVaultStats = useCallback(async () => {
    if (!vaultContract || !provider || !account) {
      return;
    }

    setLoading(true);
    setError(null);
    
    try {
      // Get vault contract address
      const vaultAddress = await vaultContract.target;
      
      // Create a minimal interface with just the methods we need
      const vaultInterface = new ethers.Interface([
        "function totalAssets() view returns (uint256)",
        "function totalSupply() view returns (uint256)",
        "function balanceOf(address) view returns (uint256)"
      ]);
      
      // Initialize values
      let totalAssets = BigInt(0);
      let totalSupply = BigInt(0);
      let userShares = BigInt(0);
      
      // Define fetchContractData inside loadVaultStats but don't recreate it on every render
      const fetchContractData = async (methodName: string, args: any[] = []) => {
        try {
          // @ts-ignore - Dynamic method call
          const rawResult = await vaultContract[methodName](...args);
          
          // Handle different return types
          if (typeof rawResult === 'bigint') {
            return rawResult;
          } else if (typeof rawResult === 'object' && rawResult !== null) {
            // Handle array-like or object returns from ethers v6
            if (Array.isArray(rawResult)) {
              return convertToBigInt(rawResult[0]);
            } else if ('value' in rawResult) {
              return convertToBigInt(rawResult.value);
            } else if ('_hex' in rawResult) {
              return convertToBigInt(rawResult._hex);
            } else {
              // Try to convert the first property if it exists
              const firstProp = Object.values(rawResult)[0];
              return convertToBigInt(firstProp);
            }
          } else {
            return convertToBigInt(rawResult);
          }
        } catch (e) {
          if (isBlockOutOfRangeError(e)) {
            throw e; // Re-throw to be caught by the outer try-catch for refresh handling
          }
          throw e;
        }
      };
      
      // Fetch all required data
      totalAssets = await fetchContractData('totalAssets');
      totalSupply = await fetchContractData('totalSupply');
      userShares = await fetchContractData('balanceOf', [account]);
      
      // Reset retry count on success
      setRetryCount(0);
      
      // Calculate derived values
      
      // Calculate derived values
      let userAssets = BigInt(0);
      let sharePrice = BigInt(0);
      
      if (totalSupply > BigInt(0)) {
        // Calculate user assets based on their share of the pool
        if (userShares > BigInt(0)) {
          userAssets = (userShares * totalAssets) / totalSupply;
          console.log('VaultStats: Calculated userAssets:', userAssets.toString());
        }
        
        // We'll calculate the share price in JavaScript after converting the BigInts
        // This is more precise than doing BigInt division which truncates
        sharePrice = BigInt(0); // This will be ignored, we'll calculate it in JS
      }
      
      // Update state with the fetched and calculated values
      // IMPORTANT: We need to use formatUnits with the correct decimals
      // USDC has 6 decimals, ERC20 shares have 18 decimals
      
      // Calculate the actual values with proper decimal handling
      // USDC has 6 decimals, but the vault contract uses 18 decimals for shares
      const formattedTotalAssets = Number(ethers.formatUnits(totalAssets, 6));
      
      // For shares, we need to check the contract's implementation
      // The issue might be that the contract is using a different decimal place for shares
      // Let's try using 6 decimals for shares as well, since that's what the contract might be using
      const formattedTotalShares = Number(ethers.formatUnits(totalSupply, 6));
      const formattedUserShares = Number(ethers.formatUnits(userShares, 6));
      
      // Calculate user assets in USDC (with proper decimal handling)
      const formattedUserAssets = formattedUserShares > 0 && formattedTotalShares > 0 
        ? (formattedUserShares / formattedTotalShares) * formattedTotalAssets
        : 0;
      
      // Calculate share price directly (USDC per share)
      const formattedSharePrice = formattedTotalShares > 0
        ? formattedTotalAssets / formattedTotalShares
        : 100; // Default to 100 if no shares exist yet
      
      const newStats = {
        totalAssets: formattedTotalAssets.toFixed(2),
        totalShares: formattedTotalShares.toFixed(2),
        userShares: formattedUserShares.toFixed(2),
        userAssets: formattedUserAssets.toFixed(2),
        sharePrice: formattedSharePrice.toFixed(2),
      };
      
      // Update the stats
      setStats(newStats);
    } catch (error) {
      console.error('Error loading vault stats:', error);
      
      // If it's a BlockOutOfRangeError, try refreshing the provider
      if (isBlockOutOfRangeError(error) && retryCount < MAX_RETRIES) {
        setRetryCount(prev => prev + 1);
        
        try {
          if (refreshProvider) {
            await refreshProvider();
            setLoading(false);
            return; // Exit and let the useEffect retry with the new provider
          }
        } catch (refreshError) {
          // Continue to error handling
        }
      }
      
      setError('Failed to load vault statistics. Please try again later.');
    } finally {
      setLoading(false);
    }
  // Only include dependencies that actually change and trigger a re-render
  }, [vaultContract, provider, account, retryCount, refreshProvider, isBlockOutOfRangeError]);

  // Use a separate effect for initial load to prevent update loops
  useEffect(() => {
    if (vaultContract && provider && account) {
      loadVaultStats();
    }
  }, [vaultContract, provider, account, loadVaultStats]);
  
  // Use a separate effect for event subscription
  useEffect(() => {
    // Set up event listener for vault transaction completed events
    const handleTransactionCompleted = () => {
      // Add a small delay to ensure blockchain state is updated
      setTimeout(() => {
        loadVaultStats();
      }, 2000); // 2 second delay
    };
    
    const unsubscribe = eventBus.on(EVENTS.VAULT_TRANSACTION_COMPLETED, handleTransactionCompleted);
    
    // Clean up the event listener when the component unmounts
    return () => {
      unsubscribe();
    };
  }, [loadVaultStats]);

  const isDataLoading = loading || contractsLoading;

  return (
    <Card variant="outlined" sx={{ mb: 3 }}>
      <CardContent>
        <Typography variant="h6" gutterBottom>
          Vault Statistics
        </Typography>
        <Grid container spacing={2}>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Total Assets
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.totalAssets).toFixed(2)}</Typography>
              )}
            </Box>
          </Grid>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Total Shares
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.totalShares).toFixed(2)}</Typography>
              )}
            </Box>
          </Grid>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Share Price
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.sharePrice).toFixed(2)} USDC</Typography>
              )}
            </Box>
          </Grid>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Your Shares
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.userShares).toFixed(2)}</Typography>
              )}
            </Box>
          </Grid>
        </Grid>

        <Divider sx={{ my: 2 }} />

        <Box>
          <Typography variant="body2" color="text.secondary">
            Your Assets Value
          </Typography>
          {isDataLoading ? (
            <Skeleton width="50%" height={40} />
          ) : (
            <Typography variant="h5">{parseFloat(stats.userAssets).toFixed(2)}</Typography>
          )}
        </Box>
      </CardContent>
    </Card>
  );
};

export default VaultStats;
