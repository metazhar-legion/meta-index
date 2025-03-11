import { ethers } from 'ethers';

/**
 * Standardized formatting utilities for consistent display across components
 */

// Format currency values with proper decimals
export const formatCurrency = (
  value: string | number | bigint | null | undefined,
  decimals: number = 2,
  prefix: string = '$'
): string => {
  if (value === null || value === undefined) return `${prefix}0.00`;
  
  let numValue: number;
  
  try {
    if (typeof value === 'bigint') {
      // Convert BigInt to string first to avoid precision issues
      numValue = parseFloat(value.toString());
    } else if (typeof value === 'string') {
      numValue = parseFloat(value);
    } else {
      numValue = value;
    }
    
    // Check for NaN
    if (isNaN(numValue)) return `${prefix}0.00`;
    
    return `${prefix}${new Intl.NumberFormat('en-US', {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    }).format(numValue)}`;
  } catch (error) {
    console.error('Error formatting currency:', error);
    return `${prefix}0.00`;
  }
};

// Format token amounts based on decimals
export const formatTokenAmount = (
  amount: bigint | string | number | null | undefined,
  decimals: number = 18,
  maxDecimals: number = 4
): string => {
  try {
    if (amount === null || amount === undefined) return '0';
    
    let formattedAmount: string;
    
    if (typeof amount === 'bigint') {
      formattedAmount = ethers.formatUnits(amount, decimals);
    } else if (typeof amount === 'string') {
      // Check if the string is a valid number
      if (!/^-?\d+(\.\d+)?$/.test(amount)) {
        return '0';
      }
      
      // Check if it's already formatted or needs to be divided by 10^decimals
      if (amount.includes('.')) {
        formattedAmount = amount;
      } else {
        formattedAmount = ethers.formatUnits(amount, decimals);
      }
    } else {
      formattedAmount = amount.toString();
    }
    
    // Format with Intl.NumberFormat for proper thousand separators
    const numValue = parseFloat(formattedAmount);
    return new Intl.NumberFormat('en-US', {
      minimumFractionDigits: 0,
      maximumFractionDigits: maxDecimals,
    }).format(numValue);
  } catch (error) {
    console.error('Error formatting token amount:', error, 'Value was:', amount);
    return '0';
  }
};

// Format addresses for display
export const formatAddress = (address: string | null | undefined): string => {
  if (!address) return '';
  return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
};

// Format percentages
export const formatPercent = (
  value: number | string | null | undefined,
  decimals: number = 2
): string => {
  if (value === null || value === undefined) return '0%';
  
  let numValue: number;
  
  try {
    numValue = typeof value === 'string' ? parseFloat(value) : value;
    
    // Check for NaN
    if (isNaN(numValue)) return '0%';
    
    return `${numValue.toFixed(decimals)}%`;
  } catch (error) {
    console.error('Error formatting percentage:', error);
    return '0%';
  }
};

// Convert from token decimals to human-readable format
export const convertFromTokenDecimals = (
  amount: string | number | bigint,
  decimals: number = 18
): string => {
  try {
    return ethers.formatUnits(amount.toString(), decimals);
  } catch (error) {
    console.error('Error converting from token decimals:', error);
    return '0';
  }
};

// Convert to token decimals from human-readable format
export const convertToTokenDecimals = (
  amount: string | number,
  decimals: number = 18
): bigint => {
  try {
    return ethers.parseUnits(amount.toString(), decimals);
  } catch (error) {
    console.error('Error converting to token decimals:', error);
    return BigInt(0);
  }
};
