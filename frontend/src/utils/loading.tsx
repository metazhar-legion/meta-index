import React from 'react';
import { Box, Skeleton, CircularProgress, Typography, alpha, useTheme } from '@mui/material';

/**
 * Standard loading states for consistent UI across components
 */

// Skeleton with consistent styling for card content
export const ContentSkeleton: React.FC<{ height?: number | string }> = ({ height = 100 }) => {
  return <Skeleton variant="rectangular" width="100%" height={height} animation="wave" />;
};

// Overlay loading state that preserves content underneath
export const OverlayLoading: React.FC<{ 
  isLoading: boolean; 
  children: React.ReactNode;
  height?: number | string;
  preserveHeight?: boolean;
}> = ({ isLoading, children, height = '100%', preserveHeight = true }) => {
  const theme = useTheme();
  
  return (
    <Box sx={{ position: 'relative', width: '100%', height: preserveHeight ? height : 'auto' }}>
      {isLoading && (
        <Box 
          sx={{ 
            position: 'absolute', 
            top: 0, 
            left: 0, 
            right: 0, 
            bottom: 0, 
            zIndex: 2,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: alpha(theme.palette.background.paper, 0.7),
            borderRadius: 1
          }}
        >
          <CircularProgress size={24} />
        </Box>
      )}
      <Box 
        sx={{ 
          position: 'relative', 
          zIndex: 1,
          opacity: isLoading ? 0.6 : 1,
          transition: 'opacity 0.3s ease-in-out',
          filter: isLoading ? 'blur(1px)' : 'none',
          transition: 'filter 0.3s ease-in-out'
        }}
      >
        {children}
      </Box>
    </Box>
  );
};

// Button loading state
export const ButtonLoading: React.FC<{ 
  isLoading: boolean; 
  text: string;
  loadingText?: string;
}> = ({ isLoading, text, loadingText }) => {
  return (
    <>
      {isLoading ? (
        <>
          <CircularProgress size={16} color="inherit" sx={{ mr: 1 }} />
          {loadingText || text}
        </>
      ) : (
        text
      )}
    </>
  );
};

// Text with loading state
export const LoadingText: React.FC<{
  isLoading: boolean;
  value: string | number;
  prefix?: string;
  suffix?: string;
  variant?: "body1" | "body2" | "h6" | "h5" | "h4";
}> = ({ isLoading, value, prefix = '', suffix = '', variant = "body1" }) => {
  return isLoading ? (
    <Skeleton width={80} height={24} animation="wave" />
  ) : (
    <Typography variant={variant}>
      {prefix}{value}{suffix}
    </Typography>
  );
};
