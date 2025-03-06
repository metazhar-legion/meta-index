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
import { Web3ReactProvider } from '@web3-react/core';
import { Web3ContextProvider, useWeb3, UserRole } from './contexts/Web3Context';
import theme from './theme/theme';
import ConnectWallet from './components/ConnectWallet';
import UserRoleSelector from './components/UserRoleSelector';
import InvestorPage from './pages/InvestorPage';
import DAOMemberPage from './pages/DAOMemberPage';
import PortfolioManagerPage from './pages/PortfolioManagerPage';

// Import connectors
import { connectors } from './connectors';

// Main content component
const MainContent: React.FC = () => {
  const { userRole, isActive } = useWeb3();

  // Render different pages based on user role
  const renderContent = () => {
    if (!isActive) {
      return (
        <Box sx={{ mt: 8, textAlign: 'center' }}>
          <Typography variant="h4" gutterBottom>
            Web3 Index Fund
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ mb: 4 }}>
            Connect your wallet to access the decentralized index fund
          </Typography>
          <Paper
            variant="outlined"
            sx={{
              p: 4,
              maxWidth: 600,
              mx: 'auto',
              bgcolor: 'background.paper',
              borderRadius: 2,
            }}
          >
            <Typography variant="h6" gutterBottom>
              Welcome to Web3 Index Fund
            </Typography>
            <Typography variant="body2" paragraph>
              This platform allows you to invest in a basket of digital assets through a decentralized, 
              DAO-governed index fund built on ERC4626 vault standard.
            </Typography>
            <Divider sx={{ my: 2 }} />
            <Box sx={{ display: 'flex', justifyContent: 'center', mt: 2 }}>
              <ConnectWallet />
            </Box>
          </Paper>
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
