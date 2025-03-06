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
          const userAssets = userShares > 0n && totalSupply > 0n
            ? (userShares * totalAssets) / totalSupply
            : 0n;

          // Calculate share price
          const sharePrice = totalSupply > 0n
            ? (totalAssets * ethers.parseEther('1')) / totalSupply
            : 0n;

          setStats({
            totalAssets: ethers.formatEther(totalAssets),
            totalShares: ethers.formatEther(totalSupply),
            userShares: ethers.formatEther(userShares),
            userAssets: ethers.formatEther(userAssets),
            sharePrice: ethers.formatEther(sharePrice),
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
