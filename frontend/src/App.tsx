import React from 'react';
import {
  CssBaseline,
  ThemeProvider,
  Container,
  Box,
  AppBar,
  Toolbar,
  Typography,
  Paper,
  Divider
} from '@mui/material';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import PieChartIcon from '@mui/icons-material/PieChart';
import ShowChartIcon from '@mui/icons-material/ShowChart';
import { Web3ReactProvider } from '@web3-react/core';
import { Web3ContextProvider, useWeb3, UserRole } from './contexts/Web3Context';
import theme from './theme/theme';
import ConnectWallet from './components/ConnectWallet';
import UserRoleSelector from './components/UserRoleSelector';
import InvestorPage from './pages/InvestorPage';
import DAOMemberPage from './pages/DAOMemberPage';
import PortfolioManagerPage from './pages/PortfolioManagerPage';
import ComposableRWAPage from './pages/ComposableRWAPage';

// Import connectors
import { connectors } from './connectors';

// Main content component
const MainContent: React.FC = () => {
  const { userRole, isActive } = useWeb3();

  // Render different pages based on user role
  const renderContent = () => {
    if (!isActive) {
      return (
        <Box sx={{ 
          mt: 4, 
          display: 'flex', 
          flexDirection: 'column',
          alignItems: 'center',
          height: '80vh'
        }}>
          {/* Hero Section */}
          <Box 
            sx={{
              width: '100%',
              background: 'linear-gradient(45deg, #2196F3 30%, #21CBF3 90%)',
              color: 'white',
              py: 6,
              borderRadius: 2,
              mb: 4,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              textAlign: 'center',
              boxShadow: 3
            }}
          >
            <Typography variant="h3" fontWeight="bold" gutterBottom>
              Web3 Index Fund
            </Typography>
            <Typography variant="h6" sx={{ maxWidth: 700, mb: 4 }}>
              Advanced composable RWA exposure with multi-strategy optimization and intelligent rebalancing
            </Typography>
            <Box sx={{ mt: 2, display: 'flex', justifyContent: 'center' }}>
              <ConnectWallet />
            </Box>
          </Box>
          
          {/* Features Section */}
          <Box sx={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 3, mt: 4 }}>
            <Paper
              elevation={2}
              sx={{
                p: 3,
                width: 280,
                height: 220,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                borderRadius: 2,
                transition: 'transform 0.3s, box-shadow 0.3s',
                '&:hover': {
                  transform: 'translateY(-5px)',
                  boxShadow: 6
                }
              }}
            >
              <Box sx={{ 
                bgcolor: 'primary.main', 
                color: 'white', 
                p: 1, 
                borderRadius: '50%',
                mb: 2
              }}>
                <AccountBalanceWalletIcon fontSize="large" />
              </Box>
              <Typography variant="h6" gutterBottom align="center">
                Easy Investment
              </Typography>
              <Typography variant="body2" align="center" color="text.secondary">
                Deposit stablecoins and gain exposure to a diversified portfolio of digital assets
              </Typography>
            </Paper>
            
            <Paper
              elevation={2}
              sx={{
                p: 3,
                width: 280,
                height: 220,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                borderRadius: 2,
                transition: 'transform 0.3s, box-shadow 0.3s',
                '&:hover': {
                  transform: 'translateY(-5px)',
                  boxShadow: 6
                }
              }}
            >
              <Box sx={{ 
                bgcolor: 'warning.main', 
                color: 'white', 
                p: 1, 
                borderRadius: '50%',
                mb: 2
              }}>
                <PieChartIcon fontSize="large" />
              </Box>
              <Typography variant="h6" gutterBottom align="center">
                Diversified Portfolio
              </Typography>
              <Typography variant="body2" align="center" color="text.secondary">
                Gain exposure to a curated selection of top-performing digital assets
              </Typography>
            </Paper>
            
            <Paper
              elevation={2}
              sx={{
                p: 3,
                width: 280,
                height: 220,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                borderRadius: 2,
                transition: 'transform 0.3s, box-shadow 0.3s',
                '&:hover': {
                  transform: 'translateY(-5px)',
                  boxShadow: 6
                }
              }}
            >
              <Box sx={{ 
                bgcolor: 'success.main', 
                color: 'white', 
                p: 1, 
                borderRadius: '50%',
                mb: 2
              }}>
                <ShowChartIcon fontSize="large" />
              </Box>
              <Typography variant="h6" gutterBottom align="center">
                Performance Tracking
              </Typography>
              <Typography variant="body2" align="center" color="text.secondary">
                Monitor your investment performance with real-time statistics and charts
              </Typography>
            </Paper>
          </Box>
        </Box>
      );
    }

    switch (userRole) {
      case UserRole.INVESTOR:
        return <InvestorPage />;
      case UserRole.DAO_MEMBER:
        return <DAOMemberPage />;
      case UserRole.PORTFOLIO_MANAGER:
        return <PortfolioManagerPage />;
      case UserRole.COMPOSABLE_RWA_USER:
        return <ComposableRWAPage />;
      default:
        return <InvestorPage />;
    }
  };

  return (
    <Container maxWidth="lg" sx={{ mt: 2, mb: 4 }}>
      {renderContent()}
    </Container>
  );
};

// App component
function App() {
  return (
    <Web3ReactProvider connectors={connectors}>
      <Web3ContextProvider>
        <ThemeProvider theme={theme}>
          <CssBaseline />
          <Box sx={{ display: 'flex', flexDirection: 'column', minHeight: '100vh' }}>
            <AppBar position="static" color="primary" elevation={0}>
              <Toolbar>
                <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
                  Web3 Index Fund
                </Typography>
                <ConnectWallet />
              </Toolbar>
            </AppBar>
            
            <Box sx={{ px: 2 }}>
              <UserRoleSelector />
            </Box>
            
            <Box component="main" sx={{ flexGrow: 1 }}>
              <MainContent />
            </Box>
            
            <Box
              component="footer"
              sx={{
                py: 3,
                px: 2,
                mt: 'auto',
                backgroundColor: (theme) => theme.palette.background.paper,
              }}
            >
              <Container maxWidth="lg">
                <Typography variant="body2" color="text.secondary" align="center">
                  Web3 Index Fund &copy; {new Date().getFullYear()}
                </Typography>
              </Container>
            </Box>
          </Box>
        </ThemeProvider>
      </Web3ContextProvider>
    </Web3ReactProvider>
  );
}

export default App;
