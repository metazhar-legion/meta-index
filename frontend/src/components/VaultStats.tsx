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
  const statsState = useDelayedUpdate<VaultStats>({
    totalAssets: '0',
    totalShares: '0',
    userShares: '0',
    userAssets: '0',
    sharePrice: '0',
  }, 3000);
  
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

    // Only show loading state if not skipping it
    if (!skipLoadingState) {
      setLoading(true);
    }
    setError(null);
    
    try {
      logger.info('Loading vault statistics');
      
      // Use safe contract calls with standardized error handling
      const totalAssets = await withRetry(
        async () => {
          return await safeContractCall(vaultContract, 'totalAssets', [], BigInt(0));
        }, 
        MAX_RETRIES
      );
      
      const totalSupply = await withRetry(
        async () => {
          return await safeContractCall(vaultContract, 'totalSupply', [], BigInt(0));
        }, 
        MAX_RETRIES
      );
      
      const userShares = await withRetry(
        async () => {
          return await safeContractCall(vaultContract, 'balanceOf', [account], BigInt(0));
        }, 
        MAX_RETRIES
      );
      
      // Reset retry count on success
      setRetryCount(0);
      
      // Calculate derived values
      let userAssets = BigInt(0);
      
      // Ensure we have valid BigInt values
      const totalSupplyBigInt = totalSupply ? BigInt(totalSupply.toString()) : BigInt(0);
      const userSharesBigInt = userShares ? BigInt(userShares.toString()) : BigInt(0);
      const totalAssetsBigInt = totalAssets ? BigInt(totalAssets.toString()) : BigInt(0);
      
      if (totalSupplyBigInt > BigInt(0) && userSharesBigInt > BigInt(0)) {
        // Calculate user assets based on their share of the pool
        userAssets = (userSharesBigInt * totalAssetsBigInt) / totalSupplyBigInt;
        logger.debug('Calculated userAssets:', userAssets.toString());
      }
      
      // Format the values using our standardized formatting utilities
      // USDC has 6 decimals, shares have 18 decimals
      const formattedTotalAssets = formatCurrency(totalAssetsBigInt);
      const formattedTotalShares = formatTokenAmount(totalSupplyBigInt, 18);
      const formattedUserShares = formatTokenAmount(userSharesBigInt, 18);
      
      // Calculate user assets in USDC - remove the $ prefix from formatted values for calculations
      const totalAssetsNum = parseFloat(formattedTotalAssets.replace('$', '').replace(/,/g, ''));
      const totalSharesNum = parseFloat(formattedTotalShares.replace(/,/g, ''));
      const userSharesNum = parseFloat(formattedUserShares.replace(/,/g, ''));
      
      // Calculate user assets in USDC
      const formattedUserAssets: number = userSharesNum > 0 && totalSharesNum > 0 
        ? (userSharesNum / totalSharesNum) * totalAssetsNum
        : 0;
      
      // Calculate share price (USDC per share)
      const formattedSharePrice = totalSharesNum > 0
        ? totalAssetsNum / totalSharesNum
        : 100; // Default to 100 if no shares exist yet
      
      const newStats = {
        totalAssets: formattedTotalAssets,
        totalShares: formattedTotalShares,
        userShares: formattedUserShares,
        userAssets: formattedUserAssets.toFixed(2),
        sharePrice: formattedSharePrice.toFixed(2),
      };
      
      // Update chart data with the latest share price
      updateChartData(formattedSharePrice);
      
      logger.info('Vault statistics loaded successfully');
      
      // Update the stats with our delayed update hook
      statsState.updateValue(newStats, skipLoadingState);
    } catch (error) {
      logger.error('Failed to load vault statistics', error);
      
      // Use our standardized error handling
      const errorMessage = <ContractErrorMessage
        error={error}
        severity="error"
      />;
      
      // If we need to refresh the provider
      const parsedErrorMessage = parseErrorMessage(error);
      if (parsedErrorMessage.includes('block height') && retryCount < MAX_RETRIES) {
        logger.info(`Refreshing provider (attempt ${retryCount + 1}/${MAX_RETRIES})`);
        setRetryCount(prev => prev + 1);
        
        try {
          if (refreshProvider) {
            await refreshProvider();
            setLoading(false);
            return; // Exit and let the useEffect retry with the new provider
          }
        } catch (refreshError) {
          logger.error('Failed to refresh provider', refreshError);
        }
      }
      
      setError(typeof errorMessage === 'string' ? errorMessage : 'Unknown error');
    } finally {
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
  
  // Use the standardized blockchain events hook for event subscription
  useBlockchainEvents({
    eventName: EVENTS.VAULT_TRANSACTION_COMPLETED,
    handler: () => {
      logger.info('Vault transaction completed, refreshing statistics');
      // Skip loading state for transaction events to avoid UI flicker
      setTimeout(() => {
        if (vaultContract && provider && account) {
          logger.info('Refreshing vault statistics after transaction');
          loadVaultStats(true);
        } else {
          logger.warn('Cannot refresh stats: missing contract, provider, or account');
        }
      }, 1000); // Additional delay to ensure contract state is updated
    },
    delay: 2000 // 2 second delay to ensure blockchain state is updated
  });

  // Only show loading state for the initial load or explicit refresh actions
  const isDataLoading = (loading && isInitialLoad) || contractsLoading;
  
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
  
  const handleRefresh = () => {
    // Force an immediate update when manually refreshing
    logger.info('Manual refresh of vault statistics');
    setLoading(true); // Show loading state for manual refresh
    loadVaultStats(false); // Don't skip loading state for manual refresh
  };

  return (
    <>
      <Card sx={{ mb: 3 }}>
        <CardContent>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
            <Typography variant="h6">Vault Overview</Typography>
            <IconButton 
              onClick={handleRefresh} 
              disabled={loading && !isInitialLoad} 
              size="small"
            >
              {loading && !isInitialLoad ? <CircularProgress size={20} /> : <RefreshIcon />}
            </IconButton>
          </Box>
          
          <Grid container spacing={3}>
            {/* Total Assets Card */}
            <Grid item xs={12} sm={6} md={3}>
              <StatCard
                title="Total Assets"
                isLoading={isDataLoading}
                value={parseFloat(statsState.value?.totalAssets || '0')}
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
                value={parseFloat(statsState.value?.sharePrice || '0')}
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
                value={parseFloat(statsState.value?.userShares || '0')}
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
                value={parseFloat(statsState.value?.userAssets || '0')}
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
            height={250}
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
