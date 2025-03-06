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
  Tabs,
  Tab,
  CircularProgress,
  Divider
} from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts, useERC20 } from '../hooks/useContracts';
import VaultStats from '../components/VaultStats';
import TokenList from '../components/TokenList';

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
  const assetAddress = indexTokens.length > 0 ? indexTokens[0].address : ethers.constants.AddressZero;
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

  const handleMaxShares = async () => {
    if (vaultContract && account) {
      try {
        const maxShares = await vaultContract.balanceOf(account);
        setShares(ethers.formatEther(maxShares));
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
      // First approve the vault to spend tokens
      const amountInWei = ethers.parseUnits(amount, tokenDecimals);
      const approved = await approveTokens(vaultContract.address, amount);
      
      if (!approved) {
        throw new Error('Failed to approve tokens');
      }
      
      // Then deposit into the vault
      const tx = await vaultContract.deposit(amountInWei, account);
      await tx.wait();
      
      setSuccess(`Successfully deposited ${amount} ${tokenSymbol}`);
      setAmount('');
    } catch (err) {
      console.error('Error depositing:', err);
      setError('Transaction failed. Please try again.');
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
      const sharesInWei = ethers.parseEther(shares);
      const tx = await vaultContract.redeem(sharesInWei, account, account);
      await tx.wait();
      
      setSuccess(`Successfully redeemed ${shares} shares`);
      setShares('');
    } catch (err) {
      console.error('Error withdrawing:', err);
      setError('Transaction failed. Please try again.');
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
                    Balance: {isLoading ? <CircularProgress size={12} /> : `${parseFloat(tokenBalance).toFixed(4)} ${tokenSymbol}`}
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
                    Shares: {isLoading ? <CircularProgress size={12} /> : parseFloat(vaultContract ? ethers.formatEther(await vaultContract.balanceOf(account)) : '0').toFixed(4)}
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
    </Box>
  );
};

export default InvestorPage;
