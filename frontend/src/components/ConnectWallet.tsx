import React, { useEffect } from 'react';
import { Button, Typography, Box, CircularProgress, Chip, Tooltip, Paper, Fade } from '@mui/material';
import { useWeb3 } from '../contexts/Web3Context';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import LogoutIcon from '@mui/icons-material/Logout';
import VerifiedUserIcon from '@mui/icons-material/VerifiedUser';

const ConnectWallet: React.FC = () => {
  const { account, connect, disconnect, isActive, isLoading, chainId } = useWeb3();

  // Format address for display
  const formatAddress = (address: string) => {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
  };

  // Attempt to auto-connect on component mount
  useEffect(() => {
    // If wallet is not connected, try to connect automatically
    if (!isActive && !isLoading && localStorage.getItem('isWalletConnected') === 'true') {
      connect();
    }
  }, [isActive, isLoading, connect]);

  // Get network name based on chainId
  const getNetworkName = () => {
    switch (chainId) {
      case 1:
        return 'Ethereum';
      case 5:
        return 'Goerli';
      case 11155111:
        return 'Sepolia';
      case 31337:
        return 'Anvil';
      case 1337:
        return 'Anvil';
      default:
        return 'Unknown';
    }
  };

  return (
    <Box>
      {!isActive ? (
        <Button
          variant="contained"
          color="primary"
          onClick={connect}
          disabled={isLoading}
          size="large"
          sx={{
            borderRadius: 28,
            px: 3,
            py: 1,
            fontWeight: 'bold',
            textTransform: 'none',
            boxShadow: 3,
            '&:hover': {
              transform: 'translateY(-2px)',
              boxShadow: 6,
            },
            transition: 'all 0.2s'
          }}
          startIcon={isLoading ? <CircularProgress size={20} color="inherit" /> : <AccountBalanceWalletIcon />}
        >
          {isLoading ? 'Connecting...' : 'Connect Wallet'}
        </Button>
      ) : (
        <Fade in={isActive}>
          <Paper
            elevation={2}
            sx={{
              display: 'flex',
              alignItems: 'center',
              p: 0.5,
              pl: 2,
              borderRadius: 28,
              bgcolor: 'background.paper',
              '&:hover': {
                boxShadow: 3,
              },
              transition: 'all 0.2s'
            }}
          >
            <Tooltip title={account || ''} arrow placement="bottom">
              <Box display="flex" alignItems="center">
                <VerifiedUserIcon color="success" sx={{ mr: 1, fontSize: 16 }} />
                <Typography variant="body2" fontWeight="medium">
                  {formatAddress(account || '')}
                </Typography>
              </Box>
            </Tooltip>
            
            <Chip 
              label={getNetworkName()} 
              size="small" 
              color="primary" 
              sx={{ mx: 1, height: 24 }} 
            />
            
            <Button
              variant="contained"
              color="error"
              size="small"
              onClick={disconnect}
              startIcon={<LogoutIcon />}
              sx={{
                borderRadius: 28,
                textTransform: 'none',
                ml: 1
              }}
            >
              Disconnect
            </Button>
          </Paper>
        </Fade>
      )}
    </Box>
  );
};

export default ConnectWallet;
