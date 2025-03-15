import { ethers } from 'ethers';

// Token interface
export interface Token {
  address: string;
  symbol: string;
  decimals: number;
  weight?: number;
  color?: string;
}

// Helper type for handling different return formats from ethers.js v6
export type BigIntish = bigint | string | number;

// Helper function to convert various return types to BigInt with enhanced error handling
export function toBigInt(value: any): bigint {
  try {
    // Handle null/undefined
    if (value === undefined || value === null) {
      return BigInt(0);
    }
    
    // Handle BigInt directly
    if (typeof value === 'bigint') {
      return value;
    }
    
    // Handle strings and numbers
    if (typeof value === 'string') {
      // Handle hex strings (with or without 0x prefix)
      if (value.startsWith('0x')) {
        return BigInt(value);
      }
      // Handle numeric strings
      if (/^-?\d+(\.\d+)?$/.test(value)) {
        // If it has a decimal point, we need to handle it specially
        if (value.includes('.')) {
          // For simplicity, just truncate the decimal part
          return BigInt(value.split('.')[0]);
        }
        return BigInt(value);
      }
      // Try parsing as is
      return BigInt(value);
    }
    
    if (typeof value === 'number') {
      // Handle NaN and Infinity
      if (isNaN(value) || !isFinite(value)) {
        return BigInt(0);
      }
      // Convert to string to avoid precision issues with large numbers
      return BigInt(Math.floor(value).toString());
    }
    
    // Handle arrays
    if (Array.isArray(value)) {
      if (value.length === 0) {
        return BigInt(0);
      }
      
      // Try to find the first convertible value
      for (const item of value) {
        try {
          return toBigInt(item);
        } catch (e) {
          // Continue to the next item
        }
      }
      
      // If we get here, no items could be converted
      return BigInt(0);
    }
    
    // Handle objects
    if (typeof value === 'object') {
      // Check for ethers.js Result object (has a _value property)
      if ('_value' in value) {
        return toBigInt(value._value);
      }
      
      // Check for objects with a toString method that might return a numeric string
      if (value.toString && typeof value.toString === 'function') {
        const stringValue = value.toString();
        // Only use toString if it looks like a number
        if (/^-?\d+(\.\d+)?$/.test(stringValue) || stringValue.startsWith('0x')) {
          try {
            return BigInt(stringValue);
          } catch (e) {
            // Silent fail and continue with other conversion methods
          }
        }
      }
      
      // Try to extract a numeric value from the object
      const objValues = Object.values(value);
      if (objValues.length > 0) {
        // Try each value until we find one that converts
        for (const objValue of objValues) {
          try {
            return toBigInt(objValue);
          } catch (e) {
            // Continue to the next value
            console.debug('toBigInt: skipping object value that cannot be converted:', objValue);
          }
        }
      }
    }
    
    // If we get here, we couldn't convert the value
    console.warn('Could not convert value to BigInt:', value);
    return BigInt(0);
  } catch (error) {
    console.error('Error in toBigInt conversion:', error, 'for value:', value);
    return BigInt(0);
  }
}

// IndexFundVault interface
export interface IndexFundVaultInterface {
  // Contract properties
  target: string;  // The contract address
  runner?: ethers.Provider | ethers.Signer;  // The provider or signer
  
  // ERC20 methods
  balanceOf: (account: string) => Promise<any>; // Use 'any' to handle different return formats
  totalSupply: () => Promise<any>; // Use 'any' to handle different return formats
  
  // ERC4626 methods
  deposit: (assets: BigIntish, receiver: string) => Promise<ethers.ContractTransactionResponse>;
  withdraw: (assets: BigIntish, receiver: string, owner: string) => Promise<ethers.ContractTransactionResponse>;
  redeem: (shares: BigIntish, receiver: string, owner: string) => Promise<ethers.ContractTransactionResponse>;
  mint: (shares: BigIntish, receiver: string) => Promise<ethers.ContractTransactionResponse>;
  
  // View methods
  totalAssets: () => Promise<any>; // Use 'any' to handle different return formats
  convertToShares: (assets: BigIntish) => Promise<any>;
  convertToAssets: (shares: BigIntish) => Promise<any>;
  previewDeposit: (assets: BigIntish) => Promise<any>;
  previewMint: (shares: BigIntish) => Promise<any>;
  previewWithdraw: (assets: BigIntish) => Promise<any>;
  previewRedeem: (shares: BigIntish) => Promise<any>;
  maxDeposit: (receiver: string) => Promise<any>;
  maxMint: (receiver: string) => Promise<any>;
  maxWithdraw: (owner: string) => Promise<any>;
  maxRedeem: (owner: string) => Promise<any>;
  
  // Custom methods
  rebalance: () => Promise<ethers.ContractTransactionResponse>;
  collectManagementFee: () => Promise<ethers.ContractTransactionResponse>;
  collectPerformanceFee: () => Promise<ethers.ContractTransactionResponse>;
  setManagementFee: (newFee: BigIntish) => Promise<ethers.ContractTransactionResponse>;
  setPerformanceFee: (newFee: BigIntish) => Promise<ethers.ContractTransactionResponse>;
  setPriceOracle: (newOracle: string) => Promise<ethers.ContractTransactionResponse>;
  setDEX: (newDEX: string) => Promise<ethers.ContractTransactionResponse>;
  
  // Events
  filters: {
    Deposit: (sender?: string, owner?: string, assets?: bigint, shares?: bigint) => ethers.EventFilter;
    Withdraw: (sender?: string, receiver?: string, owner?: string, assets?: bigint, shares?: bigint) => ethers.EventFilter;
  };
}

// IndexRegistry interface
export interface IndexRegistryInterface {
  // Contract properties
  target: string;  // The contract address
  runner?: ethers.Provider | ethers.Signer;  // The provider or signer
  
  // View methods
  getTokens: () => Promise<string[]>;
  getTokenWeight: (token: string) => Promise<bigint>;
  getTokensWithWeights: () => Promise<[string[], bigint[]]>;
  // Add support for different return types from getTokensWithWeights
  // This is needed because ethers.js v6 might return objects instead of arrays
  
  // Mutative methods
  addToken: (token: string, weight: bigint) => Promise<ethers.ContractTransactionResponse>;
  removeToken: (token: string) => Promise<ethers.ContractTransactionResponse>;
  updateTokenWeight: (token: string, newWeight: bigint) => Promise<ethers.ContractTransactionResponse>;
  
  // Events
  filters: {
    TokenAdded: (token?: string, weight?: bigint) => ethers.EventFilter;
    TokenRemoved: (token?: string) => ethers.EventFilter;
    TokenWeightUpdated: (token?: string, newWeight?: bigint) => ethers.EventFilter;
  };
}

// Contract ABIs
export const IndexFundVaultABI = [
  // ERC20 functions
  "function name() view returns (string memory)",
  "function symbol() view returns (string memory)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transferFrom(address from, address to, uint256 amount) returns (bool)",
  
  // ERC4626 functions
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function convertToShares(uint256 assets) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function maxDeposit(address receiver) view returns (uint256)",
  "function previewDeposit(uint256 assets) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256 shares)",
  "function maxMint(address receiver) view returns (uint256)",
  "function previewMint(uint256 shares) view returns (uint256)",
  "function mint(uint256 shares, address receiver) returns (uint256 assets)",
  "function maxWithdraw(address owner) view returns (uint256)",
  "function previewWithdraw(uint256 assets) view returns (uint256)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256 shares)",
  "function maxRedeem(address owner) view returns (uint256)",
  "function previewRedeem(uint256 shares) view returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)",
  
  // Custom functions
  "function rebalance() external",
  "function collectManagementFee() external returns (uint256)",
  "function collectPerformanceFee() external returns (uint256)",
  "function setManagementFee(uint256 newFee) external",
  "function setPerformanceFee(uint256 newFee) external",
  "function setPriceOracle(address newOracle) external",
  "function setDEX(address newDEX) external",
  
  // Events
  "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
  "event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)"
];

export const IndexRegistryABI = [
  // View functions
  "function getTokens() view returns (address[] memory)",
  "function getTokenWeight(address token) view returns (uint256)",
  "function getTokensWithWeights() view returns (address[] memory tokens, uint256[] memory weights)",
  
  // Mutative functions
  "function addToken(address token, uint256 weight) external",
  "function removeToken(address token) external",
  "function updateTokenWeight(address token, uint256 newWeight) external",
  
  // Events
  "event TokenAdded(address indexed token, uint256 weight)",
  "event TokenRemoved(address indexed token)",
  "event TokenWeightUpdated(address indexed token, uint256 newWeight)"
];

// ERC20 ABI for interacting with tokens
export const ERC20ABI = [
  "function name() view returns (string memory)",
  "function symbol() view returns (string memory)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transferFrom(address from, address to, uint256 amount) returns (bool)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Approval(address indexed owner, address indexed spender, uint256 value)"
];
