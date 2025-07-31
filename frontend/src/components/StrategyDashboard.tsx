import React, { useState, useEffect } from 'react';
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
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
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
import { useComposableRWA } from '../hooks/useComposableRWA';
import { StrategyType, StrategyAllocation } from '../contracts/composableRWATypes';
import { ethers } from 'ethers';

// Color scheme for different strategy types
const STRATEGY_COLORS = {
  [StrategyType.TRS]: '#FF6B6B',
  [StrategyType.PERPETUAL]: '#4ECDC4',
  [StrategyType.DIRECT_TOKEN]: '#45B7D1',
  [StrategyType.SYNTHETIC_TOKEN]: '#96CEB4',
  [StrategyType.OPTIONS]: '#FFEAA7',
};

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

const StrategyDashboard: React.FC<StrategyDashboardProps> = ({ onOptimize, onRebalance }) => {
  const {
    bundleStats,
    strategyAllocations,
    yieldBundle,
    totalAllocatedCapital,
    isLoading,
    isRefreshing,
    error,
    refreshData,
    optimizeStrategies,
    rebalanceStrategies,
  } = useComposableRWA();

  const [optimizing, setOptimizing] = useState(false);
  const [rebalancing, setRebalancing] = useState(false);

  // Calculate total allocation percentage
  const totalAllocationPercent = strategyAllocations.reduce((sum, strategy) => sum + strategy.targetAllocation, 0) / 100;

  // Prepare data for charts
  const allocationData = strategyAllocations.map((strategy, index) => {
    const colorKeys = Object.keys(STRATEGY_COLORS) as Array<keyof typeof STRATEGY_COLORS>;
    const colorKey = colorKeys[index % colorKeys.length];
    return {
      name: `Strategy ${index + 1}`,
      value: strategy.targetAllocation / 100,
      address: strategy.strategy,
      isPrimary: strategy.isPrimary,
      isActive: strategy.isActive,
      color: STRATEGY_COLORS[colorKey],
    };
  });

  const performanceData = [
    { name: 'Total Value', value: bundleStats ? parseFloat(ethers.formatUnits(bundleStats.totalValue, 6)) : 0 },
    { name: 'Total Exposure', value: bundleStats ? parseFloat(ethers.formatUnits(bundleStats.totalExposure, 6)) : 0 },
    { name: 'Allocated Capital', value: parseFloat(ethers.formatUnits(totalAllocatedCapital, 6)) },
  ];

  const handleOptimize = async () => {
    if (optimizing) return;
    
    setOptimizing(true);
    try {
      await optimizeStrategies();
      if (onOptimize) onOptimize();
    } catch (error) {
      console.error('Error optimizing strategies:', error);
    } finally {
      setOptimizing(false);
    }
  };

  const handleRebalance = async () => {
    if (rebalancing) return;
    
    setRebalancing(true);
    try {
      await rebalanceStrategies();
      if (onRebalance) onRebalance();
    } catch (error) {
      console.error('Error rebalancing strategies:', error);
    } finally {
      setRebalancing(false);
    }
  };

  const formatCurrency = (value: string | number, decimals = 2) => {
    const num = typeof value === 'string' ? parseFloat(ethers.formatUnits(value, 6)) : value;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    }).format(num);
  };

  const formatPercentage = (value: number) => {
    return `${(value / 100).toFixed(2)}%`;
  };

  if (isLoading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="400px">
        <CircularProgress size={60} />
      </Box>
    );
  }

  return (
    <Box>
      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => {}}>
          {error}
        </Alert>
      )}

      {/* Header */}
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h4" fontWeight="bold">
          Strategy Dashboard
        </Typography>
        <Box display="flex" gap={1}>
          <Tooltip title="Refresh Data">
            <IconButton onClick={refreshData} disabled={isRefreshing}>
              <Refresh />
            </IconButton>
          </Tooltip>
          <Button
            variant="outlined"
            startIcon={optimizing ? <CircularProgress size={20} /> : <TrendingUp />}
            onClick={handleOptimize}
            disabled={optimizing || isRefreshing}
          >
            {optimizing ? 'Optimizing...' : 'Optimize'}
          </Button>
          <Button
            variant="contained"
            startIcon={rebalancing ? <CircularProgress size={20} /> : <Settings />}
            onClick={handleRebalance}
            disabled={rebalancing || isRefreshing}
          >
            {rebalancing ? 'Rebalancing...' : 'Rebalance'}
          </Button>
        </Box>
      </Box>

      {/* Key Metrics */}
      <Grid container spacing={3} mb={3}>
        <Grid item xs={12} md={3}>
          <Card>
            <CardContent>
              <Typography color="textSecondary" gutterBottom variant="body2">
                Total Value
              </Typography>
              <Typography variant="h5" fontWeight="bold">
                {bundleStats ? formatCurrency(bundleStats.totalValue) : '$0.00'}
              </Typography>
              <Box display="flex" alignItems="center" mt={1}>
                {bundleStats?.isHealthy ? (
                  <CheckCircle color="success" fontSize="small" />
                ) : (
                  <Warning color="warning" fontSize="small" />
                )}
                <Typography variant="body2" color="textSecondary" ml={0.5}>
                  {bundleStats?.isHealthy ? 'Healthy' : 'Needs Attention'}
                </Typography>
              </Box>
            </CardContent>
          </Card>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Card>
            <CardContent>
              <Typography color="textSecondary" gutterBottom variant="body2">
                Total Exposure
              </Typography>
              <Typography variant="h5" fontWeight="bold">
                {bundleStats ? formatCurrency(bundleStats.totalExposure) : '$0.00'}
              </Typography>
              <Typography variant="body2" color="textSecondary">
                Leverage: {bundleStats ? (bundleStats.currentLeverage / 100).toFixed(2) : '1.00'}x
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Card>
            <CardContent>
              <Typography color="textSecondary" gutterBottom variant="body2">
                Capital Efficiency
              </Typography>
              <Typography variant="h5" fontWeight="bold">
                {bundleStats ? formatPercentage(bundleStats.capitalEfficiency) : '0%'}
              </Typography>
              <LinearProgress
                variant="determinate"
                value={bundleStats ? bundleStats.capitalEfficiency / 100 : 0}
                sx={{ mt: 1, height: 6, borderRadius: 3 }}
              />
            </CardContent>
          </Card>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Card>
            <CardContent>
              <Typography color="textSecondary" gutterBottom variant="body2">
                Active Strategies
              </Typography>
              <Typography variant="h5" fontWeight="bold">
                {strategyAllocations.filter(s => s.isActive).length}
              </Typography>
              <Typography variant="body2" color="textSecondary">
                of {strategyAllocations.length} total
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Charts Section */}
      <Grid container spacing={3} mb={3}>
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Strategy Allocation
              </Typography>
              <Box height={300}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={allocationData}
                      cx="50%"
                      cy="50%"
                      labelLine={false}
                      label={({ name, value }) => `${name}: ${(value * 100).toFixed(1)}%`}
                      outerRadius={80}
                      fill="#8884d8"
                      dataKey="value"
                    >
                      {allocationData.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                    <RechartsTooltip formatter={(value: any) => `${(value * 100).toFixed(2)}%`} />
                  </PieChart>
                </ResponsiveContainer>
              </Box>
            </CardContent>
          </Card>
        </Grid>
        
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Performance Overview
              </Typography>
              <Box height={300}>
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={performanceData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="name" />
                    <YAxis tickFormatter={(value) => `$${(value / 1000).toFixed(0)}K`} />
                    <RechartsTooltip formatter={(value: any) => formatCurrency(value)} />
                    <Bar dataKey="value" fill="#8884d8" />
                  </BarChart>
                </ResponsiveContainer>
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Strategy Details Table */}
      <Card>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            Strategy Details
          </Typography>
          <TableContainer component={Paper} variant="outlined">
            <Table>
              <TableHead>
                <TableRow>
                  <TableCell>Strategy</TableCell>
                  <TableCell>Target Allocation</TableCell>
                  <TableCell>Max Allocation</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Type</TableCell>
                  <TableCell>Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {strategyAllocations.map((strategy, index) => (
                  <TableRow key={strategy.strategy}>
                    <TableCell>
                      <Box display="flex" alignItems="center">
                        <Box
                          width={12}
                          height={12}
                          borderRadius="50%"
                          bgcolor={allocationData[index]?.color || '#ccc'}
                          mr={1}
                        />
                        <Typography variant="body2" fontFamily="monospace">
                          {`${strategy.strategy.slice(0, 6)}...${strategy.strategy.slice(-4)}`}
                        </Typography>
                      </Box>
                    </TableCell>
                    <TableCell>
                      <Typography variant="body2">
                        {formatPercentage(strategy.targetAllocation)}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <Typography variant="body2">
                        {formatPercentage(strategy.maxAllocation)}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <Box display="flex" gap={1}>
                        <Chip
                          label={strategy.isActive ? 'Active' : 'Inactive'}
                          color={strategy.isActive ? 'success' : 'default'}
                          size="small"
                        />
                        {strategy.isPrimary && (
                          <Chip label="Primary" color="primary" size="small" />
                        )}
                      </Box>
                    </TableCell>
                    <TableCell>
                      <Typography variant="body2" color="textSecondary">
                        Strategy {index + 1}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <IconButton size="small" disabled>
                        <ShowChart />
                      </IconButton>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </CardContent>
      </Card>

      {/* Yield Bundle Information */}
      {yieldBundle && yieldBundle.isActive && (
        <Card sx={{ mt: 3 }}>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              Yield Strategies
            </Typography>
            <Grid container spacing={2}>
              {yieldBundle.strategies.map((strategy, index) => (
                <Grid item xs={12} md={6} key={strategy}>
                  <Paper variant="outlined" sx={{ p: 2 }}>
                    <Typography variant="body2" fontFamily="monospace" gutterBottom>
                      {`${strategy.slice(0, 10)}...${strategy.slice(-6)}`}
                    </Typography>
                    <Typography variant="h6">
                      {formatPercentage(yieldBundle.allocations[index])}
                    </Typography>
                    <LinearProgress
                      variant="determinate"
                      value={yieldBundle.allocations[index] / 100}
                      sx={{ mt: 1 }}
                    />
                  </Paper>
                </Grid>
              ))}
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
};

export default StrategyDashboard;