import React, { useState } from 'react';
import {
  Box,
  Tabs,
  Tab,
  Typography,
  Paper,
  Alert,
  Fade,
  CircularProgress,
  Container,
} from '@mui/material';
import {
  Dashboard,
  AccountBalance,
  Analytics,
  Settings,
  Info,
} from '@mui/icons-material';
import { useWeb3 } from '../contexts/Web3Context';
import { useComposableRWAData } from '../hooks/queries';
import { ErrorBoundary } from '../components/ErrorBoundary';
import ImprovedStrategyDashboard from '../components/ImprovedStrategyDashboard';
import ImprovedComposableRWAAllocation from '../components/ImprovedComposableRWAAllocation';

// Tab panel component
interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

const TabPanel: React.FC<TabPanelProps> = ({ children, value, index }) => {
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`composable-rwa-tabpanel-${index}`}
      aria-labelledby={`composable-rwa-tab-${index}`}
    >
      {value === index && (
        <Fade in={value === index} timeout={300}>
          <Box sx={{ py: 3 }}>
            {children}
          </Box>
        </Fade>
      )}
    </div>
  );
};

// Loading component
const LoadingView: React.FC = () => (
  <Box
    sx={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: '60vh',
      gap: 2,
    }}
  >
    <CircularProgress size={60} />
    <Typography variant="h6" color="text.secondary">
      Loading ComposableRWA System...
    </Typography>
    <Typography variant="body2" color="text.secondary">
      Fetching latest data from blockchain
    </Typography>
  </Box>
);

// System status component
const SystemStatus: React.FC = () => {
  const { bundleStats, totalAllocatedCapital, isLoading, error } = useComposableRWAData();

  if (isLoading) return <CircularProgress size={20} />;
  if (error) return <Alert severity="error" sx={{ mt: 2 }}>System Status: Error</Alert>;
  
  const totalValue = parseFloat((parseFloat(totalAllocatedCapital) / 1e18).toFixed(2));
  const isActive = totalValue > 0;

  return (
    <Alert 
      severity={isActive ? "success" : "info"} 
      sx={{ mt: 2, mb: 2 }}
      icon={<Info />}
    >
      <Typography variant="body2">
        <strong>System Status:</strong> {isActive ? "Active" : "Standby"} | 
        <strong> Portfolio Value:</strong> ${totalValue.toLocaleString()} | 
        <strong> Last Update:</strong> {new Date().toLocaleTimeString()}
      </Typography>
    </Alert>
  );
};

const ImprovedComposableRWAPage: React.FC = () => {
  const { account, isActive, isLoading } = useWeb3();
  const [tabValue, setTabValue] = useState(0);
  const { isLoading: dataLoading } = useComposableRWAData();

  const handleTabChange = (event: React.SyntheticEvent, newValue: number) => {
    setTabValue(newValue);
  };

  // Show connecting state
  if (isLoading) {
    return (
      <Container maxWidth="lg">
        <LoadingView />
      </Container>
    );
  }

  // Show wallet connection prompt
  if (!isActive || !account) {
    return (
      <Container maxWidth="lg">
        <Paper sx={{ p: 4, mt: 4, textAlign: 'center' }}>
          <Typography variant="h5" gutterBottom>
            Connect Your Wallet
          </Typography>
          <Typography variant="body1" color="text.secondary" paragraph>
            Please connect your wallet to access the ComposableRWA multi-strategy platform.
          </Typography>
          <Alert severity="info" sx={{ mt: 2 }}>
            Connect to start managing your RWA exposure across multiple strategies with advanced optimization.
          </Alert>
        </Paper>
      </Container>
    );
  }

  return (
    <ErrorBoundary>
      <Container maxWidth="xl">
        <Box sx={{ width: '100%' }}>
          {/* Page Header */}
          <Box sx={{ mb: 3 }}>
            <Typography variant="h4" component="h1" gutterBottom>
              ComposableRWA Multi-Strategy Platform
            </Typography>
            <Typography variant="subtitle1" color="text.secondary" paragraph>
              Manage your exposure to Real-World Assets through advanced multi-strategy optimization.
              Seamlessly allocate capital across TRS, Perpetual, and Direct Token strategies.
            </Typography>
            
            <SystemStatus />
          </Box>

          {/* Navigation Tabs */}
          <Paper sx={{ width: '100%', mb: 2 }}>
            <Tabs
              value={tabValue}
              onChange={handleTabChange}
              indicatorColor="primary"
              textColor="primary"
              variant="fullWidth"
              sx={{
                borderBottom: 1,
                borderColor: 'divider',
                '& .MuiTab-root': {
                  fontWeight: 600,
                  textTransform: 'none',
                  fontSize: '1rem',
                  minHeight: 64,
                },
              }}
            >
              <Tab
                icon={<Dashboard />}
                iconPosition="start"
                label="Strategy Dashboard"
                aria-label="strategy dashboard"
              />
              <Tab
                icon={<AccountBalance />}
                iconPosition="start"
                label="Capital Allocation"
                aria-label="capital allocation"
              />
              <Tab
                icon={<Analytics />}
                iconPosition="start"
                label="Performance Analytics"
                aria-label="performance analytics"
                disabled
              />
              <Tab
                icon={<Settings />}
                iconPosition="start"
                label="Advanced Settings"
                aria-label="advanced settings"
                disabled
              />
            </Tabs>
          </Paper>

          {/* Tab Content */}
          <Box sx={{ minHeight: '60vh' }}>
            {/* Strategy Dashboard Tab */}
            <TabPanel value={tabValue} index={0}>
              <ErrorBoundary fallback={
                <Alert severity="error">
                  Failed to load Strategy Dashboard. Please refresh the page.
                </Alert>
              }>
                {dataLoading ? (
                  <LoadingView />
                ) : (
                  <ImprovedStrategyDashboard />
                )}
              </ErrorBoundary>
            </TabPanel>

            {/* Capital Allocation Tab */}
            <TabPanel value={tabValue} index={1}>
              <ErrorBoundary fallback={
                <Alert severity="error">
                  Failed to load Capital Allocation. Please refresh the page.
                </Alert>
              }>
                {dataLoading ? (
                  <LoadingView />
                ) : (
                  <ImprovedComposableRWAAllocation />
                )}
              </ErrorBoundary>
            </TabPanel>

            {/* Performance Analytics Tab (Coming Soon) */}
            <TabPanel value={tabValue} index={2}>
              <Paper sx={{ p: 4, textAlign: 'center' }}>
                <Analytics sx={{ fontSize: 64, color: 'text.disabled', mb: 2 }} />
                <Typography variant="h5" gutterBottom>
                  Performance Analytics
                </Typography>
                <Typography variant="body1" color="text.secondary" paragraph>
                  Advanced performance analytics and historical data visualization coming soon.
                </Typography>
                <Alert severity="info">
                  This feature is under development and will include detailed performance metrics, 
                  risk analytics, and historical comparisons across strategies.
                </Alert>
              </Paper>
            </TabPanel>

            {/* Advanced Settings Tab (Coming Soon) */}
            <TabPanel value={tabValue} index={3}>
              <Paper sx={{ p: 4, textAlign: 'center' }}>
                <Settings sx={{ fontSize: 64, color: 'text.disabled', mb: 2 }} />
                <Typography variant="h5" gutterBottom>
                  Advanced Settings
                </Typography>
                <Typography variant="body1" color="text.secondary" paragraph>
                  Fine-tune strategy parameters, risk controls, and optimization settings.
                </Typography>
                <Alert severity="info">
                  This feature will allow advanced users to customize strategy weights, 
                  risk parameters, and optimization algorithms.
                </Alert>
              </Paper>
            </TabPanel>
          </Box>

          {/* Footer Information */}
          <Box sx={{ mt: 4, mb: 2 }}>
            <Alert severity="success" variant="outlined">
              <Typography variant="body2">
                ✅ <strong>Enhanced Data Management:</strong> This interface uses React Query for improved 
                data caching, real-time updates, and error recovery. Experience faster load times and 
                better reliability.
              </Typography>
            </Alert>
          </Box>
        </Box>
      </Container>
    </ErrorBoundary>
  );
};

export default ImprovedComposableRWAPage;