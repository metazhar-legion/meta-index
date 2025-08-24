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
  Divider,
  Alert
} from '@mui/material';
import AccountBalanceWalletIcon from '@mui/icons-material/AccountBalanceWallet';
import PieChartIcon from '@mui/icons-material/PieChart';
import ShowChartIcon from '@mui/icons-material/ShowChart';
import { Web3ReactProvider } from '@web3-react/core';
import { Web3ContextProvider, useWeb3, UserRole } from './contexts/Web3Context';
import QueryProvider from './contexts/QueryProvider';
import { ErrorBoundary } from './components/ErrorBoundary';
import theme from './theme/theme';
import ConnectWallet from './components/ConnectWallet';
import UserRoleSelector from './components/UserRoleSelector';
import InvestorPage from './pages/InvestorPage';
import DAOMemberPage from './pages/DAOMemberPage';
import PortfolioManagerPage from './pages/PortfolioManagerPage';
import ComposableRWAPage from './pages/ComposableRWAPage';

// Import connectors
import { connectors } from './connectors';

// Import improved components
import ImprovedComposableRWAPage from './pages/ImprovedComposableRWAPage';

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
            <Typography variant="h3" component="h1" gutterBottom sx={{ fontWeight: 'bold' }}>
              ComposableRWA Platform
            </Typography>
            <Typography variant="h5" sx={{ mb: 3, opacity: 0.9 }}>
              Advanced Multi-Strategy Real-World Asset Exposure
            </Typography>
            <Typography variant="body1" sx={{ maxWidth: '600px', mb: 4, opacity: 0.8 }}>
              Experience institutional-grade RWA exposure through our innovative multi-strategy approach. 
              Combine TRS, Perpetual Trading, and Direct Token strategies for optimal risk-adjusted returns.
            </Typography>
          </Box>

          {/* Features Section */}
          <Container maxWidth="md">
            <Box sx={{ display: 'flex', justifyContent: 'space-around', flexWrap: 'wrap', gap: 3 }}>
              <Paper sx={{ p: 3, textAlign: 'center', minWidth: 200 }}>
                <AccountBalanceWalletIcon color="primary" sx={{ fontSize: 48, mb: 2 }} />
                <Typography variant="h6" gutterBottom>Multi-Strategy</Typography>
                <Typography variant="body2" color="text.secondary">
                  TRS, Perpetual, and Direct Token strategies
                </Typography>
              </Paper>
              
              <Paper sx={{ p: 3, textAlign: 'center', minWidth: 200 }}>
                <PieChartIcon color="secondary" sx={{ fontSize: 48, mb: 2 }} />
                <Typography variant="h6" gutterBottom>Smart Optimization</Typography>
                <Typography variant="body2" color="text.secondary">
                  Real-time cost analysis and automatic rebalancing
                </Typography>
              </Paper>
              
              <Paper sx={{ p: 3, textAlign: 'center', minWidth: 200 }}>
                <ShowChartIcon color="success" sx={{ fontSize: 48, mb: 2 }} />
                <Typography variant="h6" gutterBottom>Risk Management</Typography>
                <Typography variant="body2" color="text.secondary">
                  Advanced diversification and concentration controls
                </Typography>
              </Paper>
            </Box>
          </Container>
        </Box>
      );
    }

    switch (userRole) {
      case UserRole.COMPOSABLE_RWA_USER:
        // Use the improved ComposableRWA page with React Query
        return <ImprovedComposableRWAPage />;
      case UserRole.INVESTOR:
        return <InvestorPage />;
      case UserRole.DAO_MEMBER:
        return <DAOMemberPage />;
      case UserRole.PORTFOLIO_MANAGER:
        return <PortfolioManagerPage />;
      default:
        return <ComposableRWAPage />;
    }
  };

  return (
    <Container maxWidth="xl" sx={{ mt: 2, mb: 4 }}>
      <ErrorBoundary>
        {renderContent()}
      </ErrorBoundary>
    </Container>
  );
};

// App Header Component
const AppHeader: React.FC = () => {
  const { userRole } = useWeb3();
  
  const getRoleDisplayName = (role: UserRole) => {
    switch (role) {
      case UserRole.COMPOSABLE_RWA_USER:
        return 'ComposableRWA User';
      case UserRole.INVESTOR:
        return 'Investor';
      case UserRole.DAO_MEMBER:
        return 'DAO Member';
      case UserRole.PORTFOLIO_MANAGER:
        return 'Portfolio Manager';
      default:
        return 'Guest';
    }
  };

  return (
    <AppBar position="static" elevation={0} sx={{ backgroundColor: 'white', borderBottom: 1, borderColor: 'divider' }}>
      <Toolbar sx={{ justifyContent: 'space-between' }}>
        <Box sx={{ display: 'flex', alignItems: 'center' }}>
          <AccountBalanceWalletIcon sx={{ mr: 2, color: 'primary.main' }} />
          <Typography variant="h6" component="div" sx={{ color: 'text.primary', fontWeight: 'bold' }}>
            Web3 Index Fund
          </Typography>
          <Divider orientation="vertical" flexItem sx={{ mx: 2 }} />
          <Typography variant="body2" sx={{ color: 'text.secondary' }}>
            {getRoleDisplayName(userRole)}
          </Typography>
        </Box>
        
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
          <UserRoleSelector />
          <ConnectWallet />
        </Box>
      </Toolbar>
    </AppBar>
  );
};

// Enhanced notice about frontend improvements
const ImprovementNotice: React.FC = () => {
  return (
    <Container maxWidth="xl" sx={{ mt: 2 }}>
      <Alert severity="info" sx={{ mb: 2 }}>
        <Typography variant="body2">
          🚀 <strong>Enhanced with React Query:</strong> This version features improved data loading, 
          caching, and error handling for better performance and user experience.
        </Typography>
      </Alert>
    </Container>
  );
};

// Root App Component
const App: React.FC = () => {
  return (
    <ErrorBoundary>
      <Web3ReactProvider connectors={connectors}>
        <Web3ContextProvider>
          <QueryProvider>
            <ThemeProvider theme={theme}>
              <CssBaseline />
              <Box sx={{ minHeight: '100vh', backgroundColor: 'grey.50' }}>
                <AppHeader />
                <ImprovementNotice />
                <MainContent />
              </Box>
            </ThemeProvider>
          </QueryProvider>
        </Web3ContextProvider>
      </Web3ReactProvider>
    </ErrorBoundary>
  );
};

export default App;