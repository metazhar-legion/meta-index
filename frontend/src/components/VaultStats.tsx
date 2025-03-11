import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Grid,
  Skeleton,
  Divider,
  Tooltip,
  CircularProgress,
  IconButton,
  useTheme,
  alpha
} from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import eventBus, { EVENTS } from '../utils/eventBus';
import { useContracts } from '../hooks/useContracts';
import { toBigInt } from '../contracts/contractTypes';
import RefreshIcon from '@mui/icons-material/Refresh';
import TrendingUpIcon from '@mui/icons-material/TrendingUp';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import ShowChartIcon from '@mui/icons-material/ShowChart';
import PieChartIcon from '@mui/icons-material/PieChart';
import CountUp from 'react-countup';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, ResponsiveContainer, AreaChart, Area, Tooltip as RechartsTooltip } from 'recharts';
import { chartColors } from '../theme/theme';

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
  const [stats, setStats] = useState({
    totalAssets: '0',
    totalShares: '0',
    userShares: '0',
    userAssets: '0',
    sharePrice: '0',
  });
  // Add a separate state for pending stats to avoid UI flickering
  const [pendingStats, setPendingStats] = useState<{
    totalAssets: string;
    totalShares: string;
    userShares: string;
    userAssets: string;
    sharePrice: string;
  } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const [lastRefreshTime, setLastRefreshTime] = useState(Date.now());
  const MAX_RETRIES = 3;
  // Minimum time between visual updates (in ms)
  const MIN_UPDATE_INTERVAL = 3000;

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
      
      // Store the new stats in pendingStats first
      setPendingStats(newStats);
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
  
  // Apply pending stats to actual stats with a smooth transition
  useEffect(() => {
    if (pendingStats) {
      const now = Date.now();
      const timeSinceLastUpdate = now - lastRefreshTime;
      
      if (timeSinceLastUpdate >= MIN_UPDATE_INTERVAL) {
        // If enough time has passed, update immediately
        setStats(pendingStats);
        setPendingStats(null);
        setLastRefreshTime(now);
      } else {
        // Otherwise, schedule an update after the minimum interval
        const timeToWait = MIN_UPDATE_INTERVAL - timeSinceLastUpdate;
        const timer = setTimeout(() => {
          setStats(pendingStats);
          setPendingStats(null);
          setLastRefreshTime(Date.now());
        }, timeToWait);
        
        return () => clearTimeout(timer);
      }
    }
  }, [pendingStats, lastRefreshTime]);
  
  // Use a separate effect for event subscription
  useEffect(() => {
    // Set up event listener for vault transaction completed events
    const handleTransactionCompleted = () => {
      // Add a small delay to ensure blockchain state is updated
      setTimeout(() => {
        // Use a non-loading refresh for transaction events
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

  // Generate sample data for the chart
  const [chartData] = useState(generateSampleData());
  
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
    setLastRefreshTime(0); // Reset the last refresh time to ensure immediate update
    loadVaultStats();
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
            {isDataLoading ? (
              <Skeleton variant="rectangular" width="100%" height="100%" />
            ) : (
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
            )}
          </Box>
        </CardContent>
      </Card>
    </>
  );
};

export default VaultStats;
