// React Query-based data layer for ComposableRWA
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import { CONTRACT_ADDRESSES } from '../contracts/addresses';
import {
  ComposableRWABundleInterface,
  MockUSDCInterface,
  StrategyOptimizerInterface,
  ComposableRWABundleABI,
  MockUSDCABI,
  StrategyOptimizerABI,
  BundleStats,
  StrategyAllocation,
  YieldStrategyBundle,
} from '../contracts/composableRWATypes';

// Query keys for caching
export const queryKeys = {
  bundleStats: ['bundleStats'] as const,
  strategyAllocations: ['strategyAllocations'] as const,
  yieldBundle: ['yieldBundle'] as const,
  totalCapital: ['totalCapital'] as const,
  userBalance: ['userBalance'] as const,
  userAllowance: ['userAllowance'] as const,
};

// Helper to get contract instances
const getContracts = (provider: ethers.Provider, signer?: ethers.Signer) => {
  const contractProvider = signer || provider;
  
  return {
    bundle: new ethers.Contract(
      CONTRACT_ADDRESSES.COMPOSABLE_RWA_BUNDLE,
      ComposableRWABundleABI,
      contractProvider
    ) as ComposableRWABundleInterface,
    
    usdc: new ethers.Contract(
      CONTRACT_ADDRESSES.MOCK_USDC,
      MockUSDCABI,
      contractProvider
    ) as MockUSDCInterface,
    
    optimizer: new ethers.Contract(
      CONTRACT_ADDRESSES.STRATEGY_OPTIMIZER,
      StrategyOptimizerABI,
      contractProvider
    ) as StrategyOptimizerInterface,
  };
};

// Bundle Stats Query
export const useBundleStats = () => {
  const { provider, account, isActive } = useWeb3();
  
  return useQuery({
    queryKey: queryKeys.bundleStats,
    queryFn: async (): Promise<BundleStats | null> => {
      if (!provider || !isActive) return null;
      
      const { bundle } = getContracts(provider);
      return await bundle.getBundleStats();
    },
    enabled: !!provider && isActive,
    staleTime: 30000, // Consider data fresh for 30 seconds
    refetchInterval: 60000, // Refetch every minute
  });
};

// Strategy Allocations Query
export const useStrategyAllocations = () => {
  const { provider, isActive } = useWeb3();
  
  return useQuery({
    queryKey: queryKeys.strategyAllocations,
    queryFn: async (): Promise<StrategyAllocation[]> => {
      if (!provider || !isActive) return [];
      
      try {
        const { bundle } = getContracts(provider);
        // Try getExposureStrategies first, fallback to empty array
        const strategies = await bundle.getExposureStrategies().catch(() => []);
        return strategies || [];
      } catch (error) {
        console.warn('Failed to fetch strategy allocations:', error);
        return [];
      }
    },
    enabled: !!provider && isActive,
    staleTime: 30000,
    refetchInterval: 60000,
  });
};

// Yield Bundle Query
export const useYieldBundle = () => {
  const { provider, isActive } = useWeb3();
  
  return useQuery({
    queryKey: queryKeys.yieldBundle,
    queryFn: async (): Promise<YieldStrategyBundle | null> => {
      if (!provider || !isActive) return null;
      
      const { bundle } = getContracts(provider);
      return await bundle.getYieldBundle();
    },
    enabled: !!provider && isActive,
    staleTime: 30000,
    refetchInterval: 60000,
  });
};

// Total Capital Query
export const useTotalCapital = () => {
  const { provider, isActive } = useWeb3();
  
  return useQuery({
    queryKey: queryKeys.totalCapital,
    queryFn: async (): Promise<string> => {
      if (!provider || !isActive) return '0';
      
      const { bundle } = getContracts(provider);
      const total = await bundle.getTotalAllocatedCapital();
      return total.toString();
    },
    enabled: !!provider && isActive,
    staleTime: 30000,
    refetchInterval: 60000,
  });
};

// User USDC Balance Query
export const useUserBalance = () => {
  const { provider, account, isActive } = useWeb3();
  
  return useQuery({
    queryKey: [...queryKeys.userBalance, account],
    queryFn: async (): Promise<string> => {
      if (!provider || !account || !isActive) return '0';
      
      const { usdc } = getContracts(provider);
      const balance = await usdc.balanceOf(account);
      return balance.toString();
    },
    enabled: !!provider && !!account && isActive,
    staleTime: 15000, // User balance changes more frequently
    refetchInterval: 30000,
  });
};

// User Allowance Query
export const useUserAllowance = () => {
  const { provider, account, isActive } = useWeb3();
  
  return useQuery({
    queryKey: [...queryKeys.userAllowance, account],
    queryFn: async (): Promise<string> => {
      if (!provider || !account || !isActive) return '0';
      
      const { usdc } = getContracts(provider);
      const allowance = await usdc.allowance(account, CONTRACT_ADDRESSES.COMPOSABLE_RWA_BUNDLE);
      return allowance.toString();
    },
    enabled: !!provider && !!account && isActive,
    staleTime: 15000,
    refetchInterval: 30000,
  });
};

// Transaction Mutations
export const useApproveUSDC = () => {
  const { provider, account } = useWeb3();
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (amount: string): Promise<ethers.ContractTransactionResponse> => {
      if (!provider || !account) throw new Error('Wallet not connected');
      
      const signer = await (provider as any).getSigner();
      const { usdc } = getContracts(provider, signer);
      
      const tx = await usdc.approve(CONTRACT_ADDRESSES.COMPOSABLE_RWA_BUNDLE, amount);
      await tx.wait();
      return tx;
    },
    onSuccess: () => {
      // Invalidate and refetch related queries
      queryClient.invalidateQueries({ queryKey: queryKeys.userAllowance });
    },
  });
};

export const useAllocateCapital = () => {
  const { provider, account } = useWeb3();
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (amount: string): Promise<ethers.ContractTransactionResponse> => {
      if (!provider || !account) throw new Error('Wallet not connected');
      
      const signer = await (provider as any).getSigner();
      const { bundle } = getContracts(provider, signer);
      
      const tx = await bundle.allocateCapital(amount);
      await tx.wait();
      return tx;
    },
    onSuccess: () => {
      // Invalidate all relevant data after allocation
      queryClient.invalidateQueries({ queryKey: queryKeys.bundleStats });
      queryClient.invalidateQueries({ queryKey: queryKeys.strategyAllocations });
      queryClient.invalidateQueries({ queryKey: queryKeys.totalCapital });
      queryClient.invalidateQueries({ queryKey: queryKeys.userBalance });
      queryClient.invalidateQueries({ queryKey: queryKeys.userAllowance });
    },
  });
};

export const useWithdrawCapital = () => {
  const { provider, account } = useWeb3();
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (amount: string): Promise<ethers.ContractTransactionResponse> => {
      if (!provider || !account) throw new Error('Wallet not connected');
      
      const signer = await (provider as any).getSigner();
      const { bundle } = getContracts(provider, signer);
      
      const tx = await bundle.withdrawCapital(amount);
      await tx.wait();
      return tx;
    },
    onSuccess: () => {
      // Invalidate all relevant data after withdrawal
      queryClient.invalidateQueries({ queryKey: queryKeys.bundleStats });
      queryClient.invalidateQueries({ queryKey: queryKeys.strategyAllocations });
      queryClient.invalidateQueries({ queryKey: queryKeys.totalCapital });
      queryClient.invalidateQueries({ queryKey: queryKeys.userBalance });
    },
  });
};

export const useHarvestYield = () => {
  const { provider, account } = useWeb3();
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (): Promise<ethers.ContractTransactionResponse> => {
      if (!provider || !account) throw new Error('Wallet not connected');
      
      const signer = await (provider as any).getSigner();
      const { bundle } = getContracts(provider, signer);
      
      const tx = await bundle.harvestYield();
      await tx.wait();
      return tx;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.bundleStats });
      queryClient.invalidateQueries({ queryKey: queryKeys.yieldBundle });
      queryClient.invalidateQueries({ queryKey: queryKeys.userBalance });
    },
  });
};

export const useOptimizeStrategies = () => {
  const { provider, account } = useWeb3();
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (): Promise<ethers.ContractTransactionResponse> => {
      if (!provider || !account) throw new Error('Wallet not connected');
      
      const signer = await (provider as any).getSigner();
      const { bundle } = getContracts(provider, signer);
      
      const tx = await bundle.optimizeStrategies();
      await tx.wait();
      return tx;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.bundleStats });
      queryClient.invalidateQueries({ queryKey: queryKeys.strategyAllocations });
    },
  });
};

export const useRebalanceStrategies = () => {
  const { provider, account } = useWeb3();
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (): Promise<ethers.ContractTransactionResponse> => {
      if (!provider || !account) throw new Error('Wallet not connected');
      
      const signer = await (provider as any).getSigner();
      const { bundle } = getContracts(provider, signer);
      
      const tx = await bundle.rebalanceStrategies();
      await tx.wait();
      return tx;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.bundleStats });
      queryClient.invalidateQueries({ queryKey: queryKeys.strategyAllocations });
    },
  });
};

// Utility hook for all ComposableRWA data
export const useComposableRWAData = () => {
  const bundleStats = useBundleStats();
  const strategyAllocations = useStrategyAllocations();
  const yieldBundle = useYieldBundle();
  const totalCapital = useTotalCapital();
  const userBalance = useUserBalance();
  const userAllowance = useUserAllowance();
  
  return {
    bundleStats: bundleStats.data,
    strategyAllocations: strategyAllocations.data || [],
    yieldBundle: yieldBundle.data,
    totalAllocatedCapital: totalCapital.data || '0',
    userUSDCBalance: userBalance.data || '0',
    userAllowance: userAllowance.data || '0',
    
    isLoading: bundleStats.isLoading || strategyAllocations.isLoading || yieldBundle.isLoading,
    isRefreshing: bundleStats.isRefetching || strategyAllocations.isRefetching || yieldBundle.isRefetching,
    error: bundleStats.error?.message || strategyAllocations.error?.message || yieldBundle.error?.message || null,
    
    // Manual refetch function
    refetchAll: () => {
      bundleStats.refetch();
      strategyAllocations.refetch();
      yieldBundle.refetch();
      totalCapital.refetch();
      userBalance.refetch();
      userAllowance.refetch();
    },
  };
};