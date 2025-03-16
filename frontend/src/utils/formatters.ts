/**
 * Utility functions for formatting values
 */

/**
 * Format a number as currency
 * @param value The value to format
 * @param decimals Number of decimal places to show
 * @param currency Currency symbol to use
 * @returns Formatted currency string
 */
export const formatCurrency = (
  value: number | string, 
  decimals: number = 2, 
  currency: string = '$'
): string => {
  const numValue = typeof value === 'string' ? parseFloat(value) : value;
  
  if (isNaN(numValue)) {
    return `${currency}0.00`;
  }
  
  // Format with commas and fixed decimal places
  return `${currency}${numValue.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  })}`;
};

/**
 * Format a percentage value
 * @param value The percentage value to format
 * @param decimals Number of decimal places to show
 * @returns Formatted percentage string
 */
export const formatPercentage = (
  value: number | string,
  decimals: number = 2
): string => {
  const numValue = typeof value === 'string' ? parseFloat(value) : value;
  
  if (isNaN(numValue)) {
    return '0.00%';
  }
  
  return `${numValue.toFixed(decimals)}%`;
};

/**
 * Format a date from a timestamp
 * @param timestamp Unix timestamp in seconds or milliseconds
 * @returns Formatted date string
 */
export const formatDate = (timestamp: number): string => {
  // Check if timestamp is in seconds (Ethereum timestamps) and convert to milliseconds if needed
  const timestampMs = timestamp > 1000000000000 ? timestamp : timestamp * 1000;
  
  return new Date(timestampMs).toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
};

/**
 * Truncate an Ethereum address
 * @param address The address to truncate
 * @param startChars Number of characters to show at the start
 * @param endChars Number of characters to show at the end
 * @returns Truncated address string
 */
export const truncateAddress = (
  address: string,
  startChars: number = 6,
  endChars: number = 4
): string => {
  if (!address) return '';
  
  if (address.length <= startChars + endChars) {
    return address;
  }
  
  return `${address.slice(0, startChars)}...${address.slice(-endChars)}`;
};
