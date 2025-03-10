import React, { useState, useEffect, useCallback } from 'react';
import { Box, Card, CardContent, Typography, Grid, Skeleton, Divider } from '@mui/material';
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
  const toBigInt = (value: any): bigint => {
    if (typeof value === 'bigint') return value;
    if (typeof value === 'number') return BigInt(value);
    if (typeof value === 'string') {
      if (value.startsWith('0x')) return BigInt(value);
      return BigInt(value);
    }
    if (Array.isArray(value) && value.length > 0) {
      return toBigInt(value[0]);
    }
    return BigInt(0);
  };

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
      
      // Helper function to fetch data with multiple strategies
      const fetchContractData = async (methodName: string, args: any[] = []) => {
        let result = BigInt(0);
        let error: any = null;
        
        // Strategy 1: Direct contract call
        try {
          if (typeof vaultContract[methodName as keyof typeof vaultContract] === 'function') {
            // @ts-ignore - We've already checked that this is a function
            result = await vaultContract[methodName](...args);
            if (result > BigInt(0)) return result;
          }
        } catch (e) {
          error = e;
          // Continue to next strategy
        }
        
        // Strategy 2: Low-level call
        try {
          const callData = vaultInterface.encodeFunctionData(methodName, args);
          const rawResult = await provider.call({
            to: vaultAddress,
            data: callData
          });
          
          if (rawResult && rawResult !== '0x') {
            try {
              const decoded = vaultInterface.decodeFunctionResult(methodName, rawResult);
              result = toBigInt(decoded);
              if (result > BigInt(0)) return result;
            } catch (decodeError) {
              // Try manual decoding as fallback
              if (rawResult.length >= 66) {
                const hexValue = rawResult.slice(2);
                result = BigInt('0x' + hexValue);
                if (result > BigInt(0)) return result;
              }
            }
          }
        } catch (e) {
          error = e;
          // Continue to next strategy
        }
        
        // Strategy 3: Fresh contract instance
        try {
          const freshContract = new ethers.Contract(
            vaultAddress,
            vaultInterface,
            provider
          );
          
          // @ts-ignore - Dynamic method call
          result = await freshContract[methodName](...args);
          return result;
        } catch (e) {
          error = e;
          
          // Check if this is a BlockOutOfRangeError
          if (isBlockOutOfRangeError(e)) {
            throw e; // Re-throw to be caught by the outer try-catch for refresh handling
          }
          
          // Return the best result we have
          return result;
        }
      };
      
      try {
        // Fetch all required data
        totalAssets = await fetchContractData('totalAssets');
        totalSupply = await fetchContractData('totalSupply');
        userShares = await fetchContractData('balanceOf', [account]);
        
        // Reset retry count on success
        setRetryCount(0);
      } catch (fetchError) {
        // If it's a BlockOutOfRangeError, try refreshing the provider
        if (isBlockOutOfRangeError(fetchError) && retryCount < MAX_RETRIES) {
          console.log(`BlockOutOfRangeError detected in VaultStats, refreshing provider (attempt ${retryCount + 1}/${MAX_RETRIES})`);
          setRetryCount(prev => prev + 1);
          
          try {
            if (refreshProvider) {
              const freshProvider = await refreshProvider();
              if (freshProvider) {
                console.log('Provider refreshed successfully, retrying data fetch');
                setLoading(false);
                return; // Exit and let the useEffect retry with the new provider
              }
            }
          } catch (refreshError) {
            console.error('Error refreshing provider:', refreshError);
          }
        }
        
        throw fetchError; // Re-throw to be caught by the outer try-catch
      }
      
      // Calculate derived values
      let userAssets = BigInt(0);
      let sharePrice = BigInt(0);
      
      if (totalSupply > BigInt(0)) {
        // Calculate user assets based on their share of the pool
        if (userShares > BigInt(0)) {
          userAssets = (userShares * totalAssets) / totalSupply;
        }
        
        // Calculate share price (price per 1 full share)
        sharePrice = (totalAssets * ethers.parseEther('1')) / totalSupply;
      }
      
      // Update state with the fetched and calculated values
      setStats({
        totalAssets: ethers.formatEther(totalAssets),
        totalShares: ethers.formatEther(totalSupply),
        userShares: ethers.formatEther(userShares),
        userAssets: ethers.formatEther(userAssets),
        sharePrice: ethers.formatEther(sharePrice),
      });
    } catch (error) {
      console.error('Error loading vault stats:', error);
      
      // If it's a BlockOutOfRangeError, try refreshing the provider
      if (isBlockOutOfRangeError(error) && retryCount < MAX_RETRIES) {
        console.log(`BlockOutOfRangeError detected in VaultStats, refreshing provider (attempt ${retryCount + 1}/${MAX_RETRIES})`);
        setRetryCount(prev => prev + 1);
        
        try {
          if (refreshProvider) {
            const freshProvider = await refreshProvider();
            if (freshProvider) {
              console.log('Provider refreshed successfully, retrying data fetch');
              setLoading(false);
              return; // Exit and let the useEffect retry with the new provider
            }
          }
        } catch (refreshError) {
          console.error('Error refreshing provider:', refreshError);
        }
      }
      
      setError('Failed to load vault statistics. Please try again later.');
    } finally {
      setLoading(false);
    }
  }, [vaultContract, provider, account, retryCount, refreshProvider, isBlockOutOfRangeError]);

  useEffect(() => {
    loadVaultStats();
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
                <Typography variant="h6">{parseFloat(stats.totalAssets).toFixed(4)}</Typography>
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
                <Typography variant="h6">{parseFloat(stats.totalShares).toFixed(4)}</Typography>
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
                <Typography variant="h6">{parseFloat(stats.sharePrice).toFixed(4)}</Typography>
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
                <Typography variant="h6">{parseFloat(stats.userShares).toFixed(4)}</Typography>
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
            <Typography variant="h5">{parseFloat(stats.userAssets).toFixed(4)}</Typography>
          )}
        </Box>
      </CardContent>
    </Card>
  );
};

export default VaultStats;
