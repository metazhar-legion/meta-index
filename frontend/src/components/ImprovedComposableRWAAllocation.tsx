import React, { useState, useCallback } from 'react';
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
  Snackbar,
} from '@mui/material';
import {
  AccountBalanceWallet,
  TrendingUp,
  Info,
  Refresh,
  CheckCircle,
  Warning,
  Close,
} from '@mui/icons-material';
import { ethers } from 'ethers';
import { 
  useComposableRWAData,
  useApproveUSDC,
  useAllocateCapital,
  useWithdrawCapital,
  useHarvestYield,
} from '../hooks/queries';
import { useWeb3 } from '../contexts/Web3Context';
import { ErrorBoundary } from './ErrorBoundary';

interface AllocationDialogProps {
  open: boolean;
  onClose: () => void;
  onConfirm: (amount: string) => void;
  amount: string;
  action: 'allocate' | 'withdraw';
  isLoading: boolean;
  maxAmount: string;
  currentBalance: string;
}

const AllocationDialog: React.FC<AllocationDialogProps> = ({
  open,
  onClose,
  onConfirm,
  amount,
  action,
  isLoading,
  maxAmount,
  currentBalance,
}) => {
  const formatAmount = (value: string) => {
    const num = parseFloat(value);
    return isNaN(num) ? '0' : num.toLocaleString();
  };

  return (
    <Dialog open={open} onClose={!isLoading ? onClose : undefined} maxWidth="sm" fullWidth>
      <DialogTitle>
        Confirm {action === 'allocate' ? 'Capital Allocation' : 'Capital Withdrawal'}
        {!isLoading && (
          <IconButton
            onClick={onClose}
            sx={{ position: 'absolute', right: 8, top: 8 }}
          >
            <Close />
          </IconButton>
        )}
      </DialogTitle>
      <DialogContent>
        <Grid container spacing={2} mt={1}>
          <Grid item xs={12}>
            <Alert severity={action === 'allocate' ? 'info' : 'warning'}>
              You are about to {action === 'allocate' ? 'allocate' : 'withdraw'} {' '}
              <strong>${formatAmount(ethers.formatEther(amount))}</strong> {' '}
              {action === 'allocate' ? 'to' : 'from'} the ComposableRWA system.
            </Alert>
          </Grid>
          
          <Grid item xs={6}>
            <Typography variant="body2" color="text.secondary">
              Current Balance:
            </Typography>
            <Typography variant="h6">
              ${formatAmount(ethers.formatEther(currentBalance))}
            </Typography>
          </Grid>
          
          <Grid item xs={6}>
            <Typography variant="body2" color="text.secondary">
              {action === 'allocate' ? 'Available:' : 'Max Withdrawal:'}
            </Typography>
            <Typography variant="h6">
              ${formatAmount(ethers.formatEther(maxAmount))}
            </Typography>
          </Grid>

          {action === 'allocate' && (
            <Grid item xs={12}>
              <Typography variant="body2" color="text.secondary">
                This will distribute your capital across multiple RWA exposure strategies 
                for optimal risk-adjusted returns.
              </Typography>
            </Grid>
          )}
        </Grid>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={isLoading}>
          Cancel
        </Button>
        <Button
          variant="contained"
          onClick={() => onConfirm(amount)}
          disabled={isLoading}
          startIcon={isLoading ? <CircularProgress size={16} /> : undefined}
        >
          {isLoading 
            ? (action === 'allocate' ? 'Allocating...' : 'Withdrawing...') 
            : `Confirm ${action === 'allocate' ? 'Allocation' : 'Withdrawal'}`
          }
        </Button>
      </DialogActions>
    </Dialog>
  );
};

const ImprovedComposableRWAAllocation: React.FC = () => {
  const { account, isActive } = useWeb3();
  const [allocationAmount, setAllocationAmount] = useState('');
  const [withdrawalAmount, setWithdrawalAmount] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogAction, setDialogAction] = useState<'allocate' | 'withdraw'>('allocate');
  const [snackbarMessage, setSnackbarMessage] = useState<string | null>(null);
  const [snackbarSeverity, setSnackbarSeverity] = useState<'success' | 'error' | 'info'>('info');

  // Use the new query-based data hooks
  const {
    bundleStats,
    totalAllocatedCapital,
    userUSDCBalance,
    userAllowance,
    isLoading,
    isRefreshing,
    error,
    refetchAll,
  } = useComposableRWAData();

  // Use mutation hooks
  const approveMutation = useApproveUSDC();
  const allocateMutation = useAllocateCapital();
  const withdrawMutation = useWithdrawCapital();
  const harvestMutation = useHarvestYield();

  const showMessage = (message: string, severity: 'success' | 'error' | 'info' = 'info') => {
    setSnackbarMessage(message);
    setSnackbarSeverity(severity);
  };

  const needsApproval = (amount: string): boolean => {
    if (!amount || !userAllowance) return false;
    try {
      const amountWei = ethers.parseEther(amount);
      const allowanceWei = BigInt(userAllowance);
      return amountWei > allowanceWei;
    } catch {
      return false;
    }
  };

  const handleMaxAllocation = () => {
    if (userUSDCBalance) {
      setAllocationAmount(ethers.formatEther(userUSDCBalance));
    }
  };

  const handleMaxWithdrawal = () => {
    if (totalAllocatedCapital) {
      setWithdrawalAmount(ethers.formatEther(totalAllocatedCapital));
    }
  };

  const validateAmount = (amount: string, maxAmount: string): string | null => {
    if (!amount || amount === '0') return 'Please enter an amount';
    
    try {
      const amountWei = ethers.parseEther(amount);
      const maxWei = BigInt(maxAmount);
      
      if (amountWei <= 0n) return 'Amount must be greater than 0';
      if (amountWei > maxWei) return 'Amount exceeds available balance';
      
      return null;
    } catch {
      return 'Invalid amount format';
    }
  };

  const handleAllocate = async () => {
    if (!allocationAmount) return;

    const error = validateAmount(allocationAmount, userUSDCBalance);
    if (error) {
      showMessage(error, 'error');
      return;
    }

    try {
      const amountWei = ethers.parseEther(allocationAmount);

      // Check if approval is needed
      if (needsApproval(allocationAmount)) {
        showMessage('Approving USDC spending...', 'info');
        await approveMutation.mutateAsync(amountWei.toString());
      }

      // Perform allocation
      await allocateMutation.mutateAsync(amountWei.toString());
      
      showMessage(`Successfully allocated $${parseFloat(allocationAmount).toLocaleString()}!`, 'success');
      setAllocationAmount('');
      setDialogOpen(false);
    } catch (error: any) {
      console.error('Allocation failed:', error);
      showMessage(`Allocation failed: ${error.message || 'Unknown error'}`, 'error');
    }
  };

  const handleWithdraw = async () => {
    if (!withdrawalAmount) return;

    const error = validateAmount(withdrawalAmount, totalAllocatedCapital);
    if (error) {
      showMessage(error, 'error');
      return;
    }

    try {
      const amountWei = ethers.parseEther(withdrawalAmount);
      await withdrawMutation.mutateAsync(amountWei.toString());
      
      showMessage(`Successfully withdrew $${parseFloat(withdrawalAmount).toLocaleString()}!`, 'success');
      setWithdrawalAmount('');
      setDialogOpen(false);
    } catch (error: any) {
      console.error('Withdrawal failed:', error);
      showMessage(`Withdrawal failed: ${error.message || 'Unknown error'}`, 'error');
    }
  };

  const handleHarvestYield = async () => {
    try {
      await harvestMutation.mutateAsync();
      showMessage('Yield harvested successfully!', 'success');
    } catch (error: any) {
      console.error('Yield harvest failed:', error);
      showMessage(`Yield harvest failed: ${error.message || 'Unknown error'}`, 'error');
    }
  };

  const openDialog = (action: 'allocate' | 'withdraw') => {
    setDialogAction(action);
    setDialogOpen(true);
  };

  const confirmDialogAction = (amount: string) => {
    if (dialogAction === 'allocate') {
      handleAllocate();
    } else {
      handleWithdraw();
    }
  };

  // Calculate metrics
  const portfolioValue = parseFloat(ethers.formatEther(totalAllocatedCapital));
  const availableBalance = parseFloat(ethers.formatEther(userUSDCBalance));
  const hasPortfolio = portfolioValue > 0;

  if (!isActive || !account) {
    return (
      <Card>
        <CardContent>
          <Alert severity="warning">
            Please connect your wallet to access capital allocation features.
          </Alert>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardContent>
          <Alert 
            severity="error"
            action={
              <Button color="inherit" size="small" onClick={refetchAll}>
                Retry
              </Button>
            }
          >
            Failed to load data: {error}
          </Alert>
        </CardContent>
      </Card>
    );
  }

  return (
    <ErrorBoundary>
      <Box>
        <Typography variant="h5" gutterBottom display="flex" alignItems="center">
          <AccountBalanceWallet sx={{ mr: 1 }} />
          Capital Allocation
          <Tooltip title="Refresh data">
            <IconButton 
              onClick={refetchAll} 
              disabled={isRefreshing}
              size="small"
              sx={{ ml: 1 }}
            >
              {isRefreshing ? <CircularProgress size={16} /> : <Refresh />}
            </IconButton>
          </Tooltip>
        </Typography>

        <Grid container spacing={3}>
          {/* Portfolio Overview */}
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Grid container spacing={3}>
                  <Grid item xs={12} sm={4}>
                    <Box textAlign="center">
                      <Typography variant="h4" color="primary">
                        ${portfolioValue.toLocaleString()}
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        Total Portfolio Value
                      </Typography>
                    </Box>
                  </Grid>
                  <Grid item xs={12} sm={4}>
                    <Box textAlign="center">
                      <Typography variant="h4" color="secondary">
                        ${availableBalance.toLocaleString()}
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        Available USDC Balance
                      </Typography>
                    </Box>
                  </Grid>
                  <Grid item xs={12} sm={4}>
                    <Box textAlign="center" display="flex" flexDirection="column" alignItems="center">
                      <Button
                        variant="outlined"
                        startIcon={harvestMutation.isPending ? <CircularProgress size={16} /> : <TrendingUp />}
                        onClick={handleHarvestYield}
                        disabled={harvestMutation.isPending || !hasPortfolio}
                      >
                        {harvestMutation.isPending ? 'Harvesting...' : 'Harvest Yield'}
                      </Button>
                      <Typography variant="body2" color="text.secondary" mt={1}>
                        Collect Earnings
                      </Typography>
                    </Box>
                  </Grid>
                </Grid>
              </CardContent>
            </Card>
          </Grid>

          {/* Allocation Section */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Allocate Capital
                </Typography>
                <Typography variant="body2" color="text.secondary" paragraph>
                  Deposit USDC to start earning yield through our multi-strategy RWA exposure system.
                </Typography>

                <TextField
                  fullWidth
                  label="Allocation Amount"
                  value={allocationAmount}
                  onChange={(e) => setAllocationAmount(e.target.value)}
                  type="number"
                  InputProps={{
                    startAdornment: <InputAdornment position="start">$</InputAdornment>,
                    endAdornment: (
                      <InputAdornment position="end">
                        <Button size="small" onClick={handleMaxAllocation}>
                          Max
                        </Button>
                      </InputAdornment>
                    ),
                  }}
                  sx={{ mb: 2 }}
                  disabled={isLoading}
                />

                <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
                  <Typography variant="body2" color="text.secondary">
                    Available: ${availableBalance.toLocaleString()} USDC
                  </Typography>
                  {needsApproval(allocationAmount) && (
                    <Chip 
                      label="Approval Required" 
                      color="warning" 
                      size="small"
                      icon={<Warning />}
                    />
                  )}
                </Box>

                <Button
                  fullWidth
                  variant="contained"
                  size="large"
                  onClick={() => openDialog('allocate')}
                  disabled={
                    !allocationAmount || 
                    parseFloat(allocationAmount) <= 0 || 
                    parseFloat(allocationAmount) > availableBalance ||
                    isLoading
                  }
                  startIcon={<TrendingUp />}
                >
                  Allocate Capital
                </Button>
              </CardContent>
            </Card>
          </Grid>

          {/* Withdrawal Section */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Withdraw Capital
                </Typography>
                <Typography variant="body2" color="text.secondary" paragraph>
                  Withdraw your capital from the RWA exposure strategies back to USDC.
                </Typography>

                <TextField
                  fullWidth
                  label="Withdrawal Amount"
                  value={withdrawalAmount}
                  onChange={(e) => setWithdrawalAmount(e.target.value)}
                  type="number"
                  InputProps={{
                    startAdornment: <InputAdornment position="start">$</InputAdornment>,
                    endAdornment: (
                      <InputAdornment position="end">
                        <Button size="small" onClick={handleMaxWithdrawal} disabled={!hasPortfolio}>
                          Max
                        </Button>
                      </InputAdornment>
                    ),
                  }}
                  sx={{ mb: 2 }}
                  disabled={isLoading || !hasPortfolio}
                />

                <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
                  <Typography variant="body2" color="text.secondary">
                    Portfolio Value: ${portfolioValue.toLocaleString()}
                  </Typography>
                  {hasPortfolio && (
                    <Chip 
                      label="Available" 
                      color="success" 
                      size="small"
                      icon={<CheckCircle />}
                    />
                  )}
                </Box>

                <Button
                  fullWidth
                  variant="outlined"
                  size="large"
                  onClick={() => openDialog('withdraw')}
                  disabled={
                    !hasPortfolio ||
                    !withdrawalAmount || 
                    parseFloat(withdrawalAmount) <= 0 || 
                    parseFloat(withdrawalAmount) > portfolioValue ||
                    isLoading
                  }
                  startIcon={<AccountBalanceWallet />}
                >
                  Withdraw Capital
                </Button>
              </CardContent>
            </Card>
          </Grid>

          {/* Status Information */}
          {bundleStats && (
            <Grid item xs={12}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    System Status
                  </Typography>
                  <Grid container spacing={2}>
                    <Grid item xs={12} sm={6} md={3}>
                      <Typography variant="body2" color="text.secondary">
                        Capital Efficiency
                      </Typography>
                      <Box display="flex" alignItems="center" gap={1}>
                        <LinearProgress 
                          variant="determinate" 
                          value={Number(bundleStats.capitalEfficiency)} 
                          sx={{ flexGrow: 1 }}
                        />
                        <Typography variant="body2">
                          {Number(bundleStats.capitalEfficiency)}%
                        </Typography>
                      </Box>
                    </Grid>
                    <Grid item xs={12} sm={6} md={3}>
                      <Typography variant="body2" color="text.secondary">
                        Total System Value
                      </Typography>
                      <Typography variant="h6">
                        ${parseFloat(ethers.formatEther(bundleStats.totalValue)).toLocaleString()}
                      </Typography>
                    </Grid>
                    <Grid item xs={12} sm={6} md={3}>
                      <Typography variant="body2" color="text.secondary">
                        Health Status
                      </Typography>
                      <Chip
                        label={bundleStats.isHealthy ? 'Healthy' : 'Attention'}
                        color={bundleStats.isHealthy ? 'success' : 'warning'}
                        size="small"
                      />
                    </Grid>
                    <Grid item xs={12} sm={6} md={3}>
                      <Typography variant="body2" color="text.secondary">
                        Last Update
                      </Typography>
                      <Typography variant="body2">
                        {new Date().toLocaleTimeString()}
                      </Typography>
                    </Grid>
                  </Grid>
                </CardContent>
              </Card>
            </Grid>
          )}
        </Grid>

        {/* Confirmation Dialog */}
        <AllocationDialog
          open={dialogOpen}
          onClose={() => setDialogOpen(false)}
          onConfirm={confirmDialogAction}
          amount={dialogAction === 'allocate' ? ethers.parseEther(allocationAmount || '0').toString() : ethers.parseEther(withdrawalAmount || '0').toString()}
          action={dialogAction}
          isLoading={allocateMutation.isPending || withdrawMutation.isPending || approveMutation.isPending}
          maxAmount={dialogAction === 'allocate' ? userUSDCBalance : totalAllocatedCapital}
          currentBalance={dialogAction === 'allocate' ? userUSDCBalance : totalAllocatedCapital}
        />

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

export default ImprovedComposableRWAAllocation;