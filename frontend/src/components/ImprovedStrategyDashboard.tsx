import React, { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Grid,
  Button,
  LinearProgress,
  Chip,
  Alert,
  Divider,
  IconButton,
  Tooltip,
  CircularProgress,
  Paper,
  Skeleton,
  Snackbar,
} from '@mui/material';
import {
  TrendingUp,
  TrendingDown,
  Settings,
  Refresh,
  Warning,
  CheckCircle,
  Info,
  ShowChart,
} from '@mui/icons-material';
import { PieChart, Pie, Cell, ResponsiveContainer, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, Legend } from 'recharts';
import { ethers } from 'ethers';
import { 
  useComposableRWAData, 
  useOptimizeStrategies, 
  useRebalanceStrategies 
} from '../hooks/queries';
import { StrategyType, StrategyAllocation } from '../contracts/composableRWATypes';
import { ErrorBoundary } from './ErrorBoundary';

// Color scheme for strategies
const STRATEGY_COLORS = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7'];

const STRATEGY_NAMES = {
  [StrategyType.TRS]: 'Total Return Swap',
  [StrategyType.PERPETUAL]: 'Perpetual Futures',
  [StrategyType.DIRECT_TOKEN]: 'Direct Token',
  [StrategyType.SYNTHETIC_TOKEN]: 'Synthetic Token',
  [StrategyType.OPTIONS]: 'Options',
};

interface StrategyDashboardProps {
  onOptimize?: () => void;
  onRebalance?: () => void;
}

const LoadingSkeleton: React.FC = () => (
  <Grid container spacing={3}>
    <Grid item xs={12} md={6}>
      <Skeleton variant="rectangular" height={300} />
    </Grid>
    <Grid item xs={12} md={6}>
      <Skeleton variant="rectangular" height={300} />
    </Grid>
    <Grid item xs={12}>
      <Skeleton variant="rectangular" height={200} />
    </Grid>
  </Grid>
);

const ImprovedStrategyDashboard: React.FC<StrategyDashboardProps> = ({ 
  onOptimize, 
  onRebalance 
}) => {
  const [snackbarMessage, setSnackbarMessage] = useState<string | null>(null);
  const [snackbarSeverity, setSnackbarSeverity] = useState<'success' | 'error' | 'info'>('info');

  // Use the new query-based data hooks
  const {
    bundleStats,
    strategyAllocations,
    yieldBundle,
    totalAllocatedCapital,
    isLoading,
    isRefreshing,
    error,
    refetchAll,
  } = useComposableRWAData();

  // Use mutation hooks for actions
  const optimizeMutation = useOptimizeStrategies();
  const rebalanceMutation = useRebalanceStrategies();

  const showMessage = (message: string, severity: 'success' | 'error' | 'info' = 'info') => {
    setSnackbarMessage(message);
    setSnackbarSeverity(severity);
  };

  const handleOptimize = async () => {
    try {
      await optimizeMutation.mutateAsync();
      showMessage('Strategies optimized successfully!', 'success');
      onOptimize?.();
    } catch (error) {
      console.error('Optimization failed:', error);
      showMessage('Optimization failed. Please try again.', 'error');
    }
  };

  const handleRebalance = async () => {
    try {
      await rebalanceMutation.mutateAsync();
      showMessage('Strategies rebalanced successfully!', 'success');
      onRebalance?.();
    } catch (error) {
      console.error('Rebalancing failed:', error);
      showMessage('Rebalancing failed. Please try again.', 'error');
    }
  };

  const handleRefresh = () => {
    refetchAll();
    showMessage('Data refreshed', 'info');
  };

  // Prepare data for charts (with fallback for missing properties)
  const pieData = strategyAllocations.map((allocation, index) => ({
    name: `Strategy ${index + 1}`,
    value: allocation.targetAllocation || 1000,
    color: STRATEGY_COLORS[index % STRATEGY_COLORS.length],
    targetPercentage: ((allocation.targetAllocation || 0) / 10000) * 100,
  }));

  const barData = strategyAllocations.map((allocation, index) => ({
    name: `S${index + 1}`,
    current: allocation.targetAllocation || 0,
    target: allocation.maxAllocation || 0,
    color: STRATEGY_COLORS[index % STRATEGY_COLORS.length],
  }));

  // Calculate portfolio metrics
  const totalValue = parseFloat(ethers.formatEther(totalAllocatedCapital));
  const portfolioHealth = bundleStats ? 
    (bundleStats.isHealthy ? 'Healthy' : 'Moderate') : 'Unknown';

  const capitalEfficiency = bundleStats ? 
    Number(bundleStats.capitalEfficiency) / 100 : 0;

  // Error state
  if (error) {
    return (
      <Card>
        <CardContent>
          <Alert 
            severity="error" 
            action={
              <Button color="inherit" size="small" onClick={handleRefresh}>
                Retry
              </Button>
            }
          >
            Failed to load strategy data: {error}
          </Alert>
        </CardContent>
      </Card>
    );
  }

  // Loading state
  if (isLoading) {
    return <LoadingSkeleton />;
  }

  return (
    <ErrorBoundary>
      <Box>
        {/* Header with actions */}
        <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
          <Typography variant="h4" component="h2">
            Strategy Dashboard
          </Typography>
          <Box display="flex" gap={1}>
            <Tooltip title="Refresh data">
              <IconButton 
                onClick={handleRefresh} 
                disabled={isRefreshing}
                size="small"
              >
                {isRefreshing ? <CircularProgress size={20} /> : <Refresh />}
              </IconButton>
            </Tooltip>
            <Button
              variant="outlined"
              startIcon={optimizeMutation.isPending ? <CircularProgress size={16} /> : <Settings />}
              onClick={handleOptimize}
              disabled={optimizeMutation.isPending || totalValue === 0}
            >
              {optimizeMutation.isPending ? 'Optimizing...' : 'Optimize'}
            </Button>
            <Button
              variant="contained"
              startIcon={rebalanceMutation.isPending ? <CircularProgress size={16} /> : <TrendingUp />}
              onClick={handleRebalance}
              disabled={rebalanceMutation.isPending || totalValue === 0}
            >
              {rebalanceMutation.isPending ? 'Rebalancing...' : 'Rebalance'}
            </Button>
          </Box>
        </Box>

        <Grid container spacing={3}>
          {/* Portfolio Overview */}
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Portfolio Overview
                </Typography>
                <Grid container spacing={3}>
                  <Grid item xs={12} sm={3}>
                    <Box textAlign="center">
                      <Typography variant="h4" color="primary">
                        ${totalValue.toLocaleString()}
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        Total Portfolio Value
                      </Typography>
                    </Box>
                  </Grid>
                  <Grid item xs={12} sm={3}>
                    <Box textAlign="center">
                      <Typography variant="h4" color="secondary">
                        {strategyAllocations.length}
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        Active Strategies
                      </Typography>
                    </Box>
                  </Grid>
                  <Grid item xs={12} sm={3}>
                    <Box textAlign="center">
                      <Typography variant="h4">
                        {(capitalEfficiency * 100).toFixed(1)}%
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        Capital Efficiency
                      </Typography>
                    </Box>
                  </Grid>
                  <Grid item xs={12} sm={3}>
                    <Box textAlign="center" display="flex" flexDirection="column" alignItems="center">
                      <Chip
                        icon={
                          portfolioHealth === 'Healthy' ? <CheckCircle /> :
                          portfolioHealth === 'Moderate' ? <Warning /> : <Warning />
                        }
                        label={portfolioHealth}
                        color={
                          portfolioHealth === 'Healthy' ? 'success' :
                          portfolioHealth === 'Moderate' ? 'warning' : 'error'
                        }
                        variant="outlined"
                      />
                      <Typography variant="body2" color="text.secondary" mt={1}>
                        Health Status
                      </Typography>
                    </Box>
                  </Grid>
                </Grid>
              </CardContent>
            </Card>
          </Grid>

          {/* Strategy Allocation Pie Chart */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Current Allocation
                </Typography>
                {pieData.length > 0 ? (
                  <ResponsiveContainer width="100%" height={300}>
                    <PieChart>
                      <Pie
                        data={pieData}
                        cx="50%"
                        cy="50%"
                        labelLine={false}
                        label={({ name, value }) => `${name}: $${value.toFixed(0)}`}
                        outerRadius={80}
                        fill="#8884d8"
                        dataKey="value"
                      >
                        {pieData.map((entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        ))}
                      </Pie>
                      <RechartsTooltip formatter={(value: any) => [`$${Number(value).toLocaleString()}`, 'Value']} />
                    </PieChart>
                  </ResponsiveContainer>
                ) : (
                  <Box textAlign="center" py={4}>
                    <Typography variant="body2" color="text.secondary">
                      No allocation data available
                    </Typography>
                  </Box>
                )}
              </CardContent>
            </Card>
          </Grid>

          {/* Current vs Target Allocation */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Current vs Target Allocation
                </Typography>
                {barData.length > 0 ? (
                  <ResponsiveContainer width="100%" height={300}>
                    <BarChart data={barData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="name" />
                      <YAxis />
                      <RechartsTooltip formatter={(value: any) => [`$${Number(value).toLocaleString()}`, 'Value']} />
                      <Legend />
                      <Bar dataKey="current" fill="#8884d8" name="Current" />
                      <Bar dataKey="target" fill="#82ca9d" name="Target" />
                    </BarChart>
                  </ResponsiveContainer>
                ) : (
                  <Box textAlign="center" py={4}>
                    <Typography variant="body2" color="text.secondary">
                      No allocation data available
                    </Typography>
                  </Box>
                )}
              </CardContent>
            </Card>
          </Grid>

          {/* Strategy Details */}
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Strategy Performance
                </Typography>
                <Grid container spacing={2}>
                  {strategyAllocations.map((allocation, index) => (
                    <Grid item xs={12} sm={6} md={4} key={allocation.strategy || `strategy-${index}`}>
                      <Paper elevation={1} sx={{ p: 2 }}>
                        <Box display="flex" alignItems="center" mb={1}>
                          <Box
                            width={12}
                            height={12}
                            borderRadius="50%"
                            bgcolor={STRATEGY_COLORS[index % STRATEGY_COLORS.length]}
                            mr={1}
                          />
                          <Typography variant="subtitle2">
                            Strategy {index + 1}
                          </Typography>
                        </Box>
                        <Typography variant="h6">
                          ${(allocation.targetAllocation || 0).toLocaleString()}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                          Status: {allocation.isActive ? 'Active' : 'Inactive'}
                        </Typography>
                        <LinearProgress
                          variant="determinate"
                          value={Math.min((allocation.targetAllocation || 0) / Math.max(totalValue, 1) * 100, 100)}
                          sx={{ mt: 1 }}
                        />
                      </Paper>
                    </Grid>
                  ))}
                </Grid>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Snackbar for notifications */}
        <Snackbar
          open={Boolean(snackbarMessage)}
          autoHideDuration={6000}
          onClose={() => setSnackbarMessage(null)}
          anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
        >
          <Alert
            onClose={() => setSnackbarMessage(null)}
            severity={snackbarSeverity}
            sx={{ width: '100%' }}
          >
            {snackbarMessage}
          </Alert>
        </Snackbar>
      </Box>
    </ErrorBoundary>
  );
};

export default ImprovedStrategyDashboard;