import React, { useState, useEffect } from 'react';
import { Card, CardContent, Typography, Box, Tabs, Tab, Grid, CircularProgress, Tooltip } from '@mui/material';
import { PieChart } from 'react-minimal-pie-chart';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { formatCurrency, formatPercentage, formatDate } from '../utils/formatters';
import eventBus, { EVENTS } from '../utils/eventBus';

interface CapitalAllocationProps {
  vaultContract: any | null;
  capitalManagerContract: any | null;
  totalAssets: number;
  userSharePercent: number;
  userTotalAssets: number;
}

interface AllocationData {
  rwaPercentage: number;
  yieldPercentage: number;
  liquidityBufferPercentage: number;
  lastRebalanced: number;
}

interface RWAToken {
  rwaToken: string;
  percentage: number;
  active: boolean;
  name?: string;
  symbol?: string;
  assetType?: number;
  lastPrice?: number;
}

interface YieldStrategy {
  strategy: string;
  percentage: number;
  active: boolean;
  name?: string;
  apy?: number;
  risk?: number;
}

const CapitalAllocation: React.FC<CapitalAllocationProps> = ({
  vaultContract,
  capitalManagerContract,
  totalAssets,
  userSharePercent,
  userTotalAssets
}) => {
  const { provider } = useWeb3React();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tabValue, setTabValue] = useState(0);
  const [allocation, setAllocation] = useState<AllocationData | null>(null);
  const [rwaTokens, setRwaTokens] = useState<RWAToken[]>([]);
  const [yieldStrategies, setYieldStrategies] = useState<YieldStrategy[]>([]);
  const [viewMode, setViewMode] = useState<'chart' | 'table'>('chart');

  // Color palette for the pie chart
  const colors = [
    '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0', '#9966FF',
    '#FF9F40', '#8AC926', '#1982C4', '#6A4C93', '#F45B69'
  ];

  useEffect(() => {
    const loadCapitalAllocation = async () => {
      if (!vaultContract || !capitalManagerContract || !provider) {
        setLoading(false);
        return;
      }

      try {
        setLoading(true);
        setError(null);

        // Get capital allocation
        const allocationData = await vaultContract.getCapitalAllocation();
        setAllocation({
          rwaPercentage: Number(allocationData.rwaPercentage) / 100,
          yieldPercentage: Number(allocationData.yieldPercentage) / 100,
          liquidityBufferPercentage: Number(allocationData.liquidityBufferPercentage) / 100,
          lastRebalanced: Number(allocationData.lastRebalanced)
        });

        // Get RWA tokens
        const rwaTokensData = await vaultContract.getRWATokens();
        const rwaTokensWithInfo = await Promise.all(
          rwaTokensData.map(async (token: any) => {
            try {
              const tokenContract = new ethers.Contract(
                token.rwaToken,
                [
                  'function getAssetInfo() external view returns (tuple(string name, string symbol, uint8 assetType, address oracle, uint256 lastPrice, uint256 lastUpdated, bytes32 marketId, bool isActive))'
                ],
                provider
              );
              
              const assetInfo = await tokenContract.getAssetInfo();
              
              return {
                ...token,
                percentage: Number(token.percentage) / 100,
                name: assetInfo.name,
                symbol: assetInfo.symbol,
                assetType: Number(assetInfo.assetType),
                lastPrice: Number(ethers.formatUnits(assetInfo.lastPrice, 18))
              };
            } catch (e) {
              console.error('Error fetching RWA token info:', e);
              return {
                ...token,
                percentage: Number(token.percentage) / 100,
                name: 'Unknown RWA',
                symbol: '???',
                assetType: 0,
                lastPrice: 0
              };
            }
          })
        );
        setRwaTokens(rwaTokensWithInfo);

        // Get yield strategies
        const yieldStrategiesData = await vaultContract.getYieldStrategies();
        const strategiesWithInfo = await Promise.all(
          yieldStrategiesData.map(async (strategy: any) => {
            try {
              const strategyContract = new ethers.Contract(
                strategy.strategy,
                [
                  'function getStrategyInfo() external view returns (tuple(string name, address asset, uint256 totalDeposited, uint256 currentValue, uint256 apy, uint256 lastUpdated, bool active, uint256 risk))'
                ],
                provider
              );
              
              const strategyInfo = await strategyContract.getStrategyInfo();
              
              return {
                ...strategy,
                percentage: Number(strategy.percentage) / 100,
                name: strategyInfo.name,
                apy: Number(strategyInfo.apy) / 100,
                risk: Number(strategyInfo.risk)
              };
            } catch (e) {
              console.error('Error fetching yield strategy info:', e);
              return {
                ...strategy,
                percentage: Number(strategy.percentage) / 100,
                name: 'Unknown Strategy',
                apy: 0,
                risk: 0
              };
            }
          })
        );
        setYieldStrategies(strategiesWithInfo);

      } catch (err) {
        console.error('Error loading capital allocation:', err);
        setError('Failed to load capital allocation data');
      } finally {
        setLoading(false);
      }
    };

    loadCapitalAllocation();

    // Subscribe to vault transaction events
    const handleVaultTransaction = () => {
      loadCapitalAllocation();
    };

    eventBus.on('VAULT_TRANSACTION_COMPLETED', handleVaultTransaction);

    return () => {
      eventBus.off('VAULT_TRANSACTION_COMPLETED', handleVaultTransaction);
    };
  }, [vaultContract, capitalManagerContract, provider]);

  const handleTabChange = (event: React.SyntheticEvent, newValue: number) => {
    setTabValue(newValue);
  };

  const toggleViewMode = () => {
    setViewMode(viewMode === 'chart' ? 'table' : 'chart');
  };

  if (loading) {
    return (
      <Card>
        <CardContent>
          <Box display="flex" justifyContent="center" alignItems="center" minHeight="200px">
            <CircularProgress />
          </Box>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardContent>
          <Typography color="error">{error}</Typography>
        </CardContent>
      </Card>
    );
  }

  // Prepare data for the main allocation pie chart
  const mainAllocationData = allocation ? [
    { title: 'RWA', value: allocation.rwaPercentage, color: colors[0] },
    { title: 'Yield', value: allocation.yieldPercentage, color: colors[1] },
    { title: 'Liquidity', value: allocation.liquidityBufferPercentage, color: colors[2] }
  ] : [];

  // Prepare data for the RWA allocation pie chart
  const rwaAllocationData = rwaTokens.map((token, index) => ({
    title: token.name || `RWA ${index + 1}`,
    value: token.percentage,
    color: colors[index % colors.length]
  }));

  // Prepare data for the yield strategies pie chart
  const yieldAllocationData = yieldStrategies.map((strategy, index) => ({
    title: strategy.name || `Strategy ${index + 1}`,
    value: strategy.percentage,
    color: colors[index % colors.length]
  }));

  const getAssetTypeString = (type: number): string => {
    const types = [
      'Equity Index',
      'Commodity',
      'Fixed Income',
      'Real Estate',
      'Currency',
      'Other'
    ];
    return types[type] || 'Unknown';
  };

  const getRiskLevelString = (risk: number): string => {
    if (risk <= 2) return 'Low';
    if (risk <= 5) return 'Medium';
    if (risk <= 8) return 'High';
    return 'Very High';
  };

  return (
    <Card>
      <CardContent>
        <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
          <Typography variant="h6" component="div">
            Capital Allocation
          </Typography>
          <Typography
            variant="body2"
            component="div"
            sx={{ cursor: 'pointer', color: 'primary.main' }}
            onClick={toggleViewMode}
          >
            {viewMode === 'chart' ? 'Show as Table' : 'Show as Chart'}
          </Typography>
        </Box>

        <Tabs value={tabValue} onChange={handleTabChange} centered sx={{ mb: 2 }}>
          <Tab label="Overview" />
          <Tab label="RWA Assets" />
          <Tab label="Yield Strategies" />
        </Tabs>

        {tabValue === 0 && (
          <Box>
            {viewMode === 'chart' ? (
              <Box display="flex" justifyContent="center" mb={2}>
                <Box width="70%" maxWidth="300px">
                  <PieChart
                    data={mainAllocationData}
                    lineWidth={20}
                    paddingAngle={2}
                    rounded
                    label={({ dataEntry }) => `${dataEntry.title}: ${dataEntry.value.toFixed(1)}%`}
                    labelStyle={{
                      fontSize: '5px',
                      fontFamily: 'sans-serif',
                    }}
                    labelPosition={80}
                  />
                </Box>
              </Box>
            ) : (
              <Box>
                <Grid container spacing={2}>
                  <Grid item xs={4}>
                    <Typography variant="body2" fontWeight="bold">Allocation</Typography>
                  </Grid>
                  <Grid item xs={4}>
                    <Typography variant="body2" fontWeight="bold">Percentage</Typography>
                  </Grid>
                  <Grid item xs={4}>
                    <Typography variant="body2" fontWeight="bold">Value</Typography>
                  </Grid>
                  
                  {allocation && (
                    <>
                      <Grid item xs={4}>
                        <Typography variant="body2">RWA Assets</Typography>
                      </Grid>
                      <Grid item xs={4}>
                        <Typography variant="body2">{allocation.rwaPercentage.toFixed(1)}%</Typography>
                      </Grid>
                      <Grid item xs={4}>
                        <Typography variant="body2">
                          {formatCurrency(totalAssets * allocation.rwaPercentage / 100)}
                        </Typography>
                      </Grid>

                      <Grid item xs={4}>
                        <Typography variant="body2">Yield Strategies</Typography>
                      </Grid>
                      <Grid item xs={4}>
                        <Typography variant="body2">{allocation.yieldPercentage.toFixed(1)}%</Typography>
                      </Grid>
                      <Grid item xs={4}>
                        <Typography variant="body2">
                          {formatCurrency(totalAssets * allocation.yieldPercentage / 100)}
                        </Typography>
                      </Grid>

                      <Grid item xs={4}>
                        <Typography variant="body2">Liquidity Buffer</Typography>
                      </Grid>
                      <Grid item xs={4}>
                        <Typography variant="body2">{allocation.liquidityBufferPercentage.toFixed(1)}%</Typography>
                      </Grid>
                      <Grid item xs={4}>
                        <Typography variant="body2">
                          {formatCurrency(totalAssets * allocation.liquidityBufferPercentage / 100)}
                        </Typography>
                      </Grid>
                    </>
                  )}
                </Grid>
              </Box>
            )}

            <Box mt={2}>
              <Typography variant="body2" color="text.secondary" align="center">
                {allocation && `Last rebalanced: ${new Date(allocation.lastRebalanced * 1000).toLocaleString()}`}
              </Typography>
              <Typography variant="body2" color="text.secondary" align="center">
                Your allocation value: {formatCurrency(userTotalAssets)}
              </Typography>
            </Box>
          </Box>
        )}

        {tabValue === 1 && (
          <Box>
            {rwaTokens.length === 0 ? (
              <Typography variant="body2" align="center">No RWA assets found</Typography>
            ) : viewMode === 'chart' ? (
              <Box display="flex" justifyContent="center" mb={2}>
                <Box width="70%" maxWidth="300px">
                  <PieChart
                    data={rwaAllocationData}
                    lineWidth={20}
                    paddingAngle={2}
                    rounded
                    label={({ dataEntry }) => `${dataEntry.title}: ${dataEntry.value.toFixed(1)}%`}
                    labelStyle={{
                      fontSize: '5px',
                      fontFamily: 'sans-serif',
                    }}
                    labelPosition={80}
                  />
                </Box>
              </Box>
            ) : (
              <Box>
                <Grid container spacing={2}>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Asset</Typography>
                  </Grid>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Type</Typography>
                  </Grid>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Allocation</Typography>
                  </Grid>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Price</Typography>
                  </Grid>
                  
                  {rwaTokens.map((token, index) => (
                    <React.Fragment key={index}>
                      <Grid item xs={3}>
                        <Typography variant="body2">{token.symbol || '???'}</Typography>
                        <Typography variant="caption">{token.name || 'Unknown'}</Typography>
                      </Grid>
                      <Grid item xs={3}>
                        <Typography variant="body2">{getAssetTypeString(token.assetType || 0)}</Typography>
                      </Grid>
                      <Grid item xs={3}>
                        <Typography variant="body2">{token.percentage.toFixed(1)}%</Typography>
                        <Typography variant="caption">
                          {formatCurrency(totalAssets * allocation!.rwaPercentage / 100 * token.percentage / 100)}
                        </Typography>
                      </Grid>
                      <Grid item xs={3}>
                        <Typography variant="body2">${token.lastPrice?.toFixed(2) || '0.00'}</Typography>
                      </Grid>
                    </React.Fragment>
                  ))}
                </Grid>
              </Box>
            )}

            <Box mt={2}>
              <Typography variant="body2" color="text.secondary" align="center">
                RWA assets are backed by perpetual futures with 20% of the fund's capital
              </Typography>
            </Box>
          </Box>
        )}

        {tabValue === 2 && (
          <Box>
            {yieldStrategies.length === 0 ? (
              <Typography variant="body2" align="center">No yield strategies found</Typography>
            ) : viewMode === 'chart' ? (
              <Box display="flex" justifyContent="center" mb={2}>
                <Box width="70%" maxWidth="300px">
                  <PieChart
                    data={yieldAllocationData}
                    lineWidth={20}
                    paddingAngle={2}
                    rounded
                    label={({ dataEntry }) => `${dataEntry.title}: ${dataEntry.value.toFixed(1)}%`}
                    labelStyle={{
                      fontSize: '5px',
                      fontFamily: 'sans-serif',
                    }}
                    labelPosition={80}
                  />
                </Box>
              </Box>
            ) : (
              <Box>
                <Grid container spacing={2}>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Strategy</Typography>
                  </Grid>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">APY</Typography>
                  </Grid>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Risk</Typography>
                  </Grid>
                  <Grid item xs={3}>
                    <Typography variant="body2" fontWeight="bold">Allocation</Typography>
                  </Grid>
                  
                  {yieldStrategies.map((strategy, index) => (
                    <React.Fragment key={index}>
                      <Grid item xs={3}>
                        <Typography variant="body2">{strategy.name || 'Unknown'}</Typography>
                      </Grid>
                      <Grid item xs={3}>
                        <Typography variant="body2" color="success.main">
                          {strategy.apy?.toFixed(2) || '0.00'}%
                        </Typography>
                      </Grid>
                      <Grid item xs={3}>
                        <Typography variant="body2">
                          {getRiskLevelString(strategy.risk || 0)}
                        </Typography>
                      </Grid>
                      <Grid item xs={3}>
                        <Typography variant="body2">{strategy.percentage.toFixed(1)}%</Typography>
                        <Typography variant="caption">
                          {formatCurrency(totalAssets * allocation!.yieldPercentage / 100 * strategy.percentage / 100)}
                        </Typography>
                      </Grid>
                    </React.Fragment>
                  ))}
                </Grid>
              </Box>
            )}

            <Box mt={2}>
              <Typography variant="body2" color="text.secondary" align="center">
                Yield strategies utilize 80% of the fund's capital for stable returns
              </Typography>
            </Box>
          </Box>
        )}
      </CardContent>
    </Card>
  );
};

export default CapitalAllocation;
