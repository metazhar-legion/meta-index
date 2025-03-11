import React from 'react';
import { Box, Grid, Typography, Card, CardContent, Divider, useTheme } from '@mui/material';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, Legend } from 'recharts';
import { chartColors } from '../theme/theme';
import { Token } from '../contracts/contractTypes';

interface DashboardProps {
  totalAssets: string;
  sharePrice: string;
  userAssets: string;
  userShares: string;
  tokens: Token[];
  isLoading: boolean;
}

// Custom tooltip for the pie chart
const CustomTooltip = ({ active, payload }: any) => {
  if (active && payload && payload.length) {
    return (
      <Card sx={{ p: 1, border: '1px solid rgba(255, 255, 255, 0.1)', boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)' }}>
        <Typography variant="body2" color="text.secondary">
          {payload[0].name}
        </Typography>
        <Typography variant="body1" fontWeight="600">
          {payload[0].value.toFixed(2)}%
        </Typography>
      </Card>
    );
  }
  return null;
};

const Dashboard: React.FC<DashboardProps> = ({
  totalAssets,
  sharePrice,
  userAssets,
  userShares,
  tokens,
  isLoading,
}) => {
  const theme = useTheme();
  
  // Prepare data for the pie chart
  const pieData = tokens.map((token) => {
    const totalWeight = tokens.reduce((sum, t) => sum + Number(t.weight || 0), 0);
    const percentage = totalWeight > 0 ? (Number(token.weight) / totalWeight) * 100 : 0;
    
    return {
      name: token.symbol,
      value: percentage,
      color: token.color || chartColors[tokens.indexOf(token) % chartColors.length],
    };
  });

  // Format numbers with commas
  const formatNumber = (value: string | number) => {
    const num = typeof value === 'string' ? parseFloat(value) : value;
    return new Intl.NumberFormat('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(num);
  };

  return (
    <Box sx={{ mb: 4 }}>
      <Typography variant="h5" fontWeight="600" sx={{ mb: 3 }}>
        Portfolio Dashboard
      </Typography>
      
      <Grid container spacing={3}>
        {/* Key metrics */}
        <Grid item xs={12} md={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                Key Metrics
              </Typography>
              <Grid container spacing={3}>
                <Grid item xs={6} sm={3}>
                  <Box>
                    <Typography variant="body2" color="text.secondary">
                      Total Assets
                    </Typography>
                    <Typography variant="h6" color="primary.main">
                      ${formatNumber(totalAssets)}
                    </Typography>
                  </Box>
                </Grid>
                <Grid item xs={6} sm={3}>
                  <Box>
                    <Typography variant="body2" color="text.secondary">
                      Share Price
                    </Typography>
                    <Typography variant="h6" color="primary.main">
                      ${formatNumber(sharePrice)}
                    </Typography>
                  </Box>
                </Grid>
                <Grid item xs={6} sm={3}>
                  <Box>
                    <Typography variant="body2" color="text.secondary">
                      Your Assets
                    </Typography>
                    <Typography variant="h6" color="secondary.main">
                      ${formatNumber(userAssets)}
                    </Typography>
                  </Box>
                </Grid>
                <Grid item xs={6} sm={3}>
                  <Box>
                    <Typography variant="body2" color="text.secondary">
                      Your Shares
                    </Typography>
                    <Typography variant="h6" color="secondary.main">
                      {formatNumber(userShares)}
                    </Typography>
                  </Box>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        </Grid>

        {/* Performance card */}
        <Grid item xs={12} md={4}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                Performance
              </Typography>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Share Price Growth
                  </Typography>
                  <Typography variant="h5" color="secondary.main">
                    +2.4%
                  </Typography>
                </Box>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    24h Change
                  </Typography>
                  <Typography variant="h5" color="secondary.main">
                    +$0.24
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Asset allocation */}
        <Grid item xs={12} md={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                Asset Allocation
              </Typography>
              <Box sx={{ height: 300 }}>
                {pieData.length > 0 ? (
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={pieData}
                        cx="50%"
                        cy="50%"
                        innerRadius={60}
                        outerRadius={100}
                        fill="#8884d8"
                        paddingAngle={2}
                        dataKey="value"
                        label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                        labelLine={false}
                      >
                        {pieData.map((entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        ))}
                      </Pie>
                      <Tooltip content={<CustomTooltip />} />
                      <Legend />
                    </PieChart>
                  </ResponsiveContainer>
                ) : (
                  <Box
                    sx={{
                      height: '100%',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    <Typography variant="body1" color="text.secondary">
                      No assets in the portfolio
                    </Typography>
                  </Box>
                )}
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Token details */}
        <Grid item xs={12} md={4}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                Token Details
              </Typography>
              <Box sx={{ maxHeight: 300, overflowY: 'auto' }}>
                {tokens.map((token, index) => (
                  <Box key={token.address}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', py: 1 }}>
                      <Box sx={{ display: 'flex', alignItems: 'center' }}>
                        <Box
                          sx={{
                            width: 12,
                            height: 12,
                            borderRadius: '50%',
                            bgcolor: chartColors[index % chartColors.length],
                            mr: 1,
                          }}
                        />
                        <Typography variant="body1">{token.symbol}</Typography>
                      </Box>
                      <Typography variant="body2" color="text.secondary">
                        Weight: {token.weight}
                      </Typography>
                    </Box>
                    {index < tokens.length - 1 && <Divider />}
                  </Box>
                ))}
                {tokens.length === 0 && (
                  <Typography variant="body2" color="text.secondary">
                    No tokens in the index
                  </Typography>
                )}
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;
