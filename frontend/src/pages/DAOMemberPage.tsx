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
  CircularProgress,
  Divider,
  Paper
} from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts } from '../hooks/useContracts';
import TokenList from '../components/TokenList';

const DAOMemberPage: React.FC = () => {
  const { account, isActive } = useWeb3();
  const { registryContract, indexTokens, isLoading: contractsLoading } = useContracts();
  
  const [tokenAddress, setTokenAddress] = useState('');
  const [tokenWeight, setTokenWeight] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const handleTokenAddressChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setTokenAddress(e.target.value);
  };

  const handleTokenWeightChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setTokenWeight(e.target.value);
  };

  const handleAddToken = async () => {
    if (!registryContract || !account || !tokenAddress || !tokenWeight) {
      setError('Please fill in all fields');
      return;
    }

    if (!ethers.isAddress(tokenAddress)) {
      setError('Invalid token address');
      return;
    }

    if (parseFloat(tokenWeight) <= 0) {
      setError('Weight must be greater than 0');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const weightInWei = ethers.parseEther(tokenWeight);
      const tx = await registryContract.addToken(tokenAddress, weightInWei);
      await tx.wait();
      
      setSuccess(`Successfully added token ${tokenAddress} with weight ${tokenWeight}`);
      setTokenAddress('');
      setTokenWeight('');
    } catch (err) {
      console.error('Error adding token:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleUpdateWeight = async () => {
    if (!registryContract || !account || !tokenAddress || !tokenWeight) {
      setError('Please fill in all fields');
      return;
    }

    if (!ethers.isAddress(tokenAddress)) {
      setError('Invalid token address');
      return;
    }

    if (parseFloat(tokenWeight) <= 0) {
      setError('Weight must be greater than 0');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const weightInWei = ethers.parseEther(tokenWeight);
      const tx = await registryContract.updateTokenWeight(tokenAddress, weightInWei);
      await tx.wait();
      
      setSuccess(`Successfully updated token ${tokenAddress} weight to ${tokenWeight}`);
      setTokenAddress('');
      setTokenWeight('');
    } catch (err) {
      console.error('Error updating token weight:', err);
      setError('Transaction failed. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRemoveToken = async () => {
    if (!registryContract || !account || !tokenAddress) {
      setError('Please enter a token address');
      return;
    }

    if (!ethers.isAddress(tokenAddress)) {
      setError('Invalid token address');
      return;
    }

    setIsSubmitting(true);
    setError(null);
    setSuccess(null);

    try {
      const tx = await registryContract.removeToken(tokenAddress);
      await tx.wait();
      
      setSuccess(`Successfully removed token ${tokenAddress}`);
      setTokenAddress('');
      setTokenWeight('');
    } catch (err) {
      console.error('Error removing token:', err);
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
        DAO Member Dashboard
      </Typography>
      
      <TokenList 
        tokens={indexTokens} 
        isLoading={contractsLoading} 
        error={null} 
      />
      
      <Card variant="outlined" sx={{ mb: 3 }}>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            Manage Index Composition
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
          
          <Grid container spacing={2}>
            <Grid item xs={12}>
              <TextField
                fullWidth
                label="Token Address"
                variant="outlined"
                value={tokenAddress}
                onChange={handleTokenAddressChange}
                margin="normal"
                disabled={isSubmitting}
                placeholder="0x..."
              />
            </Grid>
            <Grid item xs={12}>
              <TextField
                fullWidth
                label="Token Weight"
                variant="outlined"
                type="number"
                value={tokenWeight}
                onChange={handleTokenWeightChange}
                margin="normal"
                disabled={isSubmitting}
                InputProps={{
                  inputProps: { min: 0, step: 0.01 }
                }}
              />
            </Grid>
            <Grid item xs={12}>
              <Box display="flex" gap={2}>
                <Button
                  variant="contained"
                  color="primary"
                  onClick={handleAddToken}
                  disabled={contractsLoading || isSubmitting || !tokenAddress || !tokenWeight}
                >
                  {isSubmitting ? <CircularProgress size={24} /> : 'Add Token'}
                </Button>
                <Button
                  variant="contained"
                  color="secondary"
                  onClick={handleUpdateWeight}
                  disabled={contractsLoading || isSubmitting || !tokenAddress || !tokenWeight}
                >
                  Update Weight
                </Button>
                <Button
                  variant="outlined"
                  color="error"
                  onClick={handleRemoveToken}
                  disabled={contractsLoading || isSubmitting || !tokenAddress}
                >
                  Remove Token
                </Button>
              </Box>
            </Grid>
          </Grid>
        </CardContent>
      </Card>
      
      <Paper variant="outlined" sx={{ p: 2, bgcolor: 'background.paper', borderRadius: 2 }}>
        <Typography variant="subtitle1" gutterBottom>
          DAO Governance Features
        </Typography>
        <Typography variant="body2" color="text.secondary">
          The following features are planned for future implementation:
        </Typography>
        <Box component="ul" sx={{ pl: 2, mt: 1 }}>
          <Box component="li">
            <Typography variant="body2" color="text.secondary">
              Proposal creation and voting
            </Typography>
          </Box>
          <Box component="li">
            <Typography variant="body2" color="text.secondary">
              Treasury management
            </Typography>
          </Box>
          <Box component="li">
            <Typography variant="body2" color="text.secondary">
              Cross-chain asset governance
            </Typography>
          </Box>
        </Box>
      </Paper>
    </Box>
  );
};

export default DAOMemberPage;
