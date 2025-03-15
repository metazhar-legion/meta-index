import React, { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  CircularProgress,
  Chip,
  LinearProgress,
  IconButton,
  Tooltip,
  useTheme,
  alpha,
  Tabs,
  Tab,
  Divider
} from '@mui/material';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip as RechartsTooltip, Legend } from 'recharts';
import InfoOutlinedIcon from '@mui/icons-material/InfoOutlined';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import { Token } from '../contracts/contractTypes';
import { chartColors } from '../theme/theme';

interface TokenListProps {
  tokens: Token[];
  isLoading: boolean;
  error: string | null;
  networkName?: string;
}

// Custom tooltip for the pie chart
const CustomTooltip = ({ active, payload }: any) => {
  const theme = useTheme();
  
  if (active && payload && payload.length) {
    return (
      <Card sx={{ 
        p: 1.5, 
        border: `1px solid ${alpha('#fff', 0.1)}`,
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
        minWidth: 150
      }}>
        <Typography variant="body2" color="text.secondary" gutterBottom>
          {payload[0].name}
        </Typography>
        <Typography variant="h6" fontWeight="600">
          {payload[0].value.toFixed(2)}%
        </Typography>
      </Card>
    );
  }
  return null;
};

const TokenList: React.FC<TokenListProps> = ({ tokens, isLoading, error, networkName = 'Ethereum' }) => {
  const theme = useTheme();
  const [view, setView] = useState<'table' | 'chart'>('chart');
  
  const handleViewChange = (event: React.SyntheticEvent, newValue: 'table' | 'chart') => {
    setView(newValue);
  };
  // Prepare data for the pie chart
  const pieData = tokens.map((token, index) => {
    const totalWeight = tokens.reduce((sum, t) => sum + Number(t.weight || 0), 0);
    const percentage = totalWeight > 0 ? (Number(token.weight) / totalWeight) * 100 : 0;
    
    return {
      name: token.symbol,
      value: percentage,
      color: chartColors[index % chartColors.length],
      address: token.address
    };
  });

  // Format address for display
  const formatAddress = (address: string) => {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
  };
  
  // Open etherscan link
  const openEtherscan = (address: string) => {
    const baseUrl = networkName.toLowerCase() === 'ethereum' 
      ? 'https://etherscan.io/address/' 
      : `https://${networkName.toLowerCase()}.etherscan.io/address/`;
    window.open(`${baseUrl}${address}`, '_blank');
  };

  if (isLoading) {
    return (
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ py: 1, px: 2 }}>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Index Composition
          </Typography>
          <Box sx={{ width: '100%', mt: 1 }}>
            <LinearProgress />
          </Box>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ py: 1, px: 2 }}>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Index Composition
          </Typography>
          <Box my={1}>
            <Typography color="error">{error}</Typography>
          </Box>
        </CardContent>
      </Card>
    );
  }

  if (tokens.length === 0) {
    return (
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ py: 1, px: 2 }}>
          <Typography variant="h6" sx={{ mb: 1 }}>
            Index Composition
          </Typography>
          <Box 
            sx={{ 
              p: 2, 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center',
              justifyContent: 'center',
              bgcolor: alpha(theme.palette.background.paper, 0.5),
              borderRadius: 2
            }}
          >
            <Typography variant="body1" color="text.secondary" align="center">
              No tokens in the index yet
            </Typography>
          </Box>
        </CardContent>
      </Card>
    );
  }

  // Calculate total weight
  const totalWeight = tokens.reduce((sum, token) => sum + Number(token.weight || 0), 0);

  return (
    <Card sx={{ mb: 2 }}>
      <CardContent sx={{ py: 1, px: 2 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
          <Typography variant="h6">
            Index Composition
          </Typography>
          <Tabs 
            value={view} 
            onChange={handleViewChange}
            sx={{ 
              minHeight: 'auto',
              '& .MuiTabs-indicator': {
                height: 3,
                borderRadius: '3px 3px 0 0'
              }
            }}
          >
            <Tab 
              value="chart" 
              label="Chart" 
              sx={{ 
                minHeight: 'auto',
                py: 0.5,
                px: 2
              }}
            />
            <Tab 
              value="table" 
              label="Table" 
              sx={{ 
                minHeight: 'auto',
                py: 0.5,
                px: 2
              }}
            />
          </Tabs>
        </Box>
        
        <Divider sx={{ mb: 1 }} />
        
        {view === 'chart' ? (
          <Box sx={{ height: 220, display: 'flex', flexDirection: 'column' }}>
            <Box sx={{ flex: 1, minHeight: 0 }}>
              {pieData.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={pieData}
                      cx="50%"
                      cy="50%"
                      innerRadius={60}
                      outerRadius={120}
                      fill="#8884d8"
                      paddingAngle={2}
                      dataKey="value"
                    >
                      {pieData.map((entry, index) => (
                        <Cell 
                          key={`cell-${index}`} 
                          fill={entry.color}
                          stroke={theme.palette.background.paper}
                          strokeWidth={2}
                        />
                      ))}
                    </Pie>
                    <RechartsTooltip content={<CustomTooltip />} />
                    <Legend 
                      formatter={(value, entry, index) => (
                        <span style={{ color: theme.palette.text.primary, marginLeft: 4 }}>{value}</span>
                      )}
                      layout="vertical"
                      verticalAlign="middle"
                      align="right"
                      wrapperStyle={{
                        paddingLeft: '10px',
                        maxHeight: '300px',
                        overflowY: 'auto',
                      }}
                    />
                  </PieChart>
                </ResponsiveContainer>
              ) : (
                <Box 
                  sx={{ 
                    height: '100%', 
                    display: 'flex', 
                    alignItems: 'center', 
                    justifyContent: 'center' 
                  }}
                >
                  <Typography variant="body2" color="text.secondary">
                    No allocation data available
                  </Typography>
                </Box>
              )}
            </Box>
          </Box>
        ) : (
          <TableContainer 
            sx={{ 
              maxHeight: 320,
              '&::-webkit-scrollbar': {
                width: '8px',
                height: '8px',
              },
              '&::-webkit-scrollbar-track': {
                background: alpha('#94A3B8', 0.05),
              },
              '&::-webkit-scrollbar-thumb': {
                background: alpha('#94A3B8', 0.2),
                borderRadius: '4px',
              },
              '&::-webkit-scrollbar-thumb:hover': {
                background: alpha('#94A3B8', 0.3),
              },
            }}
          >
            <Table size="medium">
              <TableHead>
                <TableRow>
                  <TableCell>Token</TableCell>
                  <TableCell>Address</TableCell>
                  <TableCell align="right">Weight</TableCell>
                  <TableCell align="right">Allocation</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {tokens.map((token, index) => {
                  const percentage = totalWeight > 0
                    ? (Number(token.weight) / totalWeight) * 100
                    : 0;
                    
                  return (
                    <TableRow key={token.address} hover>
                      <TableCell>
                        <Box sx={{ display: 'flex', alignItems: 'center' }}>
                          <Box
                            sx={{
                              width: 16,
                              height: 16,
                              borderRadius: '50%',
                              bgcolor: chartColors[index % chartColors.length],
                              mr: 1,
                              flexShrink: 0
                            }}
                          />
                          <Chip 
                            label={token.symbol} 
                            size="small" 
                            sx={{ 
                              fontWeight: 500,
                              bgcolor: alpha(chartColors[index % chartColors.length], 0.1),
                              color: chartColors[index % chartColors.length],
                              border: `1px solid ${alpha(chartColors[index % chartColors.length], 0.2)}`
                            }} 
                          />
                        </Box>
                      </TableCell>
                      <TableCell>
                        <Box sx={{ display: 'flex', alignItems: 'center' }}>
                          <Typography variant="body2" sx={{ fontSize: '0.875rem' }}>
                            {formatAddress(token.address)}
                          </Typography>
                          <Tooltip title="View on Etherscan">
                            <IconButton 
                              size="small" 
                              onClick={() => openEtherscan(token.address)}
                              sx={{ ml: 0.5, p: 0.5 }}
                            >
                              <OpenInNewIcon fontSize="small" sx={{ fontSize: '0.875rem' }} />
                            </IconButton>
                          </Tooltip>
                        </Box>
                      </TableCell>
                      <TableCell align="right">
                        <Typography variant="body2" fontWeight="500">
                          {token.weight}
                        </Typography>
                      </TableCell>
                      <TableCell align="right">
                        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end' }}>
                          <Box sx={{ width: '60%', mr: 1 }}>
                            <LinearProgress 
                              variant="determinate" 
                              value={percentage} 
                              sx={{ 
                                height: 6, 
                                borderRadius: 3,
                                bgcolor: alpha(chartColors[index % chartColors.length], 0.15),
                                '& .MuiLinearProgress-bar': {
                                  bgcolor: chartColors[index % chartColors.length]
                                }
                              }} 
                            />
                          </Box>
                          <Typography variant="body2" fontWeight="500">
                            {percentage.toFixed(2)}%
                          </Typography>
                        </Box>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </CardContent>
    </Card>
  );
};

export default TokenList;
