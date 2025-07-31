import React, { useState } from 'react';
import {
  Box,
  Container,
  Typography,
  Tabs,
  Tab,
  Card,
  CardContent,
  Alert,
  CircularProgress,
  Fade,
} from '@mui/material';
import {
  Dashboard as DashboardIcon,
  AccountBalanceWallet as WalletIcon,
  ShowChart as ChartIcon,
  Settings as SettingsIcon,
} from '@mui/icons-material';
import { useWeb3 } from '../contexts/Web3Context';
import { useComposableRWA } from '../hooks/useComposableRWA';
import StrategyDashboard from '../components/StrategyDashboard';
import ComposableRWAAllocation from '../components/ComposableRWAAllocation';

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

const TabPanel: React.FC<TabPanelProps> = ({ children, value, index, ...other }) => {
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`composable-rwa-tabpanel-${index}`}
      aria-labelledby={`composable-rwa-tab-${index}`}
      {...other}
    >
      {value === index && (
        <Fade in={true} timeout={300}>
          <Box sx={{ py: 3 }}>
            {children}
          </Box>
        </Fade>
      )}
    </div>
  );
};

const a11yProps = (index: number) => {
  return {
    id: `composable-rwa-tab-${index}`,
    'aria-controls': `composable-rwa-tabpanel-${index}`,
  };
};

const ComposableRWAPage: React.FC = () => {
  const { account, isActive } = useWeb3();
  const {
    bundleStats,
    strategyAllocations,
    totalAllocatedCapital,
    isLoading,
    error,
    refreshData,
  } = useComposableRWA();

  const [tabValue, setTabValue] = useState(0);

  const handleTabChange = (event: React.SyntheticEvent, newValue: number) => {
    setTabValue(newValue);
  };

  const formatCurrency = (value: string) => {
    const num = parseFloat(value) / 1e6; // Assuming 6 decimals for USDC
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(num);
  };

  if (!isActive || !account) {
    return (
      <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
        <Card>
          <CardContent sx={{ textAlign: 'center', py: 6 }}>
            <Typography variant="h5" gutterBottom>
              Connect Your Wallet
            </Typography>
            <Typography variant="body1" color="textSecondary">
              Please connect your wallet to access the Composable RWA Bundle system.
            </Typography>
          </CardContent>
        </Card>
      </Container>
    );
  }

  if (isLoading) {
    return (
      <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
        <Box display="flex" justifyContent="center" alignItems="center" minHeight="400px">
          <CircularProgress size={60} />
        </Box>
      </Container>
    );
  }

  return (
    <Container maxWidth="lg" sx={{ mt: 2, mb: 4 }}>
      {/* Page Header */}
      <Box mb={3}>
        <Typography variant="h3" fontWeight="bold" gutterBottom>
          Composable RWA Bundle
        </Typography>
        <Typography variant="h6" color="textSecondary" gutterBottom>
          Multi-strategy RWA exposure with intelligent optimization
        </Typography>
        
        {/* Quick Stats */}
        {bundleStats && (
          <Box display="flex" gap={3} mt={2} flexWrap="wrap">
            <Box>
              <Typography variant="body2" color="textSecondary">
                Total Value
              </Typography>
              <Typography variant="h6" fontWeight="bold">
                {formatCurrency(bundleStats.totalValue)}
              </Typography>
            </Box>
            <Box>
              <Typography variant="body2" color="textSecondary">
                Active Strategies
              </Typography>
              <Typography variant="h6" fontWeight="bold">
                {strategyAllocations.filter(s => s.isActive).length}
              </Typography>
            </Box>
            <Box>
              <Typography variant="body2" color="textSecondary">
                Current Leverage
              </Typography>
              <Typography variant="h6" fontWeight="bold">
                {(bundleStats.currentLeverage / 100).toFixed(2)}x
              </Typography>
            </Box>
            <Box>
              <Typography variant="body2" color="textSecondary">
                Capital Efficiency
              </Typography>
              <Typography variant="h6" fontWeight="bold">
                {(bundleStats.capitalEfficiency / 100).toFixed(1)}%
              </Typography>
            </Box>
          </Box>
        )}
      </Box>

      {/* Error Alert */}
      {error && (
        <Alert severity="error" sx={{ mb: 3 }}>
          {error}
        </Alert>
      )}

      {/* Warning for no strategies */}
      {strategyAllocations.length === 0 && (
        <Alert severity="warning" sx={{ mb: 3 }}>
          No strategies have been configured yet. Contact the portfolio manager to set up exposure strategies.
        </Alert>
      )}

      {/* Tabs */}
      <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 3 }}>
        <Tabs 
          value={tabValue} 
          onChange={handleTabChange} 
          aria-label="composable rwa tabs"
          variant="scrollable"
          scrollButtons="auto"
        >
          <Tab 
            label="Dashboard" 
            icon={<DashboardIcon />}
            iconPosition="start"
            {...a11yProps(0)} 
          />
          <Tab 
            label="Capital Allocation" 
            icon={<WalletIcon />}
            iconPosition="start"
            {...a11yProps(1)} 
          />
          <Tab 
            label="Strategy Analytics" 
            icon={<ChartIcon />}
            iconPosition="start"
            {...a11yProps(2)} 
            disabled
          />
          <Tab 
            label="Risk Management" 
            icon={<SettingsIcon />}
            iconPosition="start"
            {...a11yProps(3)} 
            disabled
          />
        </Tabs>
      </Box>

      {/* Tab Panels */}
      <TabPanel value={tabValue} index={0}>
        <StrategyDashboard 
          onOptimize={() => {
            // Refresh data after optimization
            refreshData();
          }}
          onRebalance={() => {
            // Refresh data after rebalancing
            refreshData();
          }}
        />
      </TabPanel>

      <TabPanel value={tabValue} index={1}>
        <ComposableRWAAllocation />
      </TabPanel>

      <TabPanel value={tabValue} index={2}>
        <Card>
          <CardContent sx={{ textAlign: 'center', py: 6 }}>
            <ChartIcon sx={{ fontSize: 64, color: 'text.secondary', mb: 2 }} />
            <Typography variant="h5" gutterBottom>
              Strategy Analytics
            </Typography>
            <Typography variant="body1" color="textSecondary">
              Advanced analytics and performance tracking coming soon.
            </Typography>
          </CardContent>
        </Card>
      </TabPanel>

      <TabPanel value={tabValue} index={3}>
        <Card>
          <CardContent sx={{ textAlign: 'center', py: 6 }}>
            <SettingsIcon sx={{ fontSize: 64, color: 'text.secondary', mb: 2 }} />
            <Typography variant="h5" gutterBottom>
              Risk Management
            </Typography>
            <Typography variant="body1" color="textSecondary">
              Risk parameter configuration and emergency controls coming soon.
            </Typography>
          </CardContent>
        </Card>
      </TabPanel>
    </Container>
  );
};

export default ComposableRWAPage;