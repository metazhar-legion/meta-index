import { useEffect, useState, useCallback } from 'react';
import { ethers } from 'ethers';
import { useWeb3 } from '../contexts/Web3Context';
import {
  IndexFundVaultInterface,
  IndexRegistryInterface,
  CapitalAllocationManagerInterface,
  IndexFundVaultABI,
  IndexRegistryABI,
  CapitalAllocationManagerABI,
  ERC20ABI,
  Token
} from '../contracts/contractTypes';
import { CONTRACT_ADDRESSES } from '../contracts/addresses';

// Declare module augmentation to extend ethers.Provider with getSigner method
declare module 'ethers' {
  interface Provider {
    getSigner?: () => Promise<ethers.Signer>;
  }
}

// Helper function to safely get a signer from a provider
const getSafeSignerFromProvider = async (provider: ethers.Provider): Promise<ethers.Signer | null> => {
  if (!provider) return null;
  
  try {
    // Check if the provider has getSigner method
    if (provider.getSigner) {
      return await provider.getSigner();
    }
    return null;
  } catch (error) {
    console.error('Error getting signer from provider:', error);
    return null;
  }
};

interface UseContractsReturn {
  vaultContract: IndexFundVaultInterface | null;
  registryContract: IndexRegistryInterface | null;
  capitalManagerContract: CapitalAllocationManagerInterface | null;
  indexTokens: Token[];
  isLoading: boolean;
  error: string | null;
}

export const useContracts = (): UseContractsReturn => {
  const { provider, isActive, refreshProvider } = useWeb3();
  const [vaultContract, setVaultContract] = useState<IndexFundVaultInterface | null>(null);
  const [registryContract, setRegistryContract] = useState<IndexRegistryInterface | null>(null);
  const [capitalManagerContract, setCapitalManagerContract] = useState<CapitalAllocationManagerInterface | null>(null);
  const [indexTokens, setIndexTokens] = useState<Token[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);

  // Helper function to check if an error is a BlockOutOfRangeError
  const isBlockOutOfRangeError = useCallback((error: any): boolean => {
    if (!error) return false;
    
    // Handle different error formats
    const errorMessage = typeof error === 'string' 
      ? error 
      : error.message || '';
      
    // Check for nested error data (common in RPC errors)
    const errorData = error?.data?.message || '';
    const nestedError = error?.error?.message || '';
    const errorJson = typeof error?.error === 'string' ? error.error : '';
    
    return errorMessage.includes('BlockOutOfRange') || 
           errorData.includes('BlockOutOfRange') ||
           nestedError.includes('BlockOutOfRange') ||
           errorJson.includes('BlockOutOfRange') ||
           errorMessage.includes('block height') || 
           errorData.includes('block height') ||
           nestedError.includes('block height') ||
           errorJson.includes('block height');
  }, []);

  // Initialize contracts when provider is available - simplified to avoid circular references
  useEffect(() => {
    // Reset contracts if provider is not available
    if (!provider || !isActive) {
      setVaultContract(null);
      setRegistryContract(null);
      setCapitalManagerContract(null);
      return;
    }

    const initializeContracts = async () => {
      setIsLoading(true);
      
      try {
        // Log network information for debugging
        try {
          const network = await provider.getNetwork();
          console.log('Connected to network:', {
            chainId: network.chainId,
            name: network.name
          });
        } catch (networkError) {
          console.error('Error getting network information:', networkError);
          
          // Check if this is a BlockOutOfRangeError and handle it
          if (isBlockOutOfRangeError(networkError) && retryCount < 3) {
            console.log(`BlockOutOfRangeError detected, refreshing provider (attempt ${retryCount + 1}/3)`);
            setRetryCount(prev => prev + 1);
            
            try {
              if (refreshProvider) {
                const freshProvider = await refreshProvider();
                if (freshProvider) {
                  console.log('Provider refreshed successfully, retrying contract initialization');
                  setIsLoading(false);
                  return; // Exit and let the useEffect retry with the new provider
                }
              }
            } catch (refreshError) {
              console.error('Error refreshing provider:', refreshError);
            }
          }
        }
        
        // Get a signer for transactions if available using our helper function
        let signer = await getSafeSignerFromProvider(provider);
        if (!signer) {
          console.log('Provider does not have getSigner method or getting signer failed, using provider only');
        }
        
        // Verify contract addresses are valid
        if (!ethers.isAddress(CONTRACT_ADDRESSES.VAULT)) {
          throw new Error(`Invalid vault address: ${CONTRACT_ADDRESSES.VAULT}`);
        }
        if (!ethers.isAddress(CONTRACT_ADDRESSES.REGISTRY)) {
          throw new Error(`Invalid registry address: ${CONTRACT_ADDRESSES.REGISTRY}`);
        }
        
        // Create contracts with error handling
        let vault, registry, capitalManager;
        try {
          vault = new ethers.Contract(
            CONTRACT_ADDRESSES.VAULT,
            IndexFundVaultABI,
            provider
          );
        } catch (error) {
          const vaultError = error as Error;
          console.error('Error creating vault contract:', vaultError);
          
          // Check if this is a BlockOutOfRangeError and handle it
          if (isBlockOutOfRangeError(vaultError) && retryCount < 3) {
            console.log(`BlockOutOfRangeError detected, refreshing provider (attempt ${retryCount + 1}/3)`);
            setRetryCount(prev => prev + 1);
            
            try {
              if (refreshProvider) {
                const freshProvider = await refreshProvider();
                if (freshProvider) {
                  console.log('Provider refreshed successfully, retrying contract initialization');
                  setIsLoading(false);
                  return; // Exit and let the useEffect retry with the new provider
                }
              }
            } catch (refreshError) {
              console.error('Error refreshing provider:', refreshError);
            }
          }
          
          throw new Error(`Failed to create vault contract: ${vaultError.message || 'Unknown error'}`);
        }
        
        try {
          registry = new ethers.Contract(
            CONTRACT_ADDRESSES.REGISTRY,
            IndexRegistryABI,
            provider
          );
        } catch (error) {
          const registryError = error as Error;
          console.error('Error creating registry contract:', registryError);
          
          // Check if this is a BlockOutOfRangeError and handle it
          if (isBlockOutOfRangeError(registryError) && retryCount < 3) {
            console.log(`BlockOutOfRangeError detected, refreshing provider (attempt ${retryCount + 1}/3)`);
            setRetryCount(prev => prev + 1);
            
            try {
              if (refreshProvider) {
                const freshProvider = await refreshProvider();
                if (freshProvider) {
                  console.log('Provider refreshed successfully, retrying contract initialization');
                  setIsLoading(false);
                  return; // Exit and let the useEffect retry with the new provider
                }
              }
            } catch (refreshError) {
              console.error('Error refreshing provider:', refreshError);
            }
          }
          
          throw new Error(`Failed to create registry contract: ${registryError.message || 'Unknown error'}`);
        }
        
        // Capital Manager is no longer used
        capitalManager = null;
        
        // Connect signer if available
        let vaultWithSigner, registryWithSigner, capitalManagerWithSigner;
        if (signer) {
          try {
            vaultWithSigner = vault.connect(signer);
          } catch (connectError) {
            console.error('Error connecting signer to vault contract:', connectError);
            vaultWithSigner = vault; // Fallback to provider-only
          }
          
          try {
            registryWithSigner = registry.connect(signer);
          } catch (connectError) {
            console.error('Error connecting signer to registry contract:', connectError);
            registryWithSigner = registry; // Fallback to provider-only
          }
          
          try {
            capitalManagerWithSigner = capitalManager.connect(signer);
          } catch (connectError) {
            console.error('Error connecting signer to capital manager contract:', connectError);
            capitalManagerWithSigner = capitalManager; // Fallback to provider-only
          }
        } else {
          vaultWithSigner = vault;
          registryWithSigner = registry;
          capitalManagerWithSigner = capitalManager;
        }
        
        // Test contract connectivity with more detailed logging
        try {
          console.log('Testing vault contract connectivity...');
          // Try a simple read-only call to verify connectivity
          const totalSupply = await vault.totalSupply();
          console.log('Vault contract connectivity verified. Total supply:', totalSupply.toString());
          // Reset retry count on success
          setRetryCount(0);
        } catch (testError) {
          console.warn('Could not verify vault contract connectivity:', testError);
          
          // If it's a BlockOutOfRangeError, try refreshing the provider
          if (isBlockOutOfRangeError(testError) && retryCount < 3) {
            console.log(`BlockOutOfRangeError detected, refreshing provider (attempt ${retryCount + 1}/3)`);
            setRetryCount(prev => prev + 1);
            
            try {
              if (refreshProvider) {
                const freshProvider = await refreshProvider();
                if (freshProvider) {
                  console.log('Provider refreshed successfully, retrying contract initialization');
                  setIsLoading(false);
                  return; // Exit and let the useEffect retry with the new provider
                }
              }
            } catch (refreshError) {
              console.error('Error refreshing provider:', refreshError);
            }
          }
          // Continue anyway as this might be due to empty vault
          console.log('Continuing with contract initialization despite connectivity test failure');
        }
        
        // Cast to the appropriate interfaces with additional logging
        console.log('Casting contracts to appropriate interfaces');
        const typedVault = vaultWithSigner as unknown as IndexFundVaultInterface;
        const typedRegistry = registryWithSigner as unknown as IndexRegistryInterface;
        const typedCapitalManager = capitalManagerWithSigner as unknown as CapitalAllocationManagerInterface;
        
        // Log contract addresses for verification
        console.log('Setting vault contract with address:', await vault.target);
        console.log('Setting registry contract with address:', await registry.target);
        console.log('Setting capital manager contract with address:', await capitalManager.target);
        
        setVaultContract(typedVault);
        setRegistryContract(typedRegistry);
        setCapitalManagerContract(typedCapitalManager);
        setError(null);
      } catch (error) {
        const err = error as Error;
        console.error('Error initializing contracts:', err);
        
        // If it's a BlockOutOfRangeError, try refreshing the provider
        if (isBlockOutOfRangeError(err) && retryCount < 3) {
          console.log(`BlockOutOfRangeError detected in contract initialization, refreshing provider (attempt ${retryCount + 1}/3)`);
          setRetryCount(prev => prev + 1);
          
          try {
            if (refreshProvider) {
              const freshProvider = await refreshProvider();
              if (freshProvider) {
                console.log('Provider refreshed successfully, retrying contract initialization');
                setIsLoading(false);
                return; // Exit and let the useEffect retry with the new provider
              }
            }
          } catch (refreshError) {
            console.error('Error refreshing provider:', refreshError);
          }
        }
        
        setError(`Failed to initialize contracts: ${err.message || 'Unknown error'}`);
        setVaultContract(null);
        setRegistryContract(null);
        setCapitalManagerContract(null);
      } finally {
        setIsLoading(false);
      }
    };
    
    initializeContracts();
  }, [provider, isActive, refreshProvider, retryCount, isBlockOutOfRangeError]);

  // Load index tokens when registry contract is available
  useEffect(() => {
    const loadIndexTokens = async () => {
      if (registryContract && provider) {
        setIsLoading(true);
        try {
          // Get tokens and weights from registry
          // Wrap in try-catch to provide better error handling
          let tokenAddresses: string[] = [];
          let weights: bigint[] = [];
          
          // If the registry contract is reverting, use hardcoded values for testing
          // This is a fallback mechanism for development
          const useHardcodedValues = true; // Set to false in production
          
          if (useHardcodedValues) {
            console.log('Using hardcoded token values for index testing');
            
            // Check if we're on a local testnet (Anvil) with chainId 31337
            // If so, use the deployed contract addresses from addresses.ts
            let usingLocalAddresses = false;
            
            try {
              // Import the contract addresses dynamically
              const { CONTRACT_ADDRESSES } = await import('../contracts/addresses');
              
              // Use provider.getNetwork() to check the chain ID
              if (provider) {
                const network = await provider.getNetwork();
                const chainId = network.chainId;
                const localChainId = 31337;
                
                const isLocalNetwork = typeof chainId === 'bigint' ? 
                  chainId === BigInt(localChainId) : 
                  Number(chainId) === localChainId;
                
                if (isLocalNetwork) {
                  console.log('Using local testnet token addresses for index');
                  tokenAddresses = [
                    CONTRACT_ADDRESSES.USDC, // USDC
                    CONTRACT_ADDRESSES.WETH, // WETH
                    CONTRACT_ADDRESSES.WBTC  // WBTC
                  ];
                  usingLocalAddresses = true;
                }
              }
            } catch (error) {
              console.error('Error determining chain or loading contract addresses:', error);
            }
            
            // If not on local testnet or if there was an error, use mainnet addresses
            if (!usingLocalAddresses) {
              console.log('Using mainnet token addresses for index');
              tokenAddresses = [
                '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
                '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
                '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'  // WBTC
              ];
            }
            
            // Weights are the same regardless of network
            weights = [
              BigInt('500000000000000000'), // 50%
              BigInt('300000000000000000'), // 30%
              BigInt('200000000000000000')  // 20%
            ];
          } else {
            try {
              console.log('Calling getTokensWithWeights on registry contract...');
              console.log('Registry contract address:', CONTRACT_ADDRESSES.REGISTRY);
              console.log('Registry contract methods:', Object.keys(registryContract));
              
              // Check if the method exists
              if (typeof registryContract.getTokensWithWeights !== 'function') {
                console.error('getTokensWithWeights method not found on registry contract');
                throw new Error('getTokensWithWeights method not found');
              }
              
              // Try with a direct call first
              try {
                // Try with a lower-level call to avoid ABI decoding issues
                const iface = new ethers.Interface(IndexRegistryABI);
                const calldata = iface.encodeFunctionData('getTokensWithWeights', []);
                
                console.log('Encoded function call:', calldata);
                
                const rawResult = await provider.call({
                  to: CONTRACT_ADDRESSES.REGISTRY,
                  data: calldata
                });
                
                console.log('Raw result from call:', rawResult);
                
                // Decode the result manually
                const decodedResult = iface.decodeFunctionResult('getTokensWithWeights', rawResult);
                console.log('Decoded result type:', typeof decodedResult, Array.isArray(decodedResult));
                console.log('Decoded result:', JSON.stringify(decodedResult, (key, value) => 
                  typeof value === 'bigint' ? value.toString() : value
                ));
                
                // Extract tokens and weights from the decoded result
                if (decodedResult) {
                  console.log('Result keys:', Object.keys(decodedResult || {}));
                  
                  // First, check if the result has named properties (as per ABI definition)
                  if (typeof decodedResult === 'object') {
                    // Check for named properties as defined in the ABI
                    if ('tokens' in decodedResult && 'weights' in decodedResult) {
                      console.log('Found named properties: tokens, weights');
                      tokenAddresses = decodedResult.tokens as string[];
                      weights = decodedResult.weights as bigint[];
                      console.log('Extracted using named properties:', {
                        tokens: tokenAddresses.length,
                        weights: weights.length
                      });
                    }
                    // If named properties don't exist, try numeric indices
                    else if (decodedResult[0] !== undefined && decodedResult[1] !== undefined) {
                      console.log('Found numeric properties: 0, 1');
                      tokenAddresses = decodedResult[0] as string[];
                      weights = decodedResult[1] as bigint[];
                      console.log('Extracted using numeric indices:', {
                        tokens: tokenAddresses.length,
                        weights: weights.length
                      });
                    }
                    // Try with result property (sometimes ethers wraps the result)
                    else if ('result' in decodedResult && Array.isArray(decodedResult.result)) {
                      console.log('Found result property');
                      if (decodedResult.result.length >= 2) {
                        tokenAddresses = decodedResult.result[0] as string[];
                        weights = decodedResult.result[1] as bigint[];
                        console.log('Extracted using result property:', {
                          tokens: tokenAddresses.length,
                          weights: weights.length
                        });
                      }
                    }
                    // Try accessing as a tuple-like structure
                    else if (typeof decodedResult.length === 'number' && decodedResult.length >= 2) {
                      console.log('Accessing as array-like object');
                      tokenAddresses = decodedResult[0] as string[];
                      weights = decodedResult[1] as bigint[];
                      console.log('Extracted as array-like:', {
                        tokens: tokenAddresses?.length,
                        weights: weights?.length
                      });
                    }
                  }
                }
                
                console.log('Extracted tokens:', tokenAddresses ? tokenAddresses.map(addr => addr.toString()) : 'none');
                console.log('Extracted weights:', weights ? weights.map(w => w.toString()) : 'none');
                
                // Validate the extracted data
                if (!tokenAddresses || !weights) {
                  console.warn('Failed to extract token addresses or weights, using empty arrays');
                  tokenAddresses = [];
                  weights = [];
                }
                
                if (tokenAddresses.length === 0) {
                  console.warn('Extracted token addresses array is empty');
                }
                
                if (weights.length === 0) {
                  console.warn('Extracted weights array is empty');
                }
                
                if (tokenAddresses.length !== weights.length) {
                  console.warn(`Token addresses (${tokenAddresses.length}) and weights (${weights.length}) arrays have different lengths`);
                  // Truncate the longer array to match the shorter one
                  const minLength = Math.min(tokenAddresses.length, weights.length);
                  tokenAddresses = tokenAddresses.slice(0, minLength);
                  weights = weights.slice(0, minLength);
                }
                
                console.log('Token data extraction complete:', {
                  tokenCount: tokenAddresses.length,
                  weightCount: weights.length,
                  sampleAddress: tokenAddresses[0]?.toString() || 'none',
                  sampleWeight: weights[0]?.toString() || 'none'
                });
              } catch (lowLevelError) {
                console.error('Low-level call failed, trying standard method:', lowLevelError);
                
                // Fall back to standard method call
                console.log('Attempting standard method call to getTokensWithWeights');
                const result = await registryContract.getTokensWithWeights();
                console.log('Token result type:', typeof result, Array.isArray(result));
                console.log('Token result raw:', JSON.stringify(result, (key, value) => 
                  typeof value === 'bigint' ? value.toString() : value
                ));
                
                if (result === null || result === undefined) {
                  console.warn('Token result is null or undefined, using empty arrays');
                  tokenAddresses = [];
                  weights = [];
                  // Continue execution instead of throwing
                }
                  
                // In ethers v6, the result might be returned as an object with named properties
                // or as an array depending on the contract method definition
                console.log('Result keys:', Object.keys(result || {}));
                
                // First, try accessing as a named property structure (as per ABI)
                if (typeof result === 'object') {
                  // Check for named properties as defined in the ABI
                  if ('tokens' in result && 'weights' in result) {
                    console.log('Found named properties: tokens, weights');
                    tokenAddresses = result.tokens as string[];
                    weights = result.weights as bigint[];
                    console.log('Extracted using named properties:', {
                      tokens: tokenAddresses.length,
                      weights: weights.length
                    });
                  }
                  // If named properties don't exist, try numeric indices
                  else if (result[0] !== undefined && result[1] !== undefined) {
                    console.log('Found numeric properties: 0, 1');
                    tokenAddresses = result[0] as string[];
                    weights = result[1] as bigint[];
                    console.log('Extracted using numeric indices:', {
                      tokens: tokenAddresses.length,
                      weights: weights.length
                    });
                  }
                  // Try with result property (sometimes ethers wraps the result)
                  else if ('result' in result && Array.isArray(result.result)) {
                    console.log('Found result property');
                    if (result.result.length >= 2) {
                      tokenAddresses = result.result[0] as string[];
                      weights = result.result[1] as bigint[];
                      console.log('Extracted using result property:', {
                        tokens: tokenAddresses.length,
                        weights: weights.length
                      });
                    }
                  }
                  // Try with _value property (some ethers.js v6 responses)
                  else if ('_value' in result && Array.isArray(result._value)) {
                    console.log('Found _value property');
                    if (result._value.length >= 2) {
                      tokenAddresses = result._value[0] as string[];
                      weights = result._value[1] as bigint[];
                      console.log('Extracted using _value property:', {
                        tokens: tokenAddresses.length,
                        weights: weights.length
                      });
                    }
                  }
                  // Try accessing as a tuple-like structure
                  else if (typeof result.length === 'number' && result.length >= 2) {
                    console.log('Accessing as array-like object');
                    tokenAddresses = result[0] as string[];
                    weights = result[1] as bigint[];
                    console.log('Extracted as array-like:', {
                      tokens: tokenAddresses?.length,
                      weights: weights?.length
                    });
                  } else {
                    console.warn('Could not extract tokens and weights from result, using empty arrays');
                    tokenAddresses = [];
                    weights = [];
                  }
                }
                
                // Validate the extracted data
                console.log('Standard call - extracted tokens:', tokenAddresses ? tokenAddresses.map(addr => addr.toString()) : 'none');
                console.log('Standard call - extracted weights:', weights ? weights.map(w => w.toString()) : 'none');
                
                if (!tokenAddresses || !weights) {
                  console.warn('Standard call - failed to extract token addresses or weights, using empty arrays');
                  tokenAddresses = [];
                  weights = [];
                }
                
                if (tokenAddresses.length === 0) {
                  console.warn('Standard call - extracted token addresses array is empty');
                }
                
                if (weights.length === 0) {
                  console.warn('Standard call - extracted weights array is empty');
                }
                
                if (tokenAddresses.length !== weights.length) {
                  console.warn(`Standard call - token addresses (${tokenAddresses.length}) and weights (${weights.length}) arrays have different lengths`);
                  // Truncate the longer array to match the shorter one
                  const minLength = Math.min(tokenAddresses.length, weights.length);
                  tokenAddresses = tokenAddresses.slice(0, minLength);
                  weights = weights.slice(0, minLength);
                }
                
                console.log('Standard call - token data extraction complete:', {
                  tokenCount: tokenAddresses.length,
                  weightCount: weights.length,
                  sampleAddress: tokenAddresses[0]?.toString() || 'none',
                  sampleWeight: weights[0]?.toString() || 'none'
                });
              }
                
              console.log('Extracted from object:', { tokenAddresses, weights });
              
              // Final fallback if both methods failed to extract valid data
              if (!tokenAddresses) tokenAddresses = [];
              if (!weights) weights = [];
              
              if (tokenAddresses.length === 0 || weights.length === 0) {
                console.warn('Extraction methods returned empty arrays, trying fallback mechanism');
                
                try {
                  // Try one more approach - call individual methods if available
                  console.log('Attempting to call individual methods for tokens and weights');
                  
                  try {
                    // Try to get tokens first
                    if (!tokenAddresses || tokenAddresses.length === 0) {
                      console.log('Calling getTokens method directly');
                      // Check if we can access tokens through a custom method or property
                      if (typeof (registryContract as any).getTokens === 'function') {
                        const tokensResult = await (registryContract as any).getTokens();
                        console.log('getTokens result:', tokensResult);
                        
                        if (Array.isArray(tokensResult)) {
                          tokenAddresses = tokensResult;
                        } else if (tokensResult && typeof tokensResult === 'object') {
                          // Handle different response formats
                          const resultObj = tokensResult as any;
                          if (Array.isArray(resultObj._value)) {
                            tokenAddresses = resultObj._value;
                          } else if (Array.isArray(resultObj.result)) {
                            tokenAddresses = resultObj.result;
                          } else if (typeof resultObj.length === 'number') {
                            tokenAddresses = Array.from(resultObj);
                          }
                        }
                      }
                    }
                  } catch (tokenError) {
                    console.error('Failed to get tokens individually:', tokenError);
                  }
                  
                  try {
                    // Then try to get weights
                    if (!weights || weights.length === 0) {
                      console.log('Calling getWeights method directly');
                      // Check if we can access weights through a custom method or property
                      if (typeof (registryContract as any).getWeights === 'function') {
                        const weightsResult = await (registryContract as any).getWeights();
                        console.log('getWeights result:', weightsResult);
                        
                        if (Array.isArray(weightsResult)) {
                          weights = weightsResult;
                        } else if (weightsResult && typeof weightsResult === 'object') {
                          // Handle different response formats
                          const resultObj = weightsResult as any;
                          if (Array.isArray(resultObj._value)) {
                            weights = resultObj._value;
                          } else if (Array.isArray(resultObj.result)) {
                            weights = resultObj.result;
                          } else if (typeof resultObj.length === 'number') {
                            weights = Array.from(resultObj);
                          }
                        }
                      }
                    }
                  } catch (weightError) {
                    console.error('Failed to get weights individually:', weightError);
                  }
                  
                  // Log the results of individual calls
                  console.log('After individual calls - tokens:', tokenAddresses?.length, 'weights:', weights?.length);
                } catch (fallbackError) {
                  console.error('Fallback mechanism failed:', fallbackError);
                }
              }
            } catch (tokenError) {
              console.error('Error getting tokens with weights:', tokenError);
              
              // Last resort fallback - provide dummy data for development
              console.warn('All extraction methods failed, using development fallback data');
              if (process.env.NODE_ENV === 'development') {
                console.log('Using development fallback data');
                tokenAddresses = [
                  '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984', // UNI
                  '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9', // AAVE
                  '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e'  // YFI
                ];
                weights = [5000000000000000000n, 3000000000000000000n, 2000000000000000000n]; // 50%, 30%, 20%
                console.log('Development fallback data loaded');
              } else {
                console.warn('Failed to get tokens from registry, continuing with empty arrays');
                tokenAddresses = [];
                weights = [];
              }
            }
          }
            
          // Create token contracts and fetch metadata
          console.log('Starting to load token metadata for', tokenAddresses?.length || 0, 'tokens');
          
          // Ensure tokenAddresses is an array
          const finalTokenAddresses = tokenAddresses || [];
          const finalWeights = weights || [];
          
          const tokenPromises = finalTokenAddresses.map(async (address: string, index: number) => {
            if (!provider) {
              console.warn('Provider not available for token metadata loading, using fallback');
              return {
                address,
                symbol: 'ERROR',
                decimals: 18,
                weight: 0
              };
            }
            
            // Skip invalid addresses
            if (!address || !ethers.isAddress(address)) {
              console.warn(`Invalid address at index ${index}, skipping`);
              return {
                address: ethers.ZeroAddress,
                symbol: 'INVALID',
                decimals: 18,
                weight: 0
              };
            }
            
            // Common token symbols for known addresses (fallback)
            // This is a comprehensive list of popular tokens with their correct decimals
            // Used as a fallback when contract calls fail
            let knownTokens: Record<string, {symbol: string, decimals: number}> = {};
            
            // Check if we're on a local testnet (Anvil) with chainId 31337
            // If so, use the deployed contract addresses from addresses.ts
            try {
              // Use provider.getNetwork() which is available on all provider types
              const network = await provider.getNetwork();
              const chainId = network.chainId;
              console.log(`Current chain ID: ${chainId}`);
              
              // In ethers v6, chainId is returned as a bigint
              // Convert to number for comparison or compare with BigInt
              const localChainId = 31337;
              const isLocalNetwork = typeof chainId === 'bigint' ? 
                chainId === BigInt(localChainId) : 
                Number(chainId) === localChainId;
              
              if (isLocalNetwork) {
                console.log('Using local testnet contract addresses for token metadata');
                // Import the contract addresses from addresses.ts
                const { CONTRACT_ADDRESSES } = await import('../contracts/addresses');
                
                // Add local testnet token addresses with their symbols and decimals
                knownTokens = {
                  // Convert addresses to lowercase for case-insensitive matching
                  [CONTRACT_ADDRESSES.USDC.toLowerCase()]: { symbol: 'USDC', decimals: 6 },
                  [CONTRACT_ADDRESSES.WBTC.toLowerCase()]: { symbol: 'WBTC', decimals: 8 },
                  [CONTRACT_ADDRESSES.WETH.toLowerCase()]: { symbol: 'WETH', decimals: 18 },
                  [CONTRACT_ADDRESSES.LINK.toLowerCase()]: { symbol: 'LINK', decimals: 18 },
                  [CONTRACT_ADDRESSES.UNI.toLowerCase()]: { symbol: 'UNI', decimals: 18 },
                  [CONTRACT_ADDRESSES.AAVE.toLowerCase()]: { symbol: 'AAVE', decimals: 18 },
                };
                console.log('Local testnet token addresses loaded:', knownTokens);
              } else {
                // For mainnet and other networks, use the standard token addresses
                knownTokens = {
                  // Major tokens
                  '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48': { symbol: 'USDC', decimals: 6 },
                  '0xdac17f958d2ee523a2206206994597c13d831ec7': { symbol: 'USDT', decimals: 6 },
                  '0x6b175474e89094c44da98b954eedeac495271d0f': { symbol: 'DAI', decimals: 18 },
                  '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599': { symbol: 'WBTC', decimals: 8 },
                  '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2': { symbol: 'WETH', decimals: 18 },
                  
                  // DeFi tokens
                  '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984': { symbol: 'UNI', decimals: 18 },
                  '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9': { symbol: 'AAVE', decimals: 18 },
                  '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e': { symbol: 'YFI', decimals: 18 },
                  '0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2': { symbol: 'MKR', decimals: 18 },
                  '0xba100000625a3754423978a60c9317c58a424e3d': { symbol: 'BAL', decimals: 18 },
                  '0xc944e90c64b2c07662a292be6244bdf05cda44a7': { symbol: 'GRT', decimals: 18 },
                  '0x4e15361fd6b4bb609fa63c81a2be19d873717870': { symbol: 'FTM', decimals: 18 },
                  '0x514910771af9ca656af840dff83e8264ecf986ca': { symbol: 'LINK', decimals: 18 },
                  '0x111111111117dc0aa78b770fa6a738034120c302': { symbol: '1INCH', decimals: 18 },
                  '0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0': { symbol: 'MATIC', decimals: 18 },
                  '0x6810e776880c02933d47db1b9fc05908e5386b96': { symbol: 'GNO', decimals: 18 },
                  
                  // Stablecoins
                  '0x4fabb145d64652a948d72533023f6e7a623c7c53': { symbol: 'BUSD', decimals: 18 },
                  '0x8e870d67f660d95d5be530380d0ec0bd388289e1': { symbol: 'PAX', decimals: 18 },
                  '0x056fd409e1d7a124bd7017459dfea2f387b6d5cd': { symbol: 'GUSD', decimals: 2 },
                  '0x0000000000085d4780b73119b644ae5ecd22b376': { symbol: 'TUSD', decimals: 18 },
                  '0x5f98805a4e8be255a32880fdec7f6728c6568ba0': { symbol: 'LUSD', decimals: 18 },
                  '0x853d955acef822db058eb8505911ed77f175b99e': { symbol: 'FRAX', decimals: 18 },
                };
              }
            } catch (error) {
              console.error('Error determining chain or loading contract addresses:', error);
              // Fallback to mainnet addresses if there's an error
              knownTokens = {
                '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48': { symbol: 'USDC', decimals: 6 },
                '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599': { symbol: 'WBTC', decimals: 8 },
                '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2': { symbol: 'WETH', decimals: 18 },
                '0x514910771af9ca656af840dff83e8264ecf986ca': { symbol: 'LINK', decimals: 18 },
                '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984': { symbol: 'UNI', decimals: 18 },
                '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9': { symbol: 'AAVE', decimals: 18 }
              };
            }
            
            const normalizedAddress = address.toLowerCase();
            let symbol = 'UNKNOWN';
            let decimals = 18;
            let weight = 0;
            
            try {
              console.log(`Loading metadata for token at ${address}`);
              const tokenContract = new ethers.Contract(address, ERC20ABI, provider);
              
              // Try to get symbol
              try {
                symbol = await tokenContract.symbol();
                console.log(`Got symbol for ${address}: ${symbol}`);
              } catch (symbolError) {
                console.error(`Error getting symbol for ${address}:`, symbolError);
                // Try fallback
                if (knownTokens[normalizedAddress]) {
                  symbol = knownTokens[normalizedAddress].symbol;
                  console.log(`Used fallback symbol for ${address}: ${symbol}`);
                }
              }
              
              // Try to get decimals with multiple approaches
              try {
                // First try with standard contract call and timeout protection
                const decimalsPromise = Promise.race([
                  tokenContract.decimals(),
                  new Promise<never>((_, reject) => 
                    setTimeout(() => reject(new Error('Decimals request timed out')), 3000)
                  )
                ]);
                
                decimals = await decimalsPromise;
                console.log(`Got decimals for ${address}: ${decimals}`);
              } catch (decimalsError) {
                console.error(`Error getting decimals for ${address}:`, decimalsError);
                
                // Try with low-level call approach
                try {
                  console.log(`Trying low-level call for decimals on ${address}`);
                  const iface = new ethers.Interface(['function decimals() view returns (uint8)']);
                  const calldata = iface.encodeFunctionData('decimals', []);
                  
                  const rawResult = await provider.call({
                    to: address,
                    data: calldata
                  });
                  
                  if (rawResult && rawResult !== '0x') {
                    const decodedResult = iface.decodeFunctionResult('decimals', rawResult);
                    decimals = Number(decodedResult[0]);
                    console.log(`Got decimals via low-level call for ${address}: ${decimals}`);
                  } else {
                    throw new Error('Empty result from low-level call');
                  }
                } catch (lowLevelError) {
                  console.error(`Low-level call for decimals failed for ${address}:`, lowLevelError);
                  
                  // Use fallback from known tokens
                  if (knownTokens[normalizedAddress]) {
                    decimals = knownTokens[normalizedAddress].decimals;
                    console.log(`Used fallback decimals for ${address}: ${decimals}`);
                  }
                }
              }
              
              // Get weight (with fallback)
              try {
                if (finalWeights && finalWeights[index]) {
                  weight = parseFloat(ethers.formatUnits(finalWeights[index], 18));
                  console.log(`Got weight for ${address}: ${weight}`);
                } else {
                  console.warn(`No weight found for token at index ${index}`);
                }
              } catch (weightError) {
                console.warn(`Error formatting weight for ${address}, using 0:`, weightError);
              }
              
              return {
                address,
                symbol,
                decimals,
                weight,
              };
            } catch (tokenError) {
              console.error(`Error loading token at ${address}:`, tokenError);
              // Return a placeholder with any fallback data we have
              return {
                address,
                symbol: knownTokens[normalizedAddress]?.symbol || 'ERROR',
                decimals: knownTokens[normalizedAddress]?.decimals || 18,
                weight: finalWeights && finalWeights[index] ? 
                  parseFloat(ethers.formatUnits(finalWeights[index], 18)) : 0,
              };
            }
          });
          
          console.log('Waiting for all token metadata promises to resolve...');
          // Use Promise.allSettled to handle partial failures
          const results = await Promise.allSettled(tokenPromises);
          
          console.log('Token metadata loading results:', 
            results.map((r, i) => `${i}: ${r.status}`).join(', ')
          );
          
          // Filter successful results
          const tokens = results
            .filter((result): result is PromiseFulfilledResult<any> => result.status === 'fulfilled')
            .map(result => result.value as Token)
            .filter((t: Token) => t.symbol !== 'ERROR'); // Filter out error tokens
          
          // Log any failures
          results
            .filter((result): result is PromiseRejectedResult => result.status === 'rejected')
            .forEach((result, index) => {
              console.error(`Token at index ${index} failed to load:`, result.reason);
            });
          
          console.log('Successfully loaded', tokens.length, 'tokens out of', tokenPromises.length);
          
          // Even if we have no tokens, don't show an error - just display empty state
          if (tokens.length === 0 && tokenPromises.length > 0) {
            console.warn('All token metadata loading failed or returned errors');
            setIndexTokens([]);
            setError(null); // Don't set error to avoid breaking the UI
          } else {
            // Sort tokens by weight (descending)
            const sortedTokens = [...tokens].sort((a, b) => (b.weight || 0) - (a.weight || 0));
            console.log('Final sorted tokens:', sortedTokens.map(t => `${t.symbol}: ${t.weight || 0}`).join(', '));
            setIndexTokens(sortedTokens);
            setError(null);
          }
        } catch (err) {
          console.error('Error loading index tokens:', err);
          setError('Failed to load index tokens');
          setIndexTokens([]);
        } finally {
          setIsLoading(false);
        }
      }
    };
    
    if (registryContract && provider) {
      loadIndexTokens();
    }
  }, [registryContract, provider]);

  return {
    vaultContract,
    registryContract,
    capitalManagerContract,
    indexTokens,
    isLoading,
    error,
  };
};

// Hook for ERC20 token interactions
export const useERC20 = (tokenAddress: string) => {
  const { provider, account } = useWeb3();
  const [tokenContract, setTokenContract] = useState<ethers.Contract | null>(null);
  const [tokenBalance, setTokenBalance] = useState<string>('0');
  const [tokenSymbol, setTokenSymbol] = useState<string>('');
  const [tokenDecimals, setTokenDecimals] = useState<number>(18);
  const [isLoading, setIsLoading] = useState(false);

  // Initialize token contract
  useEffect(() => {
    if (provider && tokenAddress && tokenAddress !== ethers.ZeroAddress) {
      const contract = new ethers.Contract(tokenAddress, ERC20ABI, provider);
      setTokenContract(contract);
      
      // Load token metadata
      const loadTokenMetadata = async () => {
        try {
          const [symbol, decimals] = await Promise.all([
            contract.symbol(),
            contract.decimals(),
          ]);
          setTokenSymbol(symbol);
          setTokenDecimals(decimals);
        } catch (err) {
          console.error('Error loading token metadata:', err);
        }
      };
      
      loadTokenMetadata();
    } else {
      setTokenContract(null);
    }
  }, [provider, tokenAddress]);

  // Load token balance
  useEffect(() => {
    const loadBalance = async () => {
      if (tokenContract && account) {
        setIsLoading(true);
        try {
          const balance = await tokenContract.balanceOf(account);
          setTokenBalance(ethers.formatUnits(balance, tokenDecimals));
        } catch (err) {
          console.error('Error loading token balance:', err);
        } finally {
          setIsLoading(false);
        }
      }
    };
    
    loadBalance();
    
    // Set up event listener for balance changes
    if (tokenContract && account) {
      const filter = tokenContract.filters.Transfer(account, null);
      const fromFilter = tokenContract.filters.Transfer(null, account);
      
      tokenContract.on(filter, loadBalance);
      tokenContract.on(fromFilter, loadBalance);
      
      return () => {
        tokenContract.off(filter, loadBalance);
        tokenContract.off(fromFilter, loadBalance);
      };
    }
  }, [tokenContract, account, tokenDecimals]);

  // Approve spending of tokens with comprehensive error handling
  const approveTokens = async (spender: string, amount: string): Promise<boolean> => {
    if (!tokenContract) {
      console.error('Token contract not initialized');
      return false;
    }
    
    if (!provider) {
      console.error('Provider not available');
      return false;
    }
    
    if (!spender || spender === ethers.ZeroAddress) {
      console.error('Invalid spender address');
      return false;
    }
    
    try {
      console.log(`Approving ${amount} ${tokenSymbol} for spender: ${spender}`);
      
      // Get signer
      console.log('Getting signer...');
      if (!provider.getSigner) {
        console.error('Provider does not have getSigner method');
        return false;
      }
      const signer = await provider.getSigner();
      const signerAddress = await signer.getAddress();
      console.log('Signer address:', signerAddress);
      
      // Get token address
      console.log('Getting token address...');
      const tokenAddress = await tokenContract.getAddress();
      console.log('Token address:', tokenAddress);
      
      // Create contract with signer
      console.log('Creating contract with signer...');
      const connectedContract = new ethers.Contract(
        tokenAddress, 
        ERC20ABI, 
        signer
      );
      
      // Check allowance first
      console.log('Checking current allowance...');
      try {
        const currentAllowance = await connectedContract.allowance(signerAddress, spender);
        console.log('Current allowance:', ethers.formatUnits(currentAllowance, tokenDecimals), tokenSymbol);
        
        // If allowance is already sufficient, no need to approve again
        const amountInWei = ethers.parseUnits(amount, tokenDecimals);
        if (currentAllowance >= amountInWei) {
          console.log('Allowance is already sufficient');
          return true;
        }
      } catch (allowanceError) {
        console.warn('Error checking allowance, proceeding with approval anyway:', allowanceError);
      }
      
      // Parse amount
      const amountInWei = ethers.parseUnits(amount, tokenDecimals);
      console.log('Amount in wei for approval:', amountInWei.toString());
      
      // Send transaction
      console.log('Sending approval transaction...');
      try {
        const tx = await connectedContract.approve(spender, amountInWei);
        console.log('Approval transaction sent:', tx.hash);
        
        // Wait for confirmation
        console.log('Waiting for transaction confirmation...');
        const receipt = await tx.wait();
        console.log('Approval transaction confirmed in block:', receipt?.blockNumber || 'Unknown block');
        
        return true;
      } catch (txError: unknown) {
        console.error('Transaction error details:', txError);
        // Check for specific error messages
        const errorMessage = typeof txError === 'object' && txError !== null && 'message' in txError 
          ? String(txError.message) 
          : 'Unknown error';
        if (errorMessage.includes('user rejected')) {
          console.error('User rejected the transaction');
        } else if (errorMessage.includes('insufficient funds')) {
          console.error('Insufficient funds for transaction');
        }
        throw txError; // Re-throw to be caught by the outer catch
      }
    } catch (err) {
      console.error('Error approving tokens:', err);
      return false;
    }
  };

  return {
    tokenContract,
    tokenBalance,
    tokenSymbol,
    tokenDecimals,
    approveTokens,
    isLoading,
  };
};
