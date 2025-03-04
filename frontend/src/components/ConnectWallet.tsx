import React from 'react';
import { Button, Typography, Box, CircularProgress } from '@mui/material';
import { useWeb3 } from '../contexts/Web3Context';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import LogoutIcon from '@mui/icons-material/Logout';

const ConnectWallet: React.FC = () => {
  const { account, connect, disconnect, isActive, isLoading } = useWeb3();

  // Format address for display
  const formatAddress = (address: string) => {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
  };

  return (
    <Box>
      {!isActive ? (
        <Button
          variant="contained"
          color="primary"
          onClick={connect}
          disabled={isLoading}
          startIcon={isLoading ? <CircularProgress size={20} color="inherit" /> : <AccountBalanceWalletIcon />}
        >
          {isLoading ? 'Connecting...' : 'Connect Wallet'}
        </Button>
      ) : (
        <Box display="flex" alignItems="center">
          <Typography variant="body2" sx={{ mr: 1 }}>
            {formatAddress(account || '')}
          </Typography>
          <Button
            variant="outlined"
            color="primary"
            size="small"
            onClick={disconnect}
            startIcon={<LogoutIcon />}
          >
            Disconnect
          </Button>
        </Box>
      )}
    </Box>
  );
};

export default ConnectWallet;
