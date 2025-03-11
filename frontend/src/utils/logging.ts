/**
 * Standardized logging utilities for consistent debugging and monitoring
 */

// Log levels
enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

// Current log level - can be adjusted based on environment
const CURRENT_LOG_LEVEL = process.env.NODE_ENV === 'production' 
  ? LogLevel.WARN  // Only log warnings and errors in production
  : LogLevel.DEBUG; // Log everything in development

// Standardized logger with consistent formatting
class Logger {
  private context: string;
  
  constructor(context: string) {
    this.context = context;
  }
  
  // Debug level logs - only shown in development
  debug(message: string, ...args: any[]): void {
    if (CURRENT_LOG_LEVEL <= LogLevel.DEBUG) {
      console.debug(`[${this.context}] 🔍 ${message}`, ...args);
    }
  }
  
  // Info level logs - general information
  info(message: string, ...args: any[]): void {
    if (CURRENT_LOG_LEVEL <= LogLevel.INFO) {
      console.info(`[${this.context}] ℹ️ ${message}`, ...args);
    }
  }
  
  // Warning level logs - potential issues
  warn(message: string, ...args: any[]): void {
    if (CURRENT_LOG_LEVEL <= LogLevel.WARN) {
      console.warn(`[${this.context}] ⚠️ ${message}`, ...args);
    }
  }
  
  // Error level logs - critical issues
  error(message: string, error?: any, ...args: any[]): void {
    if (CURRENT_LOG_LEVEL <= LogLevel.ERROR) {
      console.error(`[${this.context}] 🔴 ${message}`, error, ...args);
    }
  }
  
  // Log contract interactions with consistent format
  logContractCall(method: string, args: any[] = [], result?: any): void {
    this.debug(`Contract Call: ${method}`, {
      arguments: args,
      result: result || 'pending'
    });
  }
  
  // Log transaction details
  logTransaction(txHash: string, method: string, status: 'sent' | 'confirmed' | 'failed'): void {
    const emoji = status === 'sent' ? '📤' : status === 'confirmed' ? '✅' : '❌';
    this.info(`Transaction ${status} ${emoji} - ${method} (${txHash})`);
  }
  
  // Log user actions
  logUserAction(action: string, details?: any): void {
    this.info(`User Action: ${action}`, details);
  }
}

// Create logger factory
export const createLogger = (context: string): Logger => {
  return new Logger(context);
};

// Global error handler for unexpected errors
export const setupGlobalErrorLogging = (): void => {
  const logger = createLogger('GlobalErrorHandler');
  
  // Handle uncaught promise rejections
  window.addEventListener('unhandledrejection', (event) => {
    logger.error('Unhandled Promise Rejection', event.reason);
  });
  
  // Handle uncaught exceptions
  window.addEventListener('error', (event) => {
    logger.error('Uncaught Error', event.error);
  });
};
