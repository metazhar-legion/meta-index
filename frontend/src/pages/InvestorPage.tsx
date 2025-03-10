import React, { useState, useMemo } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  TextField,
  Button,
  Grid,
  Alert,
  Tabs,
  Tab,
  CircularProgress
} from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts, useERC20 } from '../hooks/useContracts';
import { CONTRACT_ADDRESSES } from '../contracts/addresses';
import VaultStats from '../components/VaultStats';
import TokenList from '../components/TokenList';
import TestingTools from '../components/TestingTools';
import eventBus, { EVENTS } from '../utils/eventBus';

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

const TabPanel: React.FC<TabPanelProps> = ({ children, value, index, ...other }) => {
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`simple-tabpanel-${index}`}
      aria-labelledby={`simple-tab-${index}`}
      {...other}
    >
      {value === index && <Box sx={{ pt: 3 }}>{children}</Box>}
    </div>
  );
};

const InvestorPage: React.FC = () => {
  const { account, isActive } = useWeb3();
  const { vaultContract, indexTokens, isLoading: contractsLoading } = useContracts();
  
  // Get the underlying asset (assuming the first token in the index is the asset)
  const assetAddress = indexTokens.length > 0 ? indexTokens[0].address : ethers.ZeroAddress;
  const { tokenBalance, tokenSymbol, tokenDecimals, approveTokens, isLoading: tokenLoading } = useERC20(assetAddress);
  
  const [tabValue, setTabValue] = useState(0);
  const [amount, setAmount] = useState('');
  const [shares, setShares] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const handleTabChange = (event: React.SyntheticEvent, newValue: number) => {
    setTabValue(newValue);
    setAmount('');
    setShares('');
    setError(null);
    setSuccess(null);
  };

  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setAmount(e.target.value);
  };

  const handleSharesChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setShares(e.target.value);
  };

  const handleMaxAmount = () => {
    setAmount(tokenBalance);
  };

  // Helper function to format numbers with proper decimal places
  const formatNumber = (value: string | number, decimals: number = 4): string => {
    try {
      // Convert to number first
      const num = typeof value === 'string' ? parseFloat(value) : value;
      
      // Check if it's a valid number
      if (isNaN(num) || !isFinite(num)) {
        console.warn('Invalid number for formatting:', value);
        return '0.0000';
      }
      
      // Format with fixed decimals
      return num.toFixed(decimals);
    } catch (err) {
      console.error('Error formatting number:', err, value);
      return '0.0000';
    }
  };
  
  // Memoize formatted token balance to avoid unnecessary re-renders
  const formattedTokenBalance = useMemo(() => {
    return formatNumber(tokenBalance);
  }, [tokenBalance]);

  const handleMaxShares = async () => {
    if (vaultContract && account) {
      try {
        console.log('Getting max shares for account:', account);
        const maxShares = await vaultContract.balanceOf(account);
        console.log('Max shares raw value:', maxShares.toString());
        // Use formatUnits with 6 decimals to match the vault contract's implementation
        const formattedShares = ethers.formatUnits(maxShares, 6);
        console.log('Formatted max shares:', formattedShares);
        setShares(formattedShares);
      } catch (err) {
        console.error('Error getting max shares:', err);
      }
    }
  };

  const handleDeposit = async () => {
    if (!vaultContract || !account || !amount || parseFloat(amount) <= 0) {
      setError('Please enter a valid amount');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      console.log('Starting deposit process...');
      console.log('Account:', account);
      console.log('Amount to deposit:', amount, tokenSymbol);
      console.log('Token decimals:', tokenDecimals);
      
      // First approve the vault to spend tokens
      const amountInWei = ethers.parseUnits(amount, tokenDecimals);
      console.log('Amount in wei:', amountInWei.toString());
      
      // Use the vault address from contract addresses
      const vaultAddress = CONTRACT_ADDRESSES.VAULT;
      console.log('Vault address for approval:', vaultAddress);
      
      // Approve tokens
      console.log('Approving tokens...');
      const approved = await approveTokens(vaultAddress, amount);
      
      if (!approved) {
        throw new Error('Failed to approve tokens');
      }
      console.log('Token approval successful');
      
      // Then deposit into the vault
      console.log('Depositing into vault...');
      try {
        // Ensure we're using BigInt for the transaction
        const tx = await vaultContract.deposit(amountInWei, account);
        console.log('Deposit transaction sent:', tx.hash);
        
        console.log('Waiting for transaction confirmation...');
        const receipt = await tx.wait();
        console.log('Transaction confirmed:', receipt?.hash || 'No hash available');
        
        setSuccess(`Successfully deposited ${amount} ${tokenSymbol}`);
        setAmount('');
        
        // Emit event to notify other components that a transaction was completed
        eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
      } catch (txError) {
        console.error('Transaction error details:', txError);
        // Check for specific error messages
        const errorMessage = typeof txError === 'object' && txError !== null && 'message' in txError 
          ? String(txError.message) 
          : 'Unknown error';
        if (errorMessage.includes('user rejected')) {
          setError('Transaction was rejected by the user');
        } else if (errorMessage.includes('insufficient funds')) {
          setError('Insufficient funds for transaction');
        } else {
          setError(`Transaction failed: ${errorMessage.substring(0, 100)}...`);
        }
        throw txError; // Re-throw to be caught by the outer catch
      }
    } catch (err) {
      console.error('Error in deposit process:', err);
      if (!error) { // Only set error if not already set by inner catch
        setError('Transaction failed. Please try again.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleWithdraw = async () => {
    if (!vaultContract || !account || !shares || parseFloat(shares) <= 0) {
      setError('Please enter a valid amount of shares');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      console.log('Starting withdrawal process...');
      console.log('Account:', account);
      console.log('Shares to redeem:', shares);
      
      // Convert shares to wei (6 decimals to match the vault contract's implementation)
      const sharesInWei = ethers.parseUnits(shares, 6);
      console.log('Shares in wei:', sharesInWei.toString());
      
      console.log('Redeeming shares...');
      try {
        // Call the redeem function with proper parameters
        const tx = await vaultContract.redeem(sharesInWei, account, account);
        console.log('Redeem transaction sent:', tx.hash);
        
        console.log('Waiting for transaction confirmation...');
        const receipt = await tx.wait();
        console.log('Transaction confirmed:', receipt?.hash || 'No hash available');
        
        setSuccess(`Successfully redeemed ${shares} shares`);
        setShares('');
        
        // Emit event to notify other components that a transaction was completed
        eventBus.emit(EVENTS.VAULT_TRANSACTION_COMPLETED);
      } catch (txError) {
        console.error('Transaction error details:', txError);
        // Check for specific error messages
        const errorMessage = typeof txError === 'object' && txError !== null && 'message' in txError 
          ? String(txError.message) 
          : 'Unknown error';
        if (errorMessage.includes('user rejected')) {
          setError('Transaction was rejected by the user');
        } else if (errorMessage.includes('insufficient')) {
          setError('Insufficient shares for redemption');
        } else {
          setError(`Transaction failed: ${errorMessage.substring(0, 100)}...`);
        }
        throw txError; // Re-throw to be caught by the outer catch
      }
    } catch (err) {
      console.error('Error in withdrawal process:', err);
      if (!error) { // Only set error if not already set by inner catch
        setError('Transaction failed. Please try again.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isActive) {
    return (
      <Box sx={{ mt: 4, textAlign: 'center' }}>
        <Typography variant="h6">Please connect your wallet to continue</Typography>
      </Box>
    );
  }

  const isLoading = contractsLoading || tokenLoading;

  return (
    <Box sx={{ mt: 2 }}>
      <Typography variant="h5" gutterBottom>
        Investor Dashboard
      </Typography>
      
      <VaultStats />
      
      <TokenList 
        tokens={indexTokens} 
        isLoading={contractsLoading} 
        error={null} 
      />
      
      <Card variant="outlined">
        <CardContent>
          <Tabs value={tabValue} onChange={handleTabChange} aria-label="investment actions">
            <Tab label="Deposit" />
            <Tab label="Withdraw" />
          </Tabs>
          
          {error && (
            <Alert severity="error" sx={{ mt: 2 }}>
              {error}
            </Alert>
          )}
          
          {success && (
            <Alert severity="success" sx={{ mt: 2 }}>
              {success}
            </Alert>
          )}
          
          <TabPanel value={tabValue} index={0}>
            <Grid container spacing={2}>
              <Grid item xs={12}>
                <Box display="flex" alignItems="center" justifyContent="space-between">
                  <Typography variant="body2">
                    Balance: {isLoading ? <CircularProgress size={12} /> : `${formattedTokenBalance} ${tokenSymbol}`}
                  </Typography>
                  <Button size="small" onClick={handleMaxAmount} disabled={isLoading}>
                    Max
                  </Button>
                </Box>
                <TextField
                  fullWidth
                  label={`Amount (${tokenSymbol})`}
                  variant="outlined"
                  type="number"
                  value={amount}
                  onChange={handleAmountChange}
                  margin="normal"
                  disabled={isLoading || isSubmitting}
                  InputProps={{
                    inputProps: { min: 0, step: 0.000001 }
                  }}
                />
              </Grid>
              <Grid item xs={12}>
                <Button
                  fullWidth
                  variant="contained"
                  color="primary"
                  onClick={handleDeposit}
                  disabled={isLoading || isSubmitting || !amount || parseFloat(amount) <= 0}
                >
                  {isSubmitting ? <CircularProgress size={24} /> : 'Deposit'}
                </Button>
              </Grid>
            </Grid>
          </TabPanel>
          
          <TabPanel value={tabValue} index={1}>
            <Grid container spacing={2}>
              <Grid item xs={12}>
                <Box display="flex" alignItems="center" justifyContent="space-between">
                  <Typography variant="body2">
                    Shares: {isLoading ? <CircularProgress size={12} /> : formatNumber(shares || '0', 2)}
                  </Typography>
                  <Button size="small" onClick={handleMaxShares} disabled={isLoading}>
                    Max
                  </Button>
                </Box>
                <TextField
                  fullWidth
                  label="Shares to Redeem"
                  variant="outlined"
                  type="number"
                  value={shares}
                  onChange={handleSharesChange}
                  margin="normal"
                  disabled={isLoading || isSubmitting}
                  InputProps={{
                    inputProps: { min: 0, step: 0.000001 }
                  }}
                />
              </Grid>
              <Grid item xs={12}>
                <Button
                  fullWidth
                  variant="contained"
                  color="primary"
                  onClick={handleWithdraw}
                  disabled={isLoading || isSubmitting || !shares || parseFloat(shares) <= 0}
                >
                  {isSubmitting ? <CircularProgress size={24} /> : 'Withdraw'}
                </Button>
              </Grid>
            </Grid>
          </TabPanel>
        </CardContent>
      </Card>
      
      {/* Testing Tools Section */}
      {process.env.NODE_ENV === 'development' && (
        <TestingTools />
      )}
    </Box>
  );
};

export default InvestorPage;
