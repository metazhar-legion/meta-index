import { ethers } from 'ethers';

// Token interface
export interface Token {
  address: string;
  symbol: string;
  decimals: number;
  weight?: number;
}

// IndexFundVault interface
export interface IndexFundVaultInterface {
  // ERC20 methods
  balanceOf: (account: string) => Promise<bigint>;
  totalSupply: () => Promise<bigint>;
  
  // ERC4626 methods
  deposit: (assets: bigint, receiver: string) => Promise<ethers.ContractTransactionResponse>;
  withdraw: (assets: bigint, receiver: string, owner: string) => Promise<ethers.ContractTransactionResponse>;
  redeem: (shares: bigint, receiver: string, owner: string) => Promise<ethers.ContractTransactionResponse>;
  mint: (shares: bigint, receiver: string) => Promise<ethers.ContractTransactionResponse>;
  
  // View methods
  totalAssets: () => Promise<bigint>;
  convertToShares: (assets: bigint) => Promise<bigint>;
  convertToAssets: (shares: bigint) => Promise<bigint>;
  previewDeposit: (assets: bigint) => Promise<bigint>;
  previewMint: (shares: bigint) => Promise<bigint>;
  previewWithdraw: (assets: bigint) => Promise<bigint>;
  previewRedeem: (shares: bigint) => Promise<bigint>;
  maxDeposit: (receiver: string) => Promise<bigint>;
  maxMint: (receiver: string) => Promise<bigint>;
  maxWithdraw: (owner: string) => Promise<bigint>;
  maxRedeem: (owner: string) => Promise<bigint>;
  
  // Custom methods
  rebalance: () => Promise<ethers.ContractTransactionResponse>;
  collectManagementFee: () => Promise<ethers.ContractTransactionResponse>;
  collectPerformanceFee: () => Promise<ethers.ContractTransactionResponse>;
  setManagementFee: (newFee: bigint) => Promise<ethers.ContractTransactionResponse>;
  setPerformanceFee: (newFee: bigint) => Promise<ethers.ContractTransactionResponse>;
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
  // View methods
  getTokens: () => Promise<string[]>;
  getTokenWeight: (token: string) => Promise<bigint>;
  getTokensWithWeights: () => Promise<[string[], bigint[]]>;
  
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
  "function name() view returns (string)",
  "function symbol() view returns (string)",
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
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function maxMint(address receiver) view returns (uint256)",
  "function previewMint(uint256 shares) view returns (uint256)",
  "function mint(uint256 shares, address receiver) returns (uint256)",
  "function maxWithdraw(address owner) view returns (uint256)",
  "function previewWithdraw(uint256 assets) view returns (uint256)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
  "function maxRedeem(address owner) view returns (uint256)",
  "function previewRedeem(uint256 shares) view returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
  
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
  "function getTokens() view returns (address[])",
  "function getTokenWeight(address token) view returns (uint256)",
  "function getTokensWithWeights() view returns (address[], uint256[])",
  
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
  "function name() view returns (string)",
  "function symbol() view returns (string)",
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
