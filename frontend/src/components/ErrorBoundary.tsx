import React, { Component, ReactNode } from 'react';
import { Box, Alert, Button, Typography, Paper, Container } from '@mui/material';
import { ErrorOutline, Refresh } from '@mui/icons-material';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
}

interface State {
  hasError: boolean;
  error?: Error;
  errorInfo?: React.ErrorInfo;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    this.setState({ error, errorInfo });
    this.props.onError?.(error, errorInfo);
    
    // Log to console for debugging
    console.error('ErrorBoundary caught an error:', error, errorInfo);
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: undefined, errorInfo: undefined });
  };

  render() {
    if (this.state.hasError) {
      // Custom fallback UI
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // Default error UI
      return (
        <Container maxWidth="md" sx={{ mt: 4 }}>
          <Paper elevation={3} sx={{ p: 4, textAlign: 'center' }}>
            <ErrorOutline color="error" sx={{ fontSize: 64, mb: 2 }} />
            <Typography variant="h4" gutterBottom>
              Something went wrong
            </Typography>
            <Typography variant="body1" color="text.secondary" paragraph>
              An unexpected error occurred while loading this component.
            </Typography>
            
            <Alert severity="error" sx={{ mt: 2, mb: 3, textAlign: 'left' }}>
              <Typography variant="subtitle2" gutterBottom>
                Error Details:
              </Typography>
              <Typography variant="body2" component="pre" sx={{ whiteSpace: 'pre-wrap' }}>
                {this.state.error?.message}
              </Typography>
            </Alert>

            <Box sx={{ display: 'flex', gap: 2, justifyContent: 'center' }}>
              <Button
                variant="contained"
                startIcon={<Refresh />}
                onClick={this.handleRetry}
              >
                Try Again
              </Button>
              <Button
                variant="outlined"
                onClick={() => window.location.reload()}
              >
                Reload Page
              </Button>
            </Box>
          </Paper>
        </Container>
      );
    }

    return this.props.children;
  }
}

// Functional component wrapper for hooks-based error handling
interface AsyncErrorBoundaryProps {
  children: ReactNode;
  onError?: (error: Error) => void;
}

export const AsyncErrorBoundary: React.FC<AsyncErrorBoundaryProps> = ({ 
  children, 
  onError 
}) => {
  return (
    <ErrorBoundary onError={(error, errorInfo) => onError?.(error)}>
      {children}
    </ErrorBoundary>
  );
};

// Hook for manually triggering error boundary
export const useErrorHandler = () => {
  const handleError = React.useCallback((error: Error) => {
    // This will cause ErrorBoundary to catch the error
    throw error;
  }, []);

  return handleError;
};