import React, { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  TextField,
  Button,
  Grid,
  Alert,
  Divider,
  Chip,
  LinearProgress,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  CircularProgress,
  InputAdornment,
  Tooltip,
  IconButton,
} from '@mui/material';
import {
  AccountBalanceWallet,
  TrendingUp,
  Info,
  Refresh,
  CheckCircle,
  Warning,
} from '@mui/icons-material';
import { ethers } from 'ethers';
import { useComposableRWA } from '../hooks/useComposableRWA';
import { useWeb3 } from '../contexts/Web3Context';

interface AllocationDialogProps {
  open: boolean;
  onClose: () => void;
  onConfirm: (amount: string) => void;
  amount: string;
  action: 'allocate' | 'withdraw';
  isLoading: boolean;
}

const AllocationDialog: React.FC<AllocationDialogProps> = ({
  open,
  onClose,
  onConfirm,
  amount,
  action,
  isLoading,
}) => {
  const formatAmount = (value: string) => {
    const num = parseFloat(ethers.formatUnits(value, 6));
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(num);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>
        Confirm {action === 'allocate' ? 'Capital Allocation' : 'Capital Withdrawal'}
      </DialogTitle>
      <DialogContent>
        <Typography variant="body1" gutterBottom>
          Are you sure you want to {action} {formatAmount(amount)}?
        </Typography>
        <Typography variant="body2" color="textSecondary">
          {action === 'allocate'
            ? 'This will distribute your capital across the active strategies according to their target allocations.'
            : 'This will withdraw capital from strategies proportionally and return USDC to your wallet.'}
        </Typography>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={isLoading}>
          Cancel
        </Button>
        <Button
          onClick={() => onConfirm(amount)}
          variant="contained"
          disabled={isLoading}
          startIcon={isLoading ? <CircularProgress size={20} /> : null}
        >
          {isLoading ? 'Processing...' : 'Confirm'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

const ComposableRWAAllocation: React.FC = () => {
  const { account } = useWeb3();
  const {
    bundleStats,
    strategyAllocations,
    totalAllocatedCapital,
    userUSDCBalance,
    userAllowance,
    isLoading,
    error,
    refreshData,
    approveUSDC,
    allocateCapital,
    withdrawCapital,
    harvestYield,
  } = useComposableRWA();

  const [allocateAmount, setAllocateAmount] = useState('');
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showDialog, setShowDialog] = useState(false);
  const [dialogAction, setDialogAction] = useState<'allocate' | 'withdraw'>('allocate');
  const [dialogAmount, setDialogAmount] = useState('');
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const formatCurrency = (value: string | number, decimals = 2) => {
    const num = typeof value === 'string' ? parseFloat(ethers.formatUnits(value, 6)) : value;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    }).format(num);
  };

  const parseInputAmount = (value: string): string => {
    try {
      const num = parseFloat(value);
      if (isNaN(num) || num <= 0) return '0';
      return ethers.parseUnits(num.toString(), 6).toString();
    } catch {
      return '0';
    }
  };

  const needsApproval = (amount: string): boolean => {
    if (!userAllowance || amount === '0') return false;
    return ethers.toBigInt(amount) > ethers.toBigInt(userAllowance);
  };

  const handleMaxAllocate = () => {
    const maxAmount = parseFloat(ethers.formatUnits(userUSDCBalance, 6));
    setAllocateAmount(maxAmount.toString());
  };

  const handleMaxWithdraw = () => {
    if (bundleStats) {
      const maxAmount = parseFloat(ethers.formatUnits(bundleStats.totalValue, 6));
      setWithdrawAmount(maxAmount.toString());
    }
  };

  const handleAllocate = async () => {
    const amount = parseInputAmount(allocateAmount);
    if (amount === '0') {
      setErrorMessage('Please enter a valid amount');
      return;
    }

    setDialogAction('allocate');
    setDialogAmount(amount);
    setShowDialog(true);
  };

  const handleWithdraw = async () => {
    const amount = parseInputAmount(withdrawAmount);
    if (amount === '0') {
      setErrorMessage('Please enter a valid amount');
      return;
    }

    setDialogAction('withdraw');
    setDialogAmount(amount);
    setShowDialog(true);
  };

  const handleConfirmTransaction = async (amount: string) => {
    setIsSubmitting(true);
    setErrorMessage(null);
    setSuccessMessage(null);

    try {
      if (dialogAction === 'allocate') {
        // Check if approval is needed
        if (needsApproval(amount)) {
          await approveUSDC(amount);
          setSuccessMessage('USDC approved successfully');
        }
        
        await allocateCapital(amount);
        setSuccessMessage(`Successfully allocated ${formatCurrency(amount)}`);
        setAllocateAmount('');
      } else {
        await withdrawCapital(amount);
        setSuccessMessage(`Successfully withdrew ${formatCurrency(amount)}`);
        setWithdrawAmount('');
      }
    } catch (error: any) {
      console.error('Transaction error:', error);
      setErrorMessage(error.message || 'Transaction failed');
    } finally {
      setIsSubmitting(false);
      setShowDialog(false);
    }
  };

  const handleHarvestYield = async () => {
    setIsSubmitting(true);
    setErrorMessage(null);
    
    try {
      await harvestYield();
      setSuccessMessage('Yield harvested successfully');
    } catch (error: any) {
      console.error('Harvest error:', error);
      setErrorMessage(error.message || 'Harvest failed');
    } finally {
      setIsSubmitting(false);
    }
  };

  const activeStrategies = strategyAllocations.filter(s => s.isActive);
  const totalAllocation = strategyAllocations.reduce((sum, s) => sum + s.targetAllocation, 0);

  return (
    <Box>
      {/* Header */}
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Typography variant="h5" fontWeight="bold">
          Capital Allocation
        </Typography>
        <Tooltip title="Refresh Data">
          <IconButton onClick={refreshData}>
            <Refresh />
          </IconButton>
        </Tooltip>
      </Box>

      {/* Alerts */}
      {successMessage && (
        <Alert severity="success" onClose={() => setSuccessMessage(null)} sx={{ mb: 2 }}>
          {successMessage}
        </Alert>
      )}
      {errorMessage && (
        <Alert severity="error" onClose={() => setErrorMessage(null)} sx={{ mb: 2 }}>
          {errorMessage}
        </Alert>
      )}
      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      <Grid container spacing={3}>
        {/* Portfolio Overview */}
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Portfolio Overview
              </Typography>
              
              <Box mb={2}>
                <Typography variant="body2" color="textSecondary">
                  Total Portfolio Value
                </Typography>
                <Typography variant="h4" fontWeight="bold">
                  {bundleStats ? formatCurrency(bundleStats.totalValue) : '$0.00'}
                </Typography>
              </Box>

              <Box mb={2}>
                <Typography variant="body2" color="textSecondary">
                  Allocated Capital
                </Typography>
                <Typography variant="h6">
                  {formatCurrency(totalAllocatedCapital)}
                </Typography>
              </Box>

              <Box mb={2}>
                <Typography variant="body2" color="textSecondary">
                  Current Leverage
                </Typography>
                <Typography variant="h6">
                  {bundleStats ? (bundleStats.currentLeverage / 100).toFixed(2) : '1.00'}x
                </Typography>
              </Box>

              <Box mb={2}>
                <Typography variant="body2" color="textSecondary">
                  Portfolio Health
                </Typography>
                <Box display="flex" alignItems="center" mt={0.5}>
                  {bundleStats?.isHealthy ? (
                    <CheckCircle color="success" fontSize="small" />
                  ) : (
                    <Warning color="warning" fontSize="small" />
                  )}
                  <Typography variant="body2" ml={0.5}>
                    {bundleStats?.isHealthy ? 'Healthy' : 'Needs Attention'}
                  </Typography>
                </Box>
              </Box>

              <Button
                fullWidth
                variant="outlined"
                startIcon={<TrendingUp />}
                onClick={handleHarvestYield}
                disabled={isSubmitting}
              >
                Harvest Yield
              </Button>
            </CardContent>
          </Card>
        </Grid>

        {/* Allocation Actions */}
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Allocate Capital
              </Typography>
              
              <Box mb={2}>
                <Typography variant="body2" color="textSecondary" gutterBottom>
                  Available USDC Balance: {formatCurrency(userUSDCBalance)}
                </Typography>
                <TextField
                  fullWidth
                  label="Amount to Allocate"
                  value={allocateAmount}
                  onChange={(e) => setAllocateAmount(e.target.value)}
                  type="number"
                  InputProps={{
                    startAdornment: <InputAdornment position="start">$</InputAdornment>,
                    endAdornment: (
                      <InputAdornment position="end">
                        <Button size="small" onClick={handleMaxAllocate}>
                          Max
                        </Button>
                      </InputAdornment>
                    ),
                  }}
                />
              </Box>

              <Button
                fullWidth
                variant="contained"
                onClick={handleAllocate}
                disabled={!allocateAmount || parseFloat(allocateAmount) <= 0 || isSubmitting}
                startIcon={<AccountBalanceWallet />}
              >
                Allocate Capital
              </Button>

              {allocateAmount && needsApproval(parseInputAmount(allocateAmount)) && (
                <Alert severity="info" sx={{ mt: 1 }}>
                  <Typography variant="body2">
                    USDC approval required before allocation
                  </Typography>
                </Alert>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Withdrawal Actions */}
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Withdraw Capital
              </Typography>
              
              <Box mb={2}>
                <Typography variant="body2" color="textSecondary" gutterBottom>
                  Available to Withdraw: {bundleStats ? formatCurrency(bundleStats.totalValue) : '$0.00'}
                </Typography>
                <TextField
                  fullWidth
                  label="Amount to Withdraw"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  type="number"
                  InputProps={{
                    startAdornment: <InputAdornment position="start">$</InputAdornment>,
                    endAdornment: (
                      <InputAdornment position="end">
                        <Button size="small" onClick={handleMaxWithdraw}>
                          Max
                        </Button>
                      </InputAdornment>
                    ),
                  }}
                />
              </Box>

              <Button
                fullWidth
                variant="outlined"
                onClick={handleWithdraw}
                disabled={!withdrawAmount || parseFloat(withdrawAmount) <= 0 || isSubmitting}
                startIcon={<TrendingUp />}
              >
                Withdraw Capital
              </Button>
            </CardContent>
          </Card>
        </Grid>

        {/* Strategy Status */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Active Strategies ({activeStrategies.length})
              </Typography>
              
              <Grid container spacing={2}>
                {strategyAllocations.map((strategy, index) => (
                  <Grid item xs={12} md={6} lg={4} key={strategy.strategy}>
                    <Card variant="outlined">
                      <CardContent>
                        <Box display="flex" justifyContent="space-between" alignItems="center" mb={1}>
                          <Typography variant="body2" fontFamily="monospace">
                            {`${strategy.strategy.slice(0, 6)}...${strategy.strategy.slice(-4)}`}
                          </Typography>
                          <Box display="flex" gap={0.5}>
                            <Chip
                              label={strategy.isActive ? 'Active' : 'Inactive'}
                              color={strategy.isActive ? 'success' : 'default'}
                              size="small"
                            />
                            {strategy.isPrimary && (
                              <Chip label="Primary" color="primary" size="small" />
                            )}
                          </Box>
                        </Box>
                        
                        <Typography variant="body2" color="textSecondary" gutterBottom>
                          Target Allocation: {(strategy.targetAllocation / 100).toFixed(1)}%
                        </Typography>
                        
                        <LinearProgress
                          variant="determinate"
                          value={Math.min(strategy.targetAllocation / totalAllocation * 100, 100)}
                          sx={{ height: 6, borderRadius: 3 }}
                        />
                        
                        <Typography variant="caption" color="textSecondary">
                          Max: {(strategy.maxAllocation / 100).toFixed(1)}%
                        </Typography>
                      </CardContent>
                    </Card>
                  </Grid>
                ))}
              </Grid>

              {strategyAllocations.length === 0 && (
                <Alert severity="info" icon={<Info />}>
                  No strategies configured. Contact the portfolio manager to add strategies.
                </Alert>
              )}
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Confirmation Dialog */}
      <AllocationDialog
        open={showDialog}
        onClose={() => setShowDialog(false)}
        onConfirm={handleConfirmTransaction}
        amount={dialogAmount}
        action={dialogAction}
        isLoading={isSubmitting}
      />
    </Box>
  );
};

export default ComposableRWAAllocation;