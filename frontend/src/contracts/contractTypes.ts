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
  // ERC4626 methods
  deposit: (assets: ethers.BigNumber, receiver: string) => Promise<ethers.ContractTransaction>;
  withdraw: (assets: ethers.BigNumber, receiver: string, owner: string) => Promise<ethers.ContractTransaction>;
  redeem: (shares: ethers.BigNumber, receiver: string, owner: string) => Promise<ethers.ContractTransaction>;
  mint: (shares: ethers.BigNumber, receiver: string) => Promise<ethers.ContractTransaction>;
  
  // View methods
  totalAssets: () => Promise<ethers.BigNumber>;
  convertToShares: (assets: ethers.BigNumber) => Promise<ethers.BigNumber>;
  convertToAssets: (shares: ethers.BigNumber) => Promise<ethers.BigNumber>;
  previewDeposit: (assets: ethers.BigNumber) => Promise<ethers.BigNumber>;
  previewMint: (shares: ethers.BigNumber) => Promise<ethers.BigNumber>;
  previewWithdraw: (assets: ethers.BigNumber) => Promise<ethers.BigNumber>;
  previewRedeem: (shares: ethers.BigNumber) => Promise<ethers.BigNumber>;
  maxDeposit: (receiver: string) => Promise<ethers.BigNumber>;
  maxMint: (receiver: string) => Promise<ethers.BigNumber>;
  maxWithdraw: (owner: string) => Promise<ethers.BigNumber>;
  maxRedeem: (owner: string) => Promise<ethers.BigNumber>;
  
  // Custom methods
  rebalance: () => Promise<ethers.ContractTransaction>;
  collectManagementFee: () => Promise<ethers.ContractTransaction>;
  collectPerformanceFee: () => Promise<ethers.ContractTransaction>;
  setManagementFee: (newFee: ethers.BigNumber) => Promise<ethers.ContractTransaction>;
  setPerformanceFee: (newFee: ethers.BigNumber) => Promise<ethers.ContractTransaction>;
  setPriceOracle: (newOracle: string) => Promise<ethers.ContractTransaction>;
  setDEX: (newDEX: string) => Promise<ethers.ContractTransaction>;
  
  // Events
  filters: {
    Deposit: (sender?: string, owner?: string, assets?: ethers.BigNumber, shares?: ethers.BigNumber) => ethers.EventFilter;
    Withdraw: (sender?: string, receiver?: string, owner?: string, assets?: ethers.BigNumber, shares?: ethers.BigNumber) => ethers.EventFilter;
  };
}

// IndexRegistry interface
export interface IndexRegistryInterface {
  // View methods
  getTokens: () => Promise<string[]>;
  getTokenWeight: (token: string) => Promise<ethers.BigNumber>;
  getTokensWithWeights: () => Promise<[string[], ethers.BigNumber[]]>;
  
  // Mutative methods
  addToken: (token: string, weight: ethers.BigNumber) => Promise<ethers.ContractTransaction>;
  removeToken: (token: string) => Promise<ethers.ContractTransaction>;
  updateTokenWeight: (token: string, newWeight: ethers.BigNumber) => Promise<ethers.ContractTransaction>;
  
  // Events
  filters: {
    TokenAdded: (token?: string, weight?: ethers.BigNumber) => ethers.EventFilter;
    TokenRemoved: (token?: string) => ethers.EventFilter;
    TokenWeightUpdated: (token?: string, newWeight?: ethers.BigNumber) => ethers.EventFilter;
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
