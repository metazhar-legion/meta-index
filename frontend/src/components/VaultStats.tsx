import React, { useEffect, useState, useCallback } from 'react';
import { Box, Card, CardContent, Typography, Grid, Skeleton, Divider } from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import eventBus, { EVENTS } from '../utils/eventBus';
import { useContracts } from '../hooks/useContracts';
import { toBigInt } from '../contracts/contractTypes';

const VaultStats: React.FC = () => {
  const { account, provider } = useWeb3();
  const { vaultContract, isLoading: contractsLoading } = useContracts();
  
  const [stats, setStats] = useState({
    totalAssets: '0',
    totalShares: '0',
    userShares: '0',
    userAssets: '0',
    sharePrice: '0',
  });
  const [isLoading, setIsLoading] = useState(true);

  // Extract loadVaultStats to a separate function so it can be called from multiple places
  const loadVaultStats = useCallback(async () => {
    if (!vaultContract || !account || !provider) {
      console.log('Missing dependencies:', { 
        vaultContract: !!vaultContract, 
        account: !!account, 
        provider: !!provider 
      });
      setIsLoading(false);
      return;
    }
    
    setIsLoading(true);
    try {
      console.log('Loading vault stats...');
      console.log('Vault contract address:', await vaultContract.target);
      console.log('Account:', account);
      
      // Get vault contract address for debugging
      const vaultAddress = await vaultContract.target;
      console.log('Vault contract address:', vaultAddress);
      
      // Log provider and signer information
      console.log('Provider type:', provider.constructor.name);
      console.log('Is provider connected:', provider ? 'Yes' : 'No');
      console.log('Chain ID:', await provider.getNetwork().then(n => n.chainId));
      
      // Initialize values
      let totalAssets = BigInt(0);
      let totalSupply = BigInt(0);
      let userShares = BigInt(0);
      
      // Create a minimal interface with just the methods we need
      const vaultInterface = new ethers.Interface([
        "function totalAssets() view returns (uint256)",
        "function totalSupply() view returns (uint256)",
        "function balanceOf(address) view returns (uint256)"
      ]);
      
      // Try multiple approaches to get contract data
      // Approach 1: Direct contract method calls
      try {
        console.log('Attempting direct contract method calls...');
        
        try {
          if (typeof vaultContract.totalAssets === 'function') {
            totalAssets = await vaultContract.totalAssets();
            console.log('totalAssets from direct call:', totalAssets.toString());
          }
        } catch (e) {
          console.error('Direct totalAssets call failed:', e);
        }
        
        try {
          if (typeof vaultContract.totalSupply === 'function') {
            totalSupply = await vaultContract.totalSupply();
            console.log('totalSupply from direct call:', totalSupply.toString());
          }
        } catch (e) {
          console.error('Direct totalSupply call failed:', e);
        }
        
        try {
          if (typeof vaultContract.balanceOf === 'function') {
            userShares = await vaultContract.balanceOf(account);
            console.log('userShares from direct call:', userShares.toString());
          }
        } catch (e) {
          console.error('Direct balanceOf call failed:', e);
        }
      } catch (error) {
        console.warn('Error in direct contract calls:', error);
      }
      
      // Approach 2: Low-level calls if direct calls failed
      if (totalAssets === BigInt(0) || totalSupply === BigInt(0)) {
        console.log('Direct calls failed or returned zero values, trying low-level calls...');
        
        // Get total assets
        try {
          console.log('Fetching totalAssets via low-level call...');
          const callData = vaultInterface.encodeFunctionData('totalAssets', []);
          
          const result = await provider.call({
            to: vaultAddress,
            data: callData
          });
          console.log('Raw response for totalAssets:', result);
          
          if (result && result !== '0x') {
            try {
              // Try to decode the result
              const decoded = vaultInterface.decodeFunctionResult('totalAssets', result);
              console.log('Decoded totalAssets result:', decoded);
              
              // Use the helper function to handle different return formats
              totalAssets = toBigInt(decoded);
              console.log('Final totalAssets value:', totalAssets.toString());
            } catch (decodeError) {
              console.error('Error decoding totalAssets result:', decodeError);
              console.log('Attempting manual decoding...');
              
              // Manual decoding as fallback
              if (result.length >= 66) {  // 0x + 64 hex chars (32 bytes)
                const hexValue = result.slice(2);  // Remove '0x'
                totalAssets = BigInt('0x' + hexValue);
                console.log('Manually decoded totalAssets:', totalAssets.toString());
              }
            }
          } else {
            console.warn('Received empty result from totalAssets call:', result);
          }
        } catch (error) {
          console.error('Failed to get totalAssets via low-level call:', error);
        }
        
        // Get total supply
        try {
          console.log('Fetching totalSupply via low-level call...');
          const callData = vaultInterface.encodeFunctionData('totalSupply', []);
          
          const result = await provider.call({
            to: vaultAddress,
            data: callData
          });
          console.log('Raw response for totalSupply:', result);
          
          if (result && result !== '0x') {
            try {
              // Try to decode the result
              const decoded = vaultInterface.decodeFunctionResult('totalSupply', result);
              console.log('Decoded totalSupply result:', decoded);
              
              // Use the helper function to handle different return formats
              totalSupply = toBigInt(decoded);
              console.log('Final totalSupply value:', totalSupply.toString());
            } catch (decodeError) {
              console.error('Error decoding totalSupply result:', decodeError);
              console.log('Attempting manual decoding...');
              
              // Manual decoding as fallback
              if (result.length >= 66) {  // 0x + 64 hex chars (32 bytes)
                const hexValue = result.slice(2);  // Remove '0x'
                totalSupply = BigInt('0x' + hexValue);
                console.log('Manually decoded totalSupply:', totalSupply.toString());
              }
            }
          } else {
            console.warn('Received empty result from totalSupply call:', result);
          }
        } catch (error) {
          console.error('Failed to get totalSupply via low-level call:', error);
        }
        
        // Get user shares
        try {
          console.log('Fetching balanceOf via low-level call...');
          const callData = vaultInterface.encodeFunctionData('balanceOf', [account]);
          
          const result = await provider.call({
            to: vaultAddress,
            data: callData
          });
          console.log('Raw response for balanceOf:', result);
          
          if (result && result !== '0x') {
            try {
              // Try to decode the result
              const decoded = vaultInterface.decodeFunctionResult('balanceOf', result);
              console.log('Decoded balanceOf result:', decoded);
              
              // Use the helper function to handle different return formats
              userShares = toBigInt(decoded);
              console.log('Final userShares value:', userShares.toString());
            } catch (decodeError) {
              console.error('Error decoding balanceOf result:', decodeError);
              console.log('Attempting manual decoding...');
              
              // Manual decoding as fallback
              if (result.length >= 66) {  // 0x + 64 hex chars (32 bytes)
                const hexValue = result.slice(2);  // Remove '0x'
                userShares = BigInt('0x' + hexValue);
                console.log('Manually decoded userShares:', userShares.toString());
              }
            }
          } else {
            console.warn('Received empty result from balanceOf call:', result);
          }
        } catch (error) {
          console.error('Failed to get balanceOf via low-level call:', error);
        }
      }
      
      // Approach 3: Create a new contract instance if all else fails
      if (totalAssets === BigInt(0) || totalSupply === BigInt(0)) {
        console.log('Low-level calls failed, trying with a fresh contract instance...');
        
        try {
          // Create a fresh contract instance
          const freshContract = new ethers.Contract(
            vaultAddress,
            vaultInterface,
            provider
          );
          
          // Try to get data from the fresh contract
          try {
            totalAssets = await freshContract.totalAssets();
            console.log('totalAssets from fresh contract:', totalAssets.toString());
          } catch (e) {
            console.error('Fresh contract totalAssets call failed:', e);
          }
          
          try {
            totalSupply = await freshContract.totalSupply();
            console.log('totalSupply from fresh contract:', totalSupply.toString());
          } catch (e) {
            console.error('Fresh contract totalSupply call failed:', e);
          }
          
          try {
            userShares = await freshContract.balanceOf(account);
            console.log('userShares from fresh contract:', userShares.toString());
          } catch (e) {
            console.error('Fresh contract balanceOf call failed:', e);
          }
        } catch (error) {
          console.error('Error with fresh contract instance:', error);
        }
      }
      
      console.log('Final retrieved values:', {
        totalAssets: totalAssets.toString(),
        totalSupply: totalSupply.toString(),
        userShares: userShares.toString()
      });
      
      // Calculate derived values
      let userAssets = BigInt(0);
      let sharePrice = BigInt(0);
      
      if (totalSupply > BigInt(0)) {
        // Calculate user assets based on their share of the pool
        if (userShares > BigInt(0)) {
          userAssets = (userShares * totalAssets) / totalSupply;
          console.log('Calculated userAssets:', userAssets.toString());
        }
        
        // Calculate share price (price per 1 full share)
        sharePrice = (totalAssets * ethers.parseEther('1')) / totalSupply;
        console.log('Calculated sharePrice:', sharePrice.toString());
      }
      
      // Update state with the fetched and calculated values
      setStats({
        totalAssets: ethers.formatEther(totalAssets),
        totalShares: ethers.formatEther(totalSupply),
        userShares: ethers.formatEther(userShares),
        userAssets: ethers.formatEther(userAssets),
        sharePrice: ethers.formatEther(sharePrice),
      });
      
      console.log('Vault stats loaded successfully');
    } catch (error) {
      console.error('Error loading vault stats:', error);
      
      // Just show zeros in case of error - no hardcoded values
      setStats({
        totalAssets: '0',
        totalShares: '0',
        userShares: '0',
        userAssets: '0',
        sharePrice: '0',
      });
      
      console.log('Error occurred, showing zero values');
    } finally {
      setIsLoading(false);
    }
  }, [vaultContract, account, provider]);
  
  // Add effect to listen for vault transaction events
  useEffect(() => {
    // Subscribe to vault transaction completed events
    const handleVaultTransactionCompleted = () => {
      console.log('VaultStats: Vault transaction completed event received, refreshing stats...');
      loadVaultStats();
    };
    
    eventBus.on(EVENTS.VAULT_TRANSACTION_COMPLETED, handleVaultTransactionCompleted);
    
    // Cleanup subscription when component unmounts
    return () => {
      eventBus.off(EVENTS.VAULT_TRANSACTION_COMPLETED, handleVaultTransactionCompleted);
    };
  }, [loadVaultStats]);
  
  // Initial load
  useEffect(() => {
    loadVaultStats();
  }, [loadVaultStats]);

  const isDataLoading = isLoading || contractsLoading;

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
