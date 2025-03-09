// Global TypeScript declarations

interface Window {
  ethereum?: any;
}

// Extend the global namespace
declare global {
  interface Window {
    ethereum?: any;
  }
}

export {};
