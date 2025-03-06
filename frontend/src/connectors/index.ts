import { initializeConnector, Web3ReactHooks } from '@web3-react/core';
import { MetaMask } from '@web3-react/metamask';
import { Connector } from '@web3-react/types';

// Initialize the MetaMask connector with hooks
export const [metaMask, metaMaskHooks] = initializeConnector<MetaMask>(
  (actions) => new MetaMask({ actions })
);

// Export all connectors and hooks
export const connectors: [Connector, Web3ReactHooks][] = [
  [metaMask, metaMaskHooks],
];
