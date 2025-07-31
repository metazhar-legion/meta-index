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

// Contract interface types - simplified to use ethers.Contract directly
export type ComposableRWABundleInterface = ethers.Contract;
export type TRSExposureStrategyInterface = ethers.Contract;
export type DirectTokenStrategyInterface = ethers.Contract;
export type EnhancedPerpetualStrategyInterface = ethers.Contract;
export type StrategyOptimizerInterface = ethers.Contract;
export type MockUSDCInterface = ethers.Contract;