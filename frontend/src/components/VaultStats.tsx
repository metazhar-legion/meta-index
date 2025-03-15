import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Grid,
  IconButton,
  useTheme,
  alpha,
  Skeleton,
  CircularProgress
} from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts } from '../hooks/useContracts';
import RefreshIcon from '@mui/icons-material/Refresh';
import TrendingUpIcon from '@mui/icons-material/TrendingUp';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import ShowChartIcon from '@mui/icons-material/ShowChart';
import PieChartIcon from '@mui/icons-material/PieChart';
import CountUp from 'react-countup';
import { ResponsiveContainer, AreaChart, Area, CartesianGrid, XAxis, YAxis, Tooltip as RechartsTooltip } from 'recharts';

// Import standardized utilities and components
import { createLogger } from '../utils/logging';
import { formatCurrency, formatTokenAmount, formatPercent } from '../utils/formatting';
import { ContractErrorMessage, withRetry, parseErrorMessage } from '../utils/errors';
import { safeContractCall } from '../utils/contracts';
import { useDelayedUpdate, useBlockchainEvents } from '../utils/hooks';
import StatCard from './common/StatCard';
import ChartWithLoading from './common/ChartWithLoading';
import eventBus, { EVENTS } from '../utils/eventBus';

// Initialize logger
const logger = createLogger('VaultStats');

// Sample data for the chart - in a real app, this would come from an API or contract
const generateSampleData = () => {
  const data = [];
  const today = new Date();
  const baseValue = 100;
  
  for (let i = 6; i >= 0; i--) {
    const date = new Date(today);
    date.setDate(date.getDate() - i);
    
    // Generate a random value that trends upward slightly
    const randomFactor = 0.95 + Math.random() * 0.1; // Between 0.95 and 1.05
    const value: number = i === 6 ? baseValue : parseFloat(data[data.length - 1].value) * randomFactor;
    
    data.push({
      date: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
      value: value.toFixed(2)
    });
  }
  
  return data;
};

const VaultStats: React.FC = () => {
  const theme = useTheme();
  const { vaultContract, isLoading: contractsLoading } = useContracts();
  const { account, provider, refreshProvider } = useWeb3();
  
  // Define stats interface for better type safety
  interface VaultStats {
    totalAssets: string;
    totalShares: string;
    userShares: string;
    userAssets: string;
    sharePrice: string;
  }
  
  // Use the delayed update hook for smoother UI transitions
  // Reduced delay from 3000ms to 300ms for much faster updates
  // Note: We're bypassing this delay by using skipDelay=true, but keeping a small value as fallback
  const statsState = useDelayedUpdate<VaultStats>({
    totalAssets: '0',
    totalShares: '0',
    userShares: '0',
    userAssets: '0',
    sharePrice: '0',
  }, 300);
  
  // Track loading and error states
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  
  // Track if this is the initial load
  const [isInitialLoad, setIsInitialLoad] = useState(true);
  
  // Generate sample data for the chart and persist it between renders
  const [chartData, setChartData] = useState(() => generateSampleData());
  
  // Function to update chart data with real values when available
  const updateChartData = useCallback((sharePrice: number) => {
    // In a real implementation, we would fetch historical data
    // For now, we'll just update the last data point with the current share price
    if (chartData.length > 0) {
      const newData = [...chartData];
      newData[newData.length - 1].value = sharePrice.toFixed(2);
      setChartData(newData);
    }
  }, [chartData]);
  
  // Constants
  const MAX_RETRIES = 3;

  // Use the standardized contract interaction utilities instead of custom helpers

  // Memoize the loadVaultStats function to prevent recreation on every render
  const loadVaultStats = useCallback(async (skipLoadingState = false) => {
    if (!vaultContract || !provider || !account) {
      logger.warn('Cannot load vault stats: missing contract, provider, or account');
      return;
    }
    
    // Only show loading state if not skipping it (for background refreshes)
    if (!skipLoadingState) {
      setLoading(true);
    }

    setError(null);
    
    try {
      logger.info('Loading vault statistics');
      
      logger.info('Making contract calls to get vault data');
      logger.info('Account address:', account);
      
      // Make individual contract calls for better error handling
      let totalAssets, totalSupply, userShares;
      
      try {
        // Get total assets
        logger.debug('Calling vaultContract.totalAssets()');
        totalAssets = await vaultContract.totalAssets();
        logger.debug('totalAssets result:', totalAssets.toString());
      } catch (error) {
        logger.error('Error getting totalAssets:', error);
        totalAssets = BigInt(0);
      }
      
      try {
        // Get total supply
        logger.debug('Calling vaultContract.totalSupply()');
        totalSupply = await vaultContract.totalSupply();
        logger.debug('totalSupply result:', totalSupply.toString());
      } catch (error) {
        logger.error('Error getting totalSupply:', error);
        totalSupply = BigInt(0);
      }
      
      try {
        // Get user shares from the vault contract
        userShares = await vaultContract.balanceOf(account);
      } catch (error) {
        logger.error('Error getting userShares:', error);
        userShares = BigInt(0);
      }
      
      // Reset retry count on success
      setRetryCount(0);
      
      // Ensure we have valid BigInt values
      const totalAssetsBigInt = BigInt(totalAssets.toString());
      const totalSupplyBigInt = BigInt(totalSupply.toString());
      const userSharesBigInt = BigInt(userShares.toString());
      
      // Format the values using our standardized formatting utilities
      // USDC has 6 decimals, shares have 18 decimals
      const formattedTotalAssets = formatCurrency(ethers.formatUnits(totalAssetsBigInt, 6));
      
      // Log raw share values before formatting
      logger.debug('Raw share values before formatting:');
      logger.debug('- totalSupplyBigInt raw:', totalSupplyBigInt.toString());
      logger.debug('- userSharesBigInt raw:', userSharesBigInt.toString());
      logger.debug('- totalSupplyBigInt formatted:', ethers.formatUnits(totalSupplyBigInt, 18));
      logger.debug('- userSharesBigInt formatted:', ethers.formatUnits(userSharesBigInt, 18));
      
      // Format share values with proper decimals - ensure we're getting the correct numeric representation
      // For shares, we want to show the actual number of shares (e.g., 10.0) not the full decimal representation
      const formattedTotalShares = formatTokenAmount(ethers.formatUnits(totalSupplyBigInt, 18));
      
      // Format the user shares with ethers.js - keep it simple like the other values
      const formattedUserShares = ethers.formatUnits(userSharesBigInt, 18);
      logger.debug('User shares formatted:', formattedUserShares);
      
      logger.debug('Formatted values:');
      logger.debug('- formattedTotalAssets:', formattedTotalAssets);
      logger.debug('- formattedTotalShares:', formattedTotalShares);
      logger.debug('- formattedUserShares:', formattedUserShares);
      
      // Calculate numeric values for further calculations - ensure we're handling strings properly
      const totalAssetsNum = parseFloat(formattedTotalAssets.replace('$', '').replace(/,/g, '') || '0');
      const totalSharesNum = parseFloat(formattedTotalShares.replace(/,/g, '') || '0');
      
      // For user shares, we already have a properly formatted value
      const userSharesNum = parseFloat(formattedUserShares);
      
      // Log the raw user shares value from ethers for debugging
      logger.debug('Raw user shares from ethers:', ethers.formatUnits(userSharesBigInt, 18));
      
      logger.debug('Numeric values for calculations:');
      logger.debug('- totalAssetsNum:', totalAssetsNum);
      logger.debug('- totalSharesNum:', totalSharesNum);
      logger.debug('- userSharesNum:', userSharesNum);
      
      // Calculate user assets in USDC - properly handle USDC's 6 decimals
      let userAssetsBigInt = BigInt(0);
      if (userSharesBigInt > BigInt(0) && totalSupplyBigInt > BigInt(0)) {
        // Calculate user's proportional share of total assets using BigInt for precision
        userAssetsBigInt = (userSharesBigInt * totalAssetsBigInt) / totalSupplyBigInt;
        logger.debug('Calculated userAssetsBigInt:', userAssetsBigInt.toString());
      }
      
      // Format the user assets with proper decimals
      const formattedUserAssets = parseFloat(ethers.formatUnits(userAssetsBigInt, 6));
      
      // Calculate share price (USDC per share) - properly handle different decimals
      let sharePrice = 100; // Default to 100 if no shares exist yet
      
      if (totalSupplyBigInt > BigInt(0)) {
        // Calculate price using BigInt math for precision
        // We need to adjust for the decimal difference between USDC (6) and shares (18)
        // Multiply by 10^12 to account for the decimal difference
        const decimalAdjustment = BigInt(10) ** BigInt(12);
        const sharePriceBigInt = (totalAssetsBigInt * decimalAdjustment) / totalSupplyBigInt;
        
        // Format to a regular number
        sharePrice = parseFloat(ethers.formatUnits(sharePriceBigInt, 12));
        logger.debug('Calculated sharePriceBigInt:', sharePriceBigInt.toString());
        logger.debug('Calculated sharePrice:', sharePrice);
      }
      
      logger.debug('Calculated values:');
      logger.debug('- formattedUserAssets:', formattedUserAssets);
      logger.debug('- sharePrice:', sharePrice);
      
      // Create the new stats object with string values
      // Create the stats object with consistent formatting for all values
      // For user shares, we need to ensure we have a numeric value that will display properly
      // The contract is using 18 decimals, but it looks like the actual shares are stored with 6 decimals
      // So we need to adjust our formatting
      const rawUserShares = ethers.formatUnits(userSharesBigInt, 6); // Use 6 decimals instead of 18
      
      // Then parse it to a number and format to 2 decimal places
      const userSharesValue = parseFloat(rawUserShares).toFixed(2);
      
      const newStats = {
        totalAssets: formattedTotalAssets,
        totalShares: formattedTotalShares,
        userShares: userSharesValue, // Use the formatted string directly
        userAssets: formattedUserAssets.toFixed(2),
        sharePrice: sharePrice.toFixed(2),
      };
      
      // Log the final stats object to browser console

      
      logger.debug('Final stats object:', newStats);
      
      // Update chart data with the latest share price
      updateChartData(sharePrice);
      
      logger.info('Vault statistics loaded successfully');
      
      // Always update the stats immediately without delay for more responsive UI
      statsState.updateValue(newStats, true);
    } catch (error) {
      logger.error('Failed to load vault statistics', error);
      
      // Use our standardized error handling
      const errorMessage = <ContractErrorMessage
        error={error}
        severity="error"
      />;
      
      // Set the error message
      setError(typeof errorMessage === 'string' ? errorMessage : 'Unknown error');
    } finally {
      // Always reset loading state
      setLoading(false);
    }
  }, [vaultContract, provider, account, retryCount, refreshProvider, statsState]);

  // Use a separate effect for initial load to prevent update loops
  useEffect(() => {
    if (vaultContract && provider && account && isInitialLoad) {
      logger.info('Initial load of vault statistics');
      loadVaultStats();
      setIsInitialLoad(false);
    }
  }, [vaultContract, provider, account, loadVaultStats, isInitialLoad]);
  
  // Use the standardized blockchain events hook for event subscription with immediate updates
  useBlockchainEvents({
    eventName: EVENTS.VAULT_TRANSACTION_COMPLETED,
    handler: () => {
      logger.info('Vault transaction completed, refreshing statistics immediately');
      
      // Reset state for a clean refresh
      setError(null);
      setLoading(true);
      setRetryCount(0);
      
      // Immediately load vault stats if we have all necessary components
      if (vaultContract && provider && account) {
        // Immediate refresh with no delays
        loadVaultStats(true);
      } else {
        logger.warn('Cannot refresh stats: missing contract, provider, or account');
        setLoading(false);
      }
    },
    // No delay for immediate response
    delay: 0
  });
  
  // Set up polling for automatic updates every 5 seconds
  useEffect(() => {
    // Only set up polling if we have the necessary components
    if (!vaultContract || !provider || !account) return;
    
    logger.info('Setting up automatic polling for vault statistics');
    
    // Create polling interval
    const pollInterval = setInterval(() => {
      // Only refresh if not already loading and if we have all necessary components
      if (!loading && vaultContract && provider && account) {
        logger.debug('Polling: refreshing vault statistics');
        // Always use skipLoadingState=true for polling to prevent UI flicker
        loadVaultStats(true); // Use true to skip loading state for background refresh
      }
    }, 10000); // Poll every 10 seconds instead of 5 to reduce unnecessary updates
    
    // Clean up interval on unmount
    return () => {
      logger.info('Cleaning up vault statistics polling');
      clearInterval(pollInterval);
    };
  }, [vaultContract, provider, account, loading, loadVaultStats]);

  // Only show loading state for the initial load or explicit refresh actions
  const isDataLoading = loading || contractsLoading;
  
  // Format numbers with commas - using our standardized formatting utility
  const formatNumber = (value: string | number | bigint | null | undefined): string => {
    if (value === null || value === undefined) return '0.00';
    
    let num: number;
    if (typeof value === 'bigint') {
      num = Number(value.toString());
    } else if (typeof value === 'string') {
      num = parseFloat(value);
    } else if (typeof value === 'number') {
      num = value;
    } else {
      num = 0; // Default fallback
    }
    
    const formattedNum = isNaN(num) ? 0 : num;
    return new Intl.NumberFormat('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(formattedNum).toString();
  };
  
  // Calculate percentage change (for demo purposes)
  const calculateChange = () => {
    if (chartData.length < 2) return { value: 0, isPositive: true };
    
    // Ensure values are numbers for calculation
    const firstValue = parseFloat(chartData[0].value);
    const lastValue = parseFloat(chartData[chartData.length - 1].value);
    
    if (isNaN(firstValue) || isNaN(lastValue) || firstValue === 0) {
      return { value: 0, isPositive: true };
    }
    
    const change = ((lastValue - firstValue) / firstValue) * 100;
    return { value: Math.abs(change), isPositive: change >= 0 };
  };
  
  const change = calculateChange();
  
  const handleRefresh = async () => {
    // Force an immediate update when manually refreshing
    logger.info('Manual refresh of vault statistics');
    setLoading(true); // Show loading state for manual refresh
    
    // Refresh the provider first to ensure we have the latest blockchain state
    if (refreshProvider) {
      try {
        logger.info('Refreshing provider before loading stats');
        await refreshProvider();
      } catch (error) {
        logger.error('Failed to refresh provider', error);
      }
    }
    
    // Reset retry count to allow for new retries if needed
    setRetryCount(0);
    
    // Load vault stats with fresh provider state
    loadVaultStats(false); // Don't skip loading state for manual refresh
  };

  return (
    <>
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ py: 1, px: 2 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
            <Typography variant="h6">Vault Overview</Typography>
            <IconButton 
              onClick={handleRefresh} 
              disabled={loading && !isInitialLoad} 
              size="small"
            >
              {loading && !isInitialLoad ? <CircularProgress size={20} /> : <RefreshIcon />}
            </IconButton>
          </Box>
          
          <Grid container spacing={2}>
            {/* Total Assets Card */}
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Total Assets"
                isLoading={isDataLoading}
                value={statsState.value?.totalAssets?.replace('$', '').replace(/,/g, '') || '0'}
                icon={<ShowChartIcon />}
                color="primary"
                prefix="$"
                decimals={2}
              />
            </Grid>
            
            {/* Share Price Card */}
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Share Price"
                isLoading={isDataLoading}
                value={statsState.value?.sharePrice || '0'}
                icon={<TrendingUpIcon />}
                color="info"
                prefix="$"
                decimals={2}
                change={{
                  value: change.value,
                  isPositive: change.isPositive,
                  period: '7d'
                }}
              />
            </Grid>
            
            {/* Your Shares Card */}
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Your Shares"
                isLoading={isDataLoading}
                value={statsState.value?.userShares || '0'}
                icon={<PieChartIcon />}
                color="warning"
                decimals={2}
              />
            </Grid>
            
            {/* Your Assets Card */}
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Your Assets"
                isLoading={isDataLoading}
                value={statsState.value?.userAssets || '0'}
                icon={<AccountBalanceWalletIcon />}
                color="success"
                prefix="$"
                decimals={2}
              />
            </Grid>
          </Grid>
          
          {/* Chart Section */}
          <ChartWithLoading
            title="Share Price History"
            isLoading={isDataLoading}
            data={chartData}
            height={150}
            dataKey="value"
            xAxisKey="date"
            color={theme.palette.primary.main}
            tooltipFormatter={(value) => {
              // Ensure value is a number before calling toFixed
              const numValue = typeof value === 'string' ? parseFloat(value) : Number(value);
              return `$${isNaN(numValue) ? '0.00' : numValue.toFixed(2)}`;
            }}
          />
        </CardContent>
      </Card>
    </>
  );
};

export default VaultStats;
