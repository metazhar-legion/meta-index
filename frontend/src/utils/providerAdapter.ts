import { ethers } from 'ethers';

/**
 * Adapts a provider to be compatible with ethers v6 ContractRunner
 * This is a temporary solution to bridge the gap between web3-react and our code
 */
export function adaptWeb3Provider(provider: any | null): ethers.BrowserProvider | null {
  if (!provider) return null;
  
  // Create a new ethers v6 provider
  return new ethers.BrowserProvider(provider);
}

/**
 * Adapts a provider to get a signer compatible with ethers v6 ContractRunner
 */
export async function adaptWeb3Signer(provider: any | null): Promise<ethers.Signer | null> {
  if (!provider) return null;
  
  const adaptedProvider = adaptWeb3Provider(provider);
  if (!adaptedProvider) return null;
  
  try {
    return await adaptedProvider.getSigner();
  } catch (error) {
    console.error('Failed to get signer:', error);
    return null;
  }
}
