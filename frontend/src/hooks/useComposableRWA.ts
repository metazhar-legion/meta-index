import { useEffect, useState, useCallback } from 'react';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import {
  ComposableRWABundleInterface,
  TRSExposureStrategyInterface,
  DirectTokenStrategyInterface,
  EnhancedPerpetualStrategyInterface,
  StrategyOptimizerInterface,
  MockUSDCInterface,
  ComposableRWABundleABI,
  TRSExposureStrategyABI,
  DirectTokenStrategyABI,
  EnhancedPerpetualStrategyABI,
  StrategyOptimizerABI,
  MockUSDCABI,
  StrategyAllocation,
  YieldStrategyBundle,
  BundleStats,
  ExposureInfo,
  CostBreakdown,
} from '../contracts/composableRWATypes';
import { CONTRACT_ADDRESSES } from '../contracts/addresses';

// Helper function to safely get a signer from a provider
const getSafeSignerFromProvider = async (provider: ethers.Provider): Promise<ethers.Signer | null> => {
  if (!provider) return null;
  
  try {
    if ('getSigner' in provider && typeof provider.getSigner === 'function') {
      return await provider.getSigner();
    }
    return null;
  } catch (error) {
    console.error('Error getting signer from provider:', error);
    return null;
  }
};

interface UseComposableRWAReturn {
  // Core contracts
  bundleContract: ComposableRWABundleInterface | null;
  optimizerContract: StrategyOptimizerInterface | null;
  usdcContract: MockUSDCInterface | null;
  
  // Strategy contracts
  trsStrategyContract: TRSExposureStrategyInterface | null;
  perpetualStrategyContract: EnhancedPerpetualStrategyInterface | null;
  directTokenStrategyContract: DirectTokenStrategyInterface | null;
  
  // Bundle data
  bundleStats: BundleStats | null;
  strategyAllocations: StrategyAllocation[];
  yieldBundle: YieldStrategyBundle | null;
  totalAllocatedCapital: string;
  
  // User data
  userUSDCBalance: string;
  userAllowance: string;
  
  // Loading states
  isLoading: boolean;
  isRefreshing: boolean;
  error: string | null;
  
  // Functions
  refreshData: () => Promise<void>;
  approveUSDC: (amount: string) => Promise<ethers.ContractTransactionResponse>;
  allocateCapital: (amount: string) => Promise<ethers.ContractTransactionResponse>;
  withdrawCapital: (amount: string) => Promise<ethers.ContractTransactionResponse>;
  harvestYield: () => Promise<ethers.ContractTransactionResponse>;
  optimizeStrategies: () => Promise<ethers.ContractTransactionResponse>;
  rebalanceStrategies: () => Promise<ethers.ContractTransactionResponse>;
}

export const useComposableRWA = (): UseComposableRWAReturn => {
  const { provider, account, isActive } = useWeb3();
  
  // Contract instances
  const [bundleContract, setBundleContract] = useState<ComposableRWABundleInterface | null>(null);
  const [optimizerContract, setOptimizerContract] = useState<StrategyOptimizerInterface | null>(null);
  const [usdcContract, setUsdcContract] = useState<MockUSDCInterface | null>(null);
  const [trsStrategyContract, setTrsStrategyContract] = useState<TRSExposureStrategyInterface | null>(null);
  const [perpetualStrategyContract, setPerpetualStrategyContract] = useState<EnhancedPerpetualStrategyInterface | null>(null);
  const [directTokenStrategyContract, setDirectTokenStrategyContract] = useState<DirectTokenStrategyInterface | null>(null);
  
  // Data states
  const [bundleStats, setBundleStats] = useState<BundleStats | null>(null);
  const [strategyAllocations, setStrategyAllocations] = useState<StrategyAllocation[]>([]);
  const [yieldBundle, setYieldBundle] = useState<YieldStrategyBundle | null>(null);
  const [totalAllocatedCapital, setTotalAllocatedCapital] = useState<string>('0');
  const [userUSDCBalance, setUserUSDCBalance] = useState<string>('0');
  const [userAllowance, setUserAllowance] = useState<string>('0');
  
  // Loading states
  const [isLoading, setIsLoading] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize contracts
  useEffect(() => {
    if (!provider || !isActive) {
      setBundleContract(null);
      setOptimizerContract(null);
      setUsdcContract(null);
      setTrsStrategyContract(null);
      setPerpetualStrategyContract(null);
      setDirectTokenStrategyContract(null);
      return;
    }

    const initializeContracts = async () => {
      setIsLoading(true);
      setError(null);
      
      try {
        const signer = await getSafeSignerFromProvider(provider);
        const contractProvider = signer || provider;

        // Initialize core contracts
        const bundle = new ethers.Contract(
          CONTRACT_ADDRESSES.COMPOSABLE_RWA_BUNDLE,
          ComposableRWABundleABI,
          contractProvider
        ) as ComposableRWABundleInterface;

        const optimizer = new ethers.Contract(
          CONTRACT_ADDRESSES.STRATEGY_OPTIMIZER,
          StrategyOptimizerABI,
          contractProvider
        ) as StrategyOptimizerInterface;

        const usdc = new ethers.Contract(
          CONTRACT_ADDRESSES.MOCK_USDC,
          MockUSDCABI,
          contractProvider
        ) as MockUSDCInterface;

        // Initialize strategy contracts
        const trsStrategy = new ethers.Contract(
          CONTRACT_ADDRESSES.TRS_EXPOSURE_STRATEGY,
          TRSExposureStrategyABI,
          contractProvider
        ) as TRSExposureStrategyInterface;

        const perpetualStrategy = new ethers.Contract(
          CONTRACT_ADDRESSES.PERPETUAL_STRATEGY,
          EnhancedPerpetualStrategyABI,
          contractProvider
        ) as EnhancedPerpetualStrategyInterface;

        const directTokenStrategy = new ethers.Contract(
          CONTRACT_ADDRESSES.DIRECT_TOKEN_STRATEGY,
          DirectTokenStrategyABI,
          contractProvider
        ) as DirectTokenStrategyInterface;

        // Set contracts
        setBundleContract(bundle);
        setOptimizerContract(optimizer);
        setUsdcContract(usdc);
        setTrsStrategyContract(trsStrategy);
        setPerpetualStrategyContract(perpetualStrategy);
        setDirectTokenStrategyContract(directTokenStrategy);

        console.log('ComposableRWA contracts initialized successfully');
        
      } catch (error) {
        console.error('Error initializing ComposableRWA contracts:', error);
        setError('Failed to initialize contracts');
      } finally {
        setIsLoading(false);
      }
    };

    initializeContracts();
  }, [provider, isActive]);

  // Refresh data function
  const refreshData = useCallback(async () => {
    if (!bundleContract || !usdcContract || !account) return;
    
    setIsRefreshing(true);
    setError(null);
    
    try {
      // Fetch bundle data
      const [
        stats,
        allocations,
        yieldBundleData,
        totalCapital,
        userBalance,
        allowance
      ] = await Promise.all([
        bundleContract.getBundleStats().catch(() => null),
        bundleContract.getExposureStrategies().catch(() => []),
        bundleContract.getYieldBundle().catch(() => null),
        bundleContract.totalAllocatedCapital().catch(() => '0'),
        usdcContract.balanceOf(account).catch(() => '0'),
        usdcContract.allowance(account, CONTRACT_ADDRESSES.COMPOSABLE_RWA_BUNDLE).catch(() => '0')
      ]);

      setBundleStats(stats);
      setStrategyAllocations(allocations);
      setYieldBundle(yieldBundleData);
      setTotalAllocatedCapital(totalCapital);
      setUserUSDCBalance(userBalance);
      setUserAllowance(allowance);
      
    } catch (error) {
      console.error('Error refreshing ComposableRWA data:', error);
      setError('Failed to refresh data');
    } finally {
      setIsRefreshing(false);
    }
  }, [bundleContract, usdcContract, account]);

  // Load initial data
  useEffect(() => {
    if (bundleContract && usdcContract && account) {
      refreshData();
    }
  }, [bundleContract, usdcContract, account, refreshData]);

  // Transaction functions
  const approveUSDC = useCallback(async (amount: string): Promise<ethers.ContractTransactionResponse> => {
    if (!usdcContract) throw new Error('USDC contract not initialized');
    
    const tx = await usdcContract.approve(CONTRACT_ADDRESSES.COMPOSABLE_RWA_BUNDLE, amount);
    await tx.wait();
    await refreshData();
    return tx;
  }, [usdcContract, refreshData]);

  const allocateCapital = useCallback(async (amount: string): Promise<ethers.ContractTransactionResponse> => {
    if (!bundleContract) throw new Error('Bundle contract not initialized');
    
    const tx = await bundleContract.allocateCapital(amount);
    await tx.wait();
    await refreshData();
    return tx;
  }, [bundleContract, refreshData]);

  const withdrawCapital = useCallback(async (amount: string): Promise<ethers.ContractTransactionResponse> => {
    if (!bundleContract) throw new Error('Bundle contract not initialized');
    
    const tx = await bundleContract.withdrawCapital(amount);
    await tx.wait();
    await refreshData();
    return tx;
  }, [bundleContract, refreshData]);

  const harvestYield = useCallback(async (): Promise<ethers.ContractTransactionResponse> => {
    if (!bundleContract) throw new Error('Bundle contract not initialized');
    
    const tx = await bundleContract.harvestYield();
    await tx.wait();
    await refreshData();
    return tx;
  }, [bundleContract, refreshData]);

  const optimizeStrategies = useCallback(async (): Promise<ethers.ContractTransactionResponse> => {
    if (!bundleContract) throw new Error('Bundle contract not initialized');
    
    const tx = await bundleContract.optimizeStrategies();
    await tx.wait();
    await refreshData();
    return tx;
  }, [bundleContract, refreshData]);

  const rebalanceStrategies = useCallback(async (): Promise<ethers.ContractTransactionResponse> => {
    if (!bundleContract) throw new Error('Bundle contract not initialized');
    
    const tx = await bundleContract.rebalanceStrategies();
    await tx.wait();
    await refreshData();
    return tx;
  }, [bundleContract, refreshData]);

  return {
    // Contracts
    bundleContract,
    optimizerContract,
    usdcContract,
    trsStrategyContract,
    perpetualStrategyContract,
    directTokenStrategyContract,
    
    // Data
    bundleStats,
    strategyAllocations,
    yieldBundle,
    totalAllocatedCapital,
    userUSDCBalance,
    userAllowance,
    
    // States
    isLoading,
    isRefreshing,
    error,
    
    // Functions
    refreshData,
    approveUSDC,
    allocateCapital,
    withdrawCapital,
    harvestYield,
    optimizeStrategies,
    rebalanceStrategies,
  };
};