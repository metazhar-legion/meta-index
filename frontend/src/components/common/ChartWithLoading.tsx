import React from 'react';
import { Box, Skeleton, Typography, useTheme, alpha } from '@mui/material';
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip } from 'recharts';

interface ChartWithLoadingProps {
  data: any[];
  isLoading: boolean;
  title?: string;
  height?: number | string;
  dataKey?: string;
  xAxisKey?: string;
  color?: string;
  tooltipFormatter?: (value: number) => string;
}

/**
 * A reusable chart component with built-in loading state
 * Uses a smooth transition between loading and loaded states
 */
const ChartWithLoading: React.FC<ChartWithLoadingProps> = ({
  data,
  isLoading,
  title,
  height = 250,
  dataKey = 'value',
  xAxisKey = 'date',
  color,
  tooltipFormatter = (value) => `$${value.toFixed(2)}`
}) => {
  const theme = useTheme();
  const chartColor = color || theme.palette.primary.main;
  
  return (
    <Box sx={{ width: '100%', height }}>
      {title && (
        <Typography variant="subtitle1" gutterBottom>
          {title}
        </Typography>
      )}
      
      {/* Always render the chart to avoid jarring reloads, use opacity for loading state */}
      <Box sx={{ position: 'relative', width: '100%', height: '100%' }}>
        {isLoading && (
          <Box sx={{ 
            position: 'absolute', 
            top: 0, 
            left: 0, 
            right: 0, 
            bottom: 0, 
            zIndex: 1,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center'
          }}>
            <Skeleton variant="rectangular" width="100%" height="100%" />
          </Box>
        )}
        
        <Box sx={{ 
          position: 'relative', 
          width: '100%', 
          height: '100%', 
          zIndex: isLoading ? 0 : 1,
          opacity: isLoading ? 0.3 : 1,
          transition: 'opacity 0.3s ease-in-out',
          filter: isLoading ? 'blur(1px)' : 'none'
        }}>
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
              <defs>
                <linearGradient id={`color${dataKey}`} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={chartColor} stopOpacity={0.8}/>
                  <stop offset="95%" stopColor={chartColor} stopOpacity={0}/>
                </linearGradient>
              </defs>
              
              <CartesianGrid strokeDasharray="3 3" stroke={alpha(theme.palette.text.secondary, 0.2)} />
              
              <XAxis 
                dataKey={xAxisKey} 
                tick={{ fill: theme.palette.text.secondary, fontSize: 12 }}
                axisLine={{ stroke: alpha(theme.palette.text.secondary, 0.3) }}
              />
              
              <YAxis 
                tick={{ fill: theme.palette.text.secondary, fontSize: 12 }}
                axisLine={{ stroke: alpha(theme.palette.text.secondary, 0.3) }}
                tickFormatter={(value) => `$${value}`}
              />
              
              <RechartsTooltip 
                formatter={tooltipFormatter}
                contentStyle={{ 
                  backgroundColor: theme.palette.background.paper,
                  border: `1px solid ${alpha(theme.palette.divider, 0.3)}`,
                  borderRadius: '4px',
                  boxShadow: theme.shadows[2]
                }}
              />
              
              <Area 
                type="monotone" 
                dataKey={dataKey} 
                stroke={chartColor}
                fillOpacity={1}
                fill={`url(#color${dataKey})`}
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Box>
      </Box>
    </Box>
  );
};

export default ChartWithLoading;
