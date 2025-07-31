import { ethers } from 'ethers';

// Import the ABIs
import ComposableRWABundleABI from './abis/ComposableRWABundle.json';
import TRSExposureStrategyABI from './abis/TRSExposureStrategy.json';
import EnhancedPerpetualStrategyABI from './abis/EnhancedPerpetualStrategy.json';
import DirectTokenStrategyABI from './abis/DirectTokenStrategy.json';
import StrategyOptimizerABI from './abis/StrategyOptimizer.json';
import MockUSDCABI from './abis/MockUSDC.json';

// Export ABIs
export {
  ComposableRWABundleABI,
  TRSExposureStrategyABI,
  EnhancedPerpetualStrategyABI,
  DirectTokenStrategyABI,
  StrategyOptimizerABI,
  MockUSDCABI,
};

// Type definitions for ComposableRWA system

export enum StrategyType {
  PERPETUAL = 0,
  TRS = 1,
  DIRECT_TOKEN = 2,
  SYNTHETIC_TOKEN = 3,
  OPTIONS = 4,
}

export interface StrategyAllocation {
  strategy: string;
  targetAllocation: number;
  maxAllocation: number;
  isPrimary: boolean;
  isActive: boolean;
}

export interface YieldStrategyBundle {
  strategies: string[];
  allocations: number[];
  isActive: boolean;
}

export interface RiskParameters {
  maxTotalLeverage: number;
  maxStrategyCount: number;
  rebalanceThreshold: number;
  emergencyThreshold: number;
  maxSlippageTolerance: number;
  minCapitalEfficiency: number;
  circuitBreakerActive: boolean;
}

export interface ExposureInfo {
  strategyType: StrategyType;
  name: string;
  leverage: number;
  collateralRatio: number;
  currentExposure: string;
  isActive: boolean;
  liquidationPrice: string;
}

export interface CostBreakdown {
  fundingRate: number;
  borrowRate: number;
  managementFee: number;
  slippageCost: number;
  gasCost: number;
  totalCostBps: number;
}

export interface BundleStats {
  totalValue: string;
  totalExposure: string;
  currentLeverage: number;
  capitalEfficiency: number;
  isHealthy: boolean;
}

export interface CounterpartyAllocation {
  counterparty: string;
  targetAllocation: number;
  maxExposure: string;
  currentExposure: string;
  creditRating: string;
}

export interface TRSContractInfo {
  contractId: string;
  counterparty: string;
  underlyingAsset: string;
  notionalAmount: string;
  entryPrice: string;
  currentValue: string;
  maturityDate: number;
  status: number; // TRSStatus enum
}

export interface PerformanceMetrics {
  totalReturn: string;
  annualizedReturn: number;
  volatility: number;
  sharpeRatio: number;
  maxDrawdown: number;
  totalFees: string;
  yieldHarvested: string;
}

// Contract interface types
export interface ComposableRWABundleInterface extends ethers.Contract {
  // Core functions
  allocateCapital(amount: string): Promise<ethers.ContractTransactionResponse>;
  withdrawCapital(amount: string): Promise<ethers.ContractTransactionResponse>;
  getValueInBaseAsset(): Promise<string>;
  harvestYield(): Promise<ethers.ContractTransactionResponse>;
  
  // Strategy management
  addExposureStrategy(
    strategy: string,
    targetAllocation: number,
    maxAllocation: number,
    isPrimary: boolean
  ): Promise<ethers.ContractTransactionResponse>;
  removeExposureStrategy(strategy: string): Promise<ethers.ContractTransactionResponse>;
  getExposureStrategies(): Promise<StrategyAllocation[]>;
  
  // Yield management
  updateYieldBundle(
    strategies: string[],
    allocations: number[]
  ): Promise<ethers.ContractTransactionResponse>;
  getYieldBundle(): Promise<YieldStrategyBundle>;
  
  // Optimization and rebalancing
  optimizeStrategies(): Promise<ethers.ContractTransactionResponse>;
  rebalanceStrategies(): Promise<ethers.ContractTransactionResponse>;
  
  // Risk management
  updateRiskParameters(newParams: RiskParameters): Promise<ethers.ContractTransactionResponse>;
  getRiskParameters(): Promise<RiskParameters>;
  emergencyExitAll(): Promise<ethers.ContractTransactionResponse>;
  
  // Stats and monitoring
  getBundleStats(): Promise<BundleStats>;
  totalAllocatedCapital(): Promise<string>;
  
  // Core properties
  name(): Promise<string>;
  baseAsset(): Promise<string>;
  priceOracle(): Promise<string>;
  optimizer(): Promise<string>;
}

export interface TRSExposureStrategyInterface extends ethers.Contract {
  // Exposure management
  openExposure(amount: string): Promise<ethers.ContractTransactionResponse>;
  closeExposure(amount: string): Promise<ethers.ContractTransactionResponse>;
  adjustExposure(delta: string): Promise<ethers.ContractTransactionResponse>;
  getCurrentExposureValue(): Promise<string>;
  
  // Counterparty management
  addCounterparty(
    counterparty: string,
    allocation: number,
    maxExposure: string
  ): Promise<ethers.ContractTransactionResponse>;
  removeCounterparty(counterparty: string): Promise<ethers.ContractTransactionResponse>;
  getCounterpartyAllocations(): Promise<CounterpartyAllocation[]>;
  
  // Contract management
  getActiveTRSContracts(): Promise<string[]>;
  getTRSContractInfo(contractId: string): Promise<TRSContractInfo>;
  
  // Strategy info
  getExposureInfo(): Promise<ExposureInfo>;
  getCostBreakdown(): Promise<CostBreakdown>;
  canHandleExposure(amount: string): Promise<[boolean, string]>;
  estimateExposureCost(amount: string, timeHorizon: number): Promise<string>;
  
  // Emergency
  emergencyExit(): Promise<ethers.ContractTransactionResponse>;
  harvestYield(): Promise<ethers.ContractTransactionResponse>;
}

export interface DirectTokenStrategyInterface extends ethers.Contract {
  // Exposure management
  openExposure(amount: string): Promise<ethers.ContractTransactionResponse>;
  closeExposure(amount: string): Promise<ethers.ContractTransactionResponse>;
  adjustExposure(delta: string): Promise<ethers.ContractTransactionResponse>;
  getCurrentExposureValue(): Promise<string>;
  
  // Token management
  currentTokenBalance(): Promise<string>;
  totalInvestedAmount(): Promise<string>;
  tokenAllocation(): Promise<number>;
  yieldAllocation(): Promise<number>;
  
  // Yield strategies
  addYieldStrategy(strategy: string, allocation: number): Promise<ethers.ContractTransactionResponse>;
  removeYieldStrategy(index: number): Promise<ethers.ContractTransactionResponse>;
  getYieldStrategies(): Promise<[string[], number[]]>;
  
  // Strategy info
  getExposureInfo(): Promise<ExposureInfo>;
  getCostBreakdown(): Promise<CostBreakdown>;
  canHandleExposure(amount: string): Promise<[boolean, string]>;
  estimateExposureCost(amount: string, timeHorizon: number): Promise<string>;
  
  // Performance
  getPerformanceMetrics(): Promise<{
    totalPurchased: string;
    totalSold: string;
    currentBalance: string;
    totalSlippage: string;
    yieldHarvested: string;
  }>;
  
  // Emergency and yield
  emergencyExit(): Promise<ethers.ContractTransactionResponse>;
  harvestYield(): Promise<ethers.ContractTransactionResponse>;
}

export interface EnhancedPerpetualStrategyInterface extends ethers.Contract {
  // Exposure management
  openExposure(amount: string): Promise<ethers.ContractTransactionResponse>;
  closeExposure(amount: string): Promise<ethers.ContractTransactionResponse>;
  adjustExposure(delta: string): Promise<ethers.ContractTransactionResponse>;
  getCurrentExposureValue(): Promise<string>;
  
  // Position management
  getPositionSize(): Promise<string>;
  getCurrentLeverage(): Promise<number>;
  getUnrealizedPnL(): Promise<string>;
  
  // Strategy info
  getExposureInfo(): Promise<ExposureInfo>;
  getCostBreakdown(): Promise<CostBreakdown>;
  canHandleExposure(amount: string): Promise<[boolean, string]>;
  estimateExposureCost(amount: string, timeHorizon: number): Promise<string>;
  
  // Emergency and yield
  emergencyExit(): Promise<ethers.ContractTransactionResponse>;
  harvestYield(): Promise<ethers.ContractTransactionResponse>;
}

export interface StrategyOptimizerInterface extends ethers.Contract {
  // Analysis functions
  analyzeStrategies(
    strategies: string[],
    targetExposure: string,
    timeHorizon: number
  ): Promise<{
    optimalAllocation: number[];
    expectedCost: string;
    riskScore: number;
    recommendation: string;
  }>;
  
  // Performance tracking
  recordPerformance(
    strategy: string,
    returnBps: number,
    costBps: number,
    riskScore: number,
    success: boolean
  ): Promise<ethers.ContractTransactionResponse>;
  
  getPerformanceMetrics(
    strategies: string[],
    lookbackPeriod: number
  ): Promise<PerformanceMetrics[]>;
  
  // Risk assessment
  updateRiskAssessment(
    strategy: string,
    newScore: number,
    reasoning: string
  ): Promise<ethers.ContractTransactionResponse>;
  
  checkEmergencyStates(strategies: string[]): Promise<boolean[]>;
  
  // Configuration
  updateOptimizationParameters(
    gasThreshold: number,
    minCostSavingBps: number,
    maxSlippageBps: number,
    timeHorizon: number,
    riskPenalty: number
  ): Promise<ethers.ContractTransactionResponse>;
}

export interface MockUSDCInterface extends ethers.Contract {
  // ERC20 functions
  balanceOf(account: string): Promise<string>;
  allowance(owner: string, spender: string): Promise<string>;
  approve(spender: string, amount: string): Promise<ethers.ContractTransactionResponse>;
  transfer(to: string, amount: string): Promise<ethers.ContractTransactionResponse>;
  transferFrom(from: string, to: string, amount: string): Promise<ethers.ContractTransactionResponse>;
  
  // Mock functions
  mint(to: string, amount: string): Promise<ethers.ContractTransactionResponse>;
  decimals(): Promise<number>;
  symbol(): Promise<string>;
  name(): Promise<string>;
  totalSupply(): Promise<string>;
}