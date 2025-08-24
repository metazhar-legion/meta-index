// React Query Provider for improved data management
import React from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';

// Configure QueryClient with optimal settings for Web3
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Data is considered stale after 30 seconds
      staleTime: 30000,
      // Keep unused data in cache for 5 minutes
      gcTime: 5 * 60 * 1000,
      // Retry failed requests 3 times with exponential backoff
      retry: 3,
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
      // Don't refetch on window focus by default (can be expensive with blockchain calls)
      refetchOnWindowFocus: false,
      // Don't refetch on reconnect (Web3 handles this)
      refetchOnReconnect: false,
      // Use background refetching for better UX
      refetchIntervalInBackground: true,
    },
    mutations: {
      // Retry failed mutations once
      retry: 1,
      retryDelay: 2000,
    },
  },
});

interface QueryProviderProps {
  children: React.ReactNode;
}

export const QueryProvider: React.FC<QueryProviderProps> = ({ children }) => {
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      {/* Only show devtools in development */}
      {process.env.NODE_ENV === 'development' && (
        <ReactQueryDevtools initialIsOpen={false} />
      )}
    </QueryClientProvider>
  );
};

export default QueryProvider;