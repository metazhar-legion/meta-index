import React from 'react';
import { Box, Typography, Skeleton, useTheme, alpha, SvgIconProps } from '@mui/material';
import CountUp from 'react-countup';

interface StatCardProps {
  title: string;
  value: string | number;
  isLoading: boolean;
  icon: React.ReactElement<SvgIconProps>;
  color?: 'primary' | 'secondary' | 'info' | 'success' | 'warning' | 'error';
  prefix?: string;
  suffix?: string;
  decimals?: number;
  duration?: number;
  change?: {
    value: string | number;
    isPositive: boolean;
    period?: string;
  };
}

/**
 * A standardized card for displaying statistics with built-in loading state
 */
const StatCard: React.FC<StatCardProps> = ({
  title,
  value,
  isLoading,
  icon,
  color = 'primary',
  prefix = '',
  suffix = '',
  decimals = 2,
  duration = 1,
  change
}) => {
  const theme = useTheme();
  
  // Get the appropriate color from the theme
  const themeColor = theme.palette[color].main;
  
  return (
    <Box sx={{
      p: 2,
      borderRadius: 2,
      bgcolor: alpha(themeColor, 0.08),
      display: 'flex',
      flexDirection: 'column',
      height: '100%'
    }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
        <Typography variant="body2" color="text.secondary">
          {title}
        </Typography>
        {React.cloneElement(icon, { color, fontSize: 'small' })}
      </Box>
      
      {isLoading ? (
        <Skeleton width="100%" height={40} animation="wave" />
      ) : (
        <Typography variant="h5" fontWeight="600">
          {/* Log the value being passed to the StatCard */}
          <Box sx={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', width: '100%' }}>
            <CountUp 
              end={typeof value === 'string' ? parseFloat(value.replace(/,/g, '')) || 0 : value} 
              prefix={prefix} 
              suffix={suffix}
              decimals={decimals} 
              duration={duration} 
              separator=","
              preserveValue={true}
              formattingFn={(num) => {
                // Format large numbers to be more readable
                if (num >= 1000000) {
                  return prefix + (num / 1000000).toFixed(2) + 'M' + suffix;
                } else if (num >= 1000) {
                  return prefix + (num / 1000).toFixed(1) + 'K' + suffix;
                } else {
                  return prefix + num.toFixed(decimals) + suffix;
                }
              }}
            />
          </Box>
        </Typography>
      )}
      
      {!isLoading && change && (
        <Box sx={{ display: 'flex', alignItems: 'center', mt: 1 }}>
          <Typography 
            variant="body2" 
            color={change.isPositive ? 'success.main' : 'error.main'}
            sx={{ display: 'flex', alignItems: 'center' }}
          >
            {change.isPositive ? '+' : '-'}{change.value}%
          </Typography>
          {change.period && (
            <Typography variant="caption" color="text.secondary" sx={{ ml: 1 }}>
              {change.period}
            </Typography>
          )}
        </Box>
      )}
    </Box>
  );
};

export default StatCard;
