import React, { useEffect, useState } from 'react';
import { Box, Card, CardContent, Typography, Grid, Skeleton, Divider } from '@mui/material';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { useContracts } from '../hooks/useContracts';

const VaultStats: React.FC = () => {
  const { account } = useWeb3();
  const { vaultContract, isLoading: contractsLoading } = useContracts();
  
  const [stats, setStats] = useState({
    totalAssets: '0',
    totalShares: '0',
    userShares: '0',
    userAssets: '0',
    sharePrice: '0',
  });
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadVaultStats = async () => {
      if (vaultContract && account) {
        setIsLoading(true);
        try {
          // Fetch vault statistics
          const [totalAssets, totalSupply, userShares] = await Promise.all([
            vaultContract.totalAssets(),
            vaultContract.totalSupply(),
            vaultContract.balanceOf(account),
          ]);

          // Calculate user's assets
          const userAssets = userShares.gt(0) && totalSupply.gt(0)
            ? userShares.mul(totalAssets).div(totalSupply)
            : ethers.BigNumber.from(0);

          // Calculate share price
          const sharePrice = totalSupply.gt(0)
            ? totalAssets.mul(ethers.utils.parseEther('1')).div(totalSupply)
            : ethers.BigNumber.from(0);

          setStats({
            totalAssets: ethers.utils.formatEther(totalAssets),
            totalShares: ethers.utils.formatEther(totalSupply),
            userShares: ethers.utils.formatEther(userShares),
            userAssets: ethers.utils.formatEther(userAssets),
            sharePrice: ethers.utils.formatEther(sharePrice),
          });
        } catch (error) {
          console.error('Error loading vault stats:', error);
        } finally {
          setIsLoading(false);
        }
      } else {
        setIsLoading(false);
      }
    };

    loadVaultStats();
  }, [vaultContract, account]);

  const isDataLoading = isLoading || contractsLoading;

  return (
    <Card variant="outlined" sx={{ mb: 3 }}>
      <CardContent>
        <Typography variant="h6" gutterBottom>
          Vault Statistics
        </Typography>
        <Grid container spacing={2}>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Total Assets
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.totalAssets).toFixed(4)}</Typography>
              )}
            </Box>
          </Grid>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Total Shares
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.totalShares).toFixed(4)}</Typography>
              )}
            </Box>
          </Grid>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Share Price
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.sharePrice).toFixed(4)}</Typography>
              )}
            </Box>
          </Grid>
          <Grid item xs={6} md={3}>
            <Box>
              <Typography variant="body2" color="text.secondary">
                Your Shares
              </Typography>
              {isDataLoading ? (
                <Skeleton width="100%" />
              ) : (
                <Typography variant="h6">{parseFloat(stats.userShares).toFixed(4)}</Typography>
              )}
            </Box>
          </Grid>
        </Grid>

        <Divider sx={{ my: 2 }} />

        <Box>
          <Typography variant="body2" color="text.secondary">
            Your Assets Value
          </Typography>
          {isDataLoading ? (
            <Skeleton width="50%" height={40} />
          ) : (
            <Typography variant="h5">{parseFloat(stats.userAssets).toFixed(4)}</Typography>
          )}
        </Box>
      </CardContent>
    </Card>
  );
};

export default VaultStats;
