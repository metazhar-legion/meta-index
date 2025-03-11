import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Grid,
  IconButton,
  CircularProgress,
  useTheme,
  alpha
} from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts } from '../hooks/useContracts';
import RefreshIcon from '@mui/icons-material/Refresh';
import TrendingUpIcon from '@mui/icons-material/TrendingUp';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import ShowChartIcon from '@mui/icons-material/ShowChart';
import PieChartIcon from '@mui/icons-material/PieChart';

// Import standardized utilities and components
import { createLogger } from '../utils/logging';
import { formatCurrency, formatTokenAmount } from '../utils/formatting';
import { ContractErrorMessage, withRetry } from '../utils/errors';
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
    const value: number = i === 6 ? baseValue : data[data.length - 1].value * randomFactor;
    
    data.push({
      date: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
      value: parseFloat(value.toFixed(2))
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
      const totalAssets = await withRetry(() => 
        safeContractCall(vaultContract, 'totalAssets', []), 
        { maxRetries: MAX_RETRIES, logErrors: true }
      );
      
      const totalSupply = await withRetry(() => 
        safeContractCall(vaultContract, 'totalSupply', []), 
        { maxRetries: MAX_RETRIES, logErrors: true }
      );
      
      const userShares = await withRetry(() => 
        safeContractCall(vaultContract, 'balanceOf', [account]), 
        { maxRetries: MAX_RETRIES, logErrors: true }
      );
      
      // Reset retry count on success
      setRetryCount(0);
      
      // Calculate derived values
      let userAssets = BigInt(0);
      
      if (totalSupply > BigInt(0)) {
        // Calculate user assets based on their share of the pool
        if (userShares > BigInt(0)) {
          userAssets = (userShares * totalAssets) / totalSupply;
          logger.debug('Calculated userAssets:', userAssets.toString());
        }
      }
      
      // Format the values using our standardized formatting utilities
      // USDC has 6 decimals, shares have 18 decimals
      const formattedTotalAssets = formatCurrency(totalAssets, 6);
      const formattedTotalShares = formatTokenAmount(totalSupply, 6);
      const formattedUserShares = formatTokenAmount(userShares, 6);
      
      // Calculate user assets in USDC
      const formattedUserAssets = Number(formattedUserShares) > 0 && Number(formattedTotalShares) > 0 
        ? (Number(formattedUserShares) / Number(formattedTotalShares)) * Number(formattedTotalAssets)
        : 0;
      
      // Calculate share price (USDC per share)
      const formattedSharePrice = Number(formattedTotalShares) > 0
        ? Number(formattedTotalAssets) / Number(formattedTotalShares)
        : 100; // Default to 100 if no shares exist yet
      
      const newStats = {
        totalAssets: formattedTotalAssets,
        totalShares: formattedTotalShares,
        userShares: formattedUserShares,
        userAssets: formattedUserAssets.toFixed(2),
        sharePrice: formattedSharePrice.toFixed(2),
      };
      
      logger.info('Vault statistics loaded successfully');
      
      // Update the stats with our delayed update hook
      statsState.updateValue(newStats, skipLoadingState);
    } catch (error) {
      logger.error('Failed to load vault statistics', error);
      
      // Use our standardized error handling
      const errorMessage = ContractErrorMessage(error, {
        defaultMessage: 'Failed to load vault statistics. Please try again later.',
        context: 'Loading vault statistics'
      });
      
      // If we need to refresh the provider
      if (errorMessage.includes('block height') && retryCount < MAX_RETRIES) {
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
      
      setError(errorMessage);
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
  useBlockchainEvents(
    EVENTS.VAULT_TRANSACTION_COMPLETED,
    () => {
      logger.info('Vault transaction completed, refreshing statistics');
      // Skip loading state for transaction events to avoid UI flicker
      loadVaultStats(true);
    },
    2000 // 2 second delay to ensure blockchain state is updated
  );

  // Only show loading state for the initial load or explicit refresh actions
  const isDataLoading = (loading && isInitialLoad) || contractsLoading;
  
  // Format numbers with commas
  const formatNumber = (value: string | number) => {
    const num = typeof value === 'string' ? parseFloat(value) : value;
    return new Intl.NumberFormat('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(num);
  };
  
  // Calculate percentage change (for demo purposes)
  const calculateChange = () => {
    if (chartData.length < 2) return { value: 0, isPositive: true };
    const firstValue = chartData[0].value;
    const lastValue = chartData[chartData.length - 1].value;
    const change = ((lastValue - firstValue) / firstValue) * 100;
    return { value: Math.abs(change).toFixed(2), isPositive: change >= 0 };
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
            <IconButton onClick={handleRefresh} disabled={isDataLoading} size="small">
              {isDataLoading ? <CircularProgress size={20} /> : <RefreshIcon />}
            </IconButton>
          </Box>
          
          <Grid container spacing={3}>
            {/* Total Assets Card */}
            <Grid item xs={12} sm={6} md={3}>
              <Box sx={{
                p: 2,
                borderRadius: 2,
                bgcolor: alpha(theme.palette.primary.main, 0.08),
                display: 'flex',
                flexDirection: 'column'
              }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">
                    Total Assets
                  </Typography>
                  <ShowChartIcon color="primary" fontSize="small" />
                </Box>
                {isDataLoading ? (
                  <Skeleton width="100%" height={40} />
                ) : (
                  <Typography variant="h5" fontWeight="600">
                    <CountUp 
                      end={parseFloat(stats.totalAssets)} 
                      prefix="$" 
                      decimals={2} 
                      duration={1} 
                      separator=","
                    />
                  </Typography>
                )}
              </Box>
            </Grid>
            
            {/* Share Price Card */}
            <Grid item xs={12} sm={6} md={3}>
              <Box sx={{
                p: 2,
                borderRadius: 2,
                bgcolor: alpha(theme.palette.info.main, 0.08),
                display: 'flex',
                flexDirection: 'column'
              }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">
                    Share Price
                  </Typography>
                  <TrendingUpIcon color="info" fontSize="small" />
                </Box>
                {isDataLoading ? (
                  <Skeleton width="100%" height={40} />
                ) : (
                  <Typography variant="h5" fontWeight="600">
                    <CountUp 
                      end={parseFloat(stats.sharePrice)} 
                      prefix="$" 
                      decimals={2} 
                      duration={1} 
                      separator=","
                    />
                  </Typography>
                )}
                {!isDataLoading && (
                  <Box sx={{ display: 'flex', alignItems: 'center', mt: 1 }}>
                    <Typography 
                      variant="body2" 
                      color={change.isPositive ? 'success.main' : 'error.main'}
                      sx={{ display: 'flex', alignItems: 'center' }}
                    >
                      {change.isPositive ? '+' : '-'}{change.value}%
                    </Typography>
                    <Typography variant="caption" color="text.secondary" sx={{ ml: 1 }}>
                      7d
                    </Typography>
                  </Box>
                )}
              </Box>
            </Grid>
            
            {/* Your Shares Card */}
            <Grid item xs={12} sm={6} md={3}>
              <Box sx={{
                p: 2,
                borderRadius: 2,
                bgcolor: alpha(theme.palette.warning.main, 0.08),
                display: 'flex',
                flexDirection: 'column'
              }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">
                    Your Shares
                  </Typography>
                  <PieChartIcon color="warning" fontSize="small" />
                </Box>
                {isDataLoading ? (
                  <Skeleton width="100%" height={40} />
                ) : (
                  <Typography variant="h5" fontWeight="600">
                    <CountUp 
                      end={parseFloat(stats.userShares)} 
                      decimals={2} 
                      duration={1} 
                      separator=","
                    />
                  </Typography>
                )}
              </Box>
            </Grid>
            
            {/* Your Assets Card */}
            <Grid item xs={12} sm={6} md={3}>
              <Box sx={{
                p: 2,
                borderRadius: 2,
                bgcolor: alpha(theme.palette.success.main, 0.08),
                display: 'flex',
                flexDirection: 'column'
              }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography variant="body2" color="text.secondary">
                    Your Assets
                  </Typography>
                  <AccountBalanceWalletIcon color="success" fontSize="small" />
                </Box>
                {isDataLoading ? (
                  <Skeleton width="100%" height={40} />
                ) : (
                  <Typography variant="h5" fontWeight="600">
                    <CountUp 
                      end={parseFloat(stats.userAssets)} 
                      prefix="$" 
                      decimals={2} 
                      duration={1} 
                      separator=","
                    />
                  </Typography>
                )}
              </Box>
            </Grid>
          </Grid>
          
          {/* Chart Section */}
          <Box sx={{ mt: 4, height: 250 }}>
            <Typography variant="subtitle1" gutterBottom>Share Price History</Typography>
            {/* Always render the chart to avoid jarring reloads, use opacity for loading state */}
            <Box sx={{ position: 'relative', width: '100%', height: '100%' }}>
              {isDataLoading && (
                <Box sx={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, zIndex: 1 }}>
                  <Skeleton variant="rectangular" width="100%" height="100%" />
                </Box>
              )}
              <Box sx={{ 
                position: 'relative', 
                width: '100%', 
                height: '100%', 
                zIndex: isDataLoading ? 0 : 1,
                opacity: isDataLoading ? 0.3 : 1,
                transition: 'opacity 0.3s ease-in-out'
              }}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                  <defs>
                    <linearGradient id="colorValue" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor={theme.palette.primary.main} stopOpacity={0.8}/>
                      <stop offset="95%" stopColor={theme.palette.primary.main} stopOpacity={0}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke={alpha(theme.palette.divider, 0.3)} />
                  <XAxis 
                    dataKey="date" 
                    tick={{ fill: theme.palette.text.secondary, fontSize: 12 }}
                    axisLine={{ stroke: theme.palette.divider }}
                  />
                  <YAxis 
                    tick={{ fill: theme.palette.text.secondary, fontSize: 12 }}
                    axisLine={{ stroke: theme.palette.divider }}
                    tickFormatter={(value) => `$${value}`}
                  />
                  <RechartsTooltip 
                    formatter={(value: number) => [`$${value.toFixed(2)}`, 'Share Price']}
                    labelFormatter={(label) => `Date: ${label}`}
                    contentStyle={{ 
                      backgroundColor: theme.palette.background.paper,
                      border: `1px solid ${theme.palette.divider}`,
                      borderRadius: 8,
                      boxShadow: '0 4px 20px rgba(0,0,0,0.15)'
                    }}
                  />
                  <Area 
                    type="monotone" 
                    dataKey="value" 
                    stroke={theme.palette.primary.main} 
                    fillOpacity={1} 
                    fill="url(#colorValue)" 
                  />
                </AreaChart>
              </ResponsiveContainer>
              </Box>
            </Box>
          </Box>
        </CardContent>
      </Card>
    </>
  );
};

export default VaultStats;
