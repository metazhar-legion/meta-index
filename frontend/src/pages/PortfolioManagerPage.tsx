import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  TextField,
  Button,
  Grid,
  Alert,
  CircularProgress,
  Divider,
  Paper,
  List,
  ListItem,
  ListItemText,
  ListItemSecondaryAction,
  IconButton
} from '@mui/material';
import { ethers } from 'ethers';
import RefreshIcon from '@mui/icons-material/Refresh';
import SettingsIcon from '@mui/icons-material/Settings';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts } from '../hooks/useContracts';
import VaultStats from '../components/VaultStats';
import TokenList from '../components/TokenList';

const PortfolioManagerPage: React.FC = () => {
  const { account, isActive } = useWeb3();
  const { vaultContract, indexTokens, isLoading: contractsLoading } = useContracts();
  
  const [managementFee, setManagementFee] = useState('');
  const [performanceFee, setPerformanceFee] = useState('');
  const [priceOracleAddress, setPriceOracleAddress] = useState('');
  const [dexAddress, setDexAddress] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const handleManagementFeeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setManagementFee(e.target.value);
  };

  const handlePerformanceFeeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setPerformanceFee(e.target.value);
  };

  const handlePriceOracleAddressChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setPriceOracleAddress(e.target.value);
  };

  const handleDexAddressChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setDexAddress(e.target.value);
  };

  const handleRebalance = async () => {
    if (!vaultContract || !account) {
      setError('Contract not initialized');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const tx = await vaultContract.rebalance();
      await tx.wait();  // This is fine in v6
      
      setSuccess('Successfully rebalanced the portfolio');
    } catch (err) {
      console.error('Error rebalancing:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCollectManagementFee = async () => {
    if (!vaultContract || !account) {
      setError('Contract not initialized');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const tx = await vaultContract.collectManagementFee();
      await tx.wait();  // This is fine in v6
      
      setSuccess('Successfully collected management fee');
    } catch (err) {
      console.error('Error collecting management fee:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCollectPerformanceFee = async () => {
    if (!vaultContract || !account) {
      setError('Contract not initialized');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const tx = await vaultContract.collectPerformanceFee();
      await tx.wait();  // This is fine in v6
      
      setSuccess('Successfully collected performance fee');
    } catch (err) {
      console.error('Error collecting performance fee:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSetManagementFee = async () => {
    if (!vaultContract || !account || !managementFee) {
      setError('Please enter a management fee');
      return;
    }

    const feeValue = parseFloat(managementFee);
    if (isNaN(feeValue) || feeValue < 0 || feeValue > 100) {
      setError('Management fee must be between 0 and 100');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      // Convert percentage to basis points (e.g., 2% = 200 basis points)
      const feeBasisPoints = Math.floor(feeValue * 100);
      const tx = await vaultContract.setManagementFee(feeBasisPoints);
      await tx.wait();  // This is fine in v6
      
      setSuccess(`Successfully set management fee to ${managementFee}%`);
      setManagementFee('');
    } catch (err) {
      console.error('Error setting management fee:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSetPerformanceFee = async () => {
    if (!vaultContract || !account || !performanceFee) {
      setError('Please enter a performance fee');
      return;
    }

    const feeValue = parseFloat(performanceFee);
    if (isNaN(feeValue) || feeValue < 0 || feeValue > 100) {
      setError('Performance fee must be between 0 and 100');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      // Convert percentage to basis points (e.g., 20% = 2000 basis points)
      const feeBasisPoints = Math.floor(feeValue * 100);
      const tx = await vaultContract.setPerformanceFee(feeBasisPoints);
      await tx.wait();  // This is fine in v6
      
      setSuccess(`Successfully set performance fee to ${performanceFee}%`);
      setPerformanceFee('');
    } catch (err) {
      console.error('Error setting performance fee:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSetPriceOracle = async () => {
    if (!vaultContract || !account || !priceOracleAddress) {
      setError('Please enter a price oracle address');
      return;
    }

    if (!ethers.isAddress(priceOracleAddress)) {
      setError('Invalid address');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const tx = await vaultContract.setPriceOracle(priceOracleAddress);
      await tx.wait();  // This is fine in v6
      
      setSuccess(`Successfully set price oracle to ${priceOracleAddress}`);
      setPriceOracleAddress('');
    } catch (err) {
      console.error('Error setting price oracle:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSetDEX = async () => {
    if (!vaultContract || !account || !dexAddress) {
      setError('Please enter a DEX address');
      return;
    }

    if (!ethers.isAddress(dexAddress)) {
      setError('Invalid address');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const tx = await vaultContract.setDEX(dexAddress);
      await tx.wait();  // This is fine in v6
      
      setSuccess(`Successfully set DEX to ${dexAddress}`);
      setDexAddress('');
    } catch (err) {
      console.error('Error setting DEX:', err);
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

  return (
    <Box sx={{ mt: 2 }}>
      <Typography variant="h5" gutterBottom>
        Portfolio Manager Dashboard
      </Typography>
      
      <VaultStats />
      
      <TokenList 
        tokens={indexTokens} 
        isLoading={contractsLoading} 
        error={null} 
      />
      
      <Grid container spacing={3}>
        <Grid item xs={12} md={6}>
          <Card variant="outlined" sx={{ mb: 3, height: '100%' }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Portfolio Actions
              </Typography>
              
              {error && (
                <Alert severity="error" sx={{ mb: 2 }}>
                  {error}
                </Alert>
              )}
              
              {success && (
                <Alert severity="success" sx={{ mb: 2 }}>
                  {success}
                </Alert>
              )}
              
              <List>
                <ListItem>
                  <ListItemText 
                    primary="Rebalance Portfolio" 
                    secondary="Adjust token allocations to match target weights"
                  />
                  <ListItemSecondaryAction>
                    <Button
                      variant="contained"
                      color="primary"
                      startIcon={<RefreshIcon />}
                      onClick={handleRebalance}
                      disabled={contractsLoading || isSubmitting}
                    >
                      {isSubmitting ? <CircularProgress size={24} /> : 'Rebalance'}
                    </Button>
                  </ListItemSecondaryAction>
                </ListItem>
                
                <Divider component="li" />
                
                <ListItem>
                  <ListItemText 
                    primary="Collect Management Fee" 
                    secondary="Collect accrued management fees"
                  />
                  <ListItemSecondaryAction>
                    <Button
                      variant="outlined"
                      onClick={handleCollectManagementFee}
                      disabled={contractsLoading || isSubmitting}
                    >
                      Collect
                    </Button>
                  </ListItemSecondaryAction>
                </ListItem>
                
                <Divider component="li" />
                
                <ListItem>
                  <ListItemText 
                    primary="Collect Performance Fee" 
                    secondary="Collect performance fees based on high watermark"
                  />
                  <ListItemSecondaryAction>
                    <Button
                      variant="outlined"
                      onClick={handleCollectPerformanceFee}
                      disabled={contractsLoading || isSubmitting}
                    >
                      Collect
                    </Button>
                  </ListItemSecondaryAction>
                </ListItem>
              </List>
            </CardContent>
          </Card>
        </Grid>
        
        <Grid item xs={12} md={6}>
          <Card variant="outlined" sx={{ mb: 3 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Configuration
              </Typography>
              
              <Grid container spacing={2}>
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    label="Management Fee (%)"
                    variant="outlined"
                    type="number"
                    value={managementFee}
                    onChange={handleManagementFeeChange}
                    margin="normal"
                    disabled={isSubmitting}
                    InputProps={{
                      inputProps: { min: 0, max: 100, step: 0.01 }
                    }}
                  />
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={handleSetManagementFee}
                    disabled={contractsLoading || isSubmitting || !managementFee}
                    sx={{ mt: 1 }}
                  >
                    Set Management Fee
                  </Button>
                </Grid>
                
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    label="Performance Fee (%)"
                    variant="outlined"
                    type="number"
                    value={performanceFee}
                    onChange={handlePerformanceFeeChange}
                    margin="normal"
                    disabled={isSubmitting}
                    InputProps={{
                      inputProps: { min: 0, max: 100, step: 0.01 }
                    }}
                  />
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={handleSetPerformanceFee}
                    disabled={contractsLoading || isSubmitting || !performanceFee}
                    sx={{ mt: 1 }}
                  >
                    Set Performance Fee
                  </Button>
                </Grid>
                
                <Grid item xs={12}>
                  <Divider sx={{ my: 2 }} />
                </Grid>
                
                <Grid item xs={12}>
                  <TextField
                    fullWidth
                    label="Price Oracle Address"
                    variant="outlined"
                    value={priceOracleAddress}
                    onChange={handlePriceOracleAddressChange}
                    margin="normal"
                    disabled={isSubmitting}
                    placeholder="0x..."
                  />
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={handleSetPriceOracle}
                    disabled={contractsLoading || isSubmitting || !priceOracleAddress}
                    sx={{ mt: 1 }}
                  >
                    Set Price Oracle
                  </Button>
                </Grid>
                
                <Grid item xs={12}>
                  <TextField
                    fullWidth
                    label="DEX Address"
                    variant="outlined"
                    value={dexAddress}
                    onChange={handleDexAddressChange}
                    margin="normal"
                    disabled={isSubmitting}
                    placeholder="0x..."
                  />
                  <Button
                    fullWidth
                    variant="outlined"
                    onClick={handleSetDEX}
                    disabled={contractsLoading || isSubmitting || !dexAddress}
                    sx={{ mt: 1 }}
                  >
                    Set DEX
                  </Button>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
      
      <Paper variant="outlined" sx={{ p: 2, bgcolor: 'background.paper', borderRadius: 2 }}>
        <Typography variant="subtitle1" gutterBottom>
          Advanced Features (Coming Soon)
        </Typography>
        <Typography variant="body2" color="text.secondary">
          The following features are planned for future implementation:
        </Typography>
        <Box component="ul" sx={{ pl: 2, mt: 1 }}>
          <Box component="li">
            <Typography variant="body2" color="text.secondary">
              Cross-chain asset integration
            </Typography>
          </Box>
          <Box component="li">
            <Typography variant="body2" color="text.secondary">
              Real-world asset (RWA) synthetic tokens
            </Typography>
          </Box>
          <Box component="li">
            <Typography variant="body2" color="text.secondary">
              Advanced portfolio analytics
            </Typography>
          </Box>
        </Box>
      </Paper>
    </Box>
  );
};

export default PortfolioManagerPage;
