#!/bin/bash

# Web3 Index Fund - Run Script
# This script starts both the local blockchain and the frontend application

# Get the repository root directory (two levels up from this script)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}      Web3 Index Fund - Development Environment  ${NC}"
echo -e "${BLUE}=================================================${NC}"

# Check if Foundry is installed
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}Error: Foundry is not installed.${NC}"
    echo -e "${YELLOW}Please install Foundry by following the instructions at:${NC}"
    echo -e "${YELLOW}https://book.getfoundry.sh/getting-started/installation${NC}"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is not installed.${NC}"
    echo -e "${YELLOW}Please install Node.js by following the instructions at:${NC}"
    echo -e "${YELLOW}https://nodejs.org/en/download/${NC}"
    exit 1
fi

# Function to handle cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down services...${NC}"
    
    # Kill anvil process
    if [ ! -z "$anvil_pid" ]; then
        echo -e "${YELLOW}Stopping Anvil...${NC}"
        kill $anvil_pid 2>/dev/null
    fi
    
    # Kill frontend process
    if [ ! -z "$frontend_pid" ]; then
        echo -e "${YELLOW}Stopping Frontend...${NC}"
        kill $frontend_pid 2>/dev/null
    fi
    
    echo -e "${GREEN}All services stopped. Goodbye!${NC}"
    exit 0
}

# Set trap for cleanup
trap cleanup SIGINT SIGTERM

# Start Anvil in the background
echo -e "${YELLOW}Starting Anvil local blockchain...${NC}"
anvil --chain-id 31337 > anvil.log 2>&1 &
anvil_pid=$!

# Check if Anvil started successfully
sleep 2
if ! ps -p $anvil_pid > /dev/null; then
    echo -e "${RED}Error: Failed to start Anvil.${NC}"
    echo -e "${YELLOW}Check anvil.log for details.${NC}"
    exit 1
fi

echo -e "${GREEN}Anvil running with PID: $anvil_pid${NC}"
echo -e "${BLUE}Local blockchain available at: http://localhost:8545${NC}"

# Deploy contracts to local Anvil
echo -e "\n${YELLOW}Deploying ComposableRWA system to local blockchain...${NC}"
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA --rpc-url http://localhost:8545 --broadcast > deploy.log 2>&1

# Check if deployment was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Contract deployment failed.${NC}"
    echo -e "${YELLOW}Check deploy.log for details.${NC}"
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}Contracts deployed successfully!${NC}"

# Extract contract addresses from deployment logs
echo -e "${YELLOW}Extracting contract addresses...${NC}"

# Legacy/Basic contracts
VAULT_ADDRESS=$(grep "IndexFundVaultV2 deployed at:" deploy.log | awk '{print $NF}' | tail -1)
REGISTRY_ADDRESS=$(grep "IndexRegistry deployed at:" deploy.log | awk '{print $NF}' | tail -1)
USDC_ADDRESS=$(grep "MockUSDC deployed at:" deploy.log | awk '{print $NF}' | tail -1)
PRICE_ORACLE_ADDRESS=$(grep "EnhancedChainlinkPriceOracle deployed at:" deploy.log | awk '{print $NF}' | tail -1)

# ComposableRWA system contracts
BUNDLE_ADDRESS=$(grep "ComposableRWABundle deployed at:" deploy.log | awk '{print $NF}' | tail -1)
OPTIMIZER_ADDRESS=$(grep "StrategyOptimizer deployed at:" deploy.log | awk '{print $NF}' | tail -1)
TRS_ADDRESS=$(grep "TRSExposureStrategy deployed at:" deploy.log | awk '{print $NF}' | tail -1)
PERPETUAL_ADDRESS=$(grep "EnhancedPerpetualStrategy deployed at:" deploy.log | awk '{print $NF}' | tail -1)
DIRECT_ADDRESS=$(grep "DirectTokenStrategy deployed at:" deploy.log | awk '{print $NF}' | tail -1)

# Mock infrastructure
DEX_ADDRESS=$(grep "MockDEXRouter deployed at:" deploy.log | awk '{print $NF}' | tail -1)
RWA_TOKEN_ADDRESS=$(grep "MockRWAToken deployed at:" deploy.log | awk '{print $NF}' | tail -1)

if [ -z "$USDC_ADDRESS" ] || [ -z "$BUNDLE_ADDRESS" ]; then
    echo -e "${RED}Error: Could not extract contract addresses.${NC}"
    echo -e "${YELLOW}Check deploy.log for details.${NC}"
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}Contract addresses extracted successfully:${NC}"
echo -e "${BLUE}=== Legacy Contracts ===${NC}"
echo -e "${BLUE}Vault:        $VAULT_ADDRESS${NC}"
echo -e "${BLUE}Registry:     $REGISTRY_ADDRESS${NC}"
echo -e "${BLUE}USDC:         $USDC_ADDRESS${NC}"
echo -e "${BLUE}Price Oracle: $PRICE_ORACLE_ADDRESS${NC}"
echo -e "${BLUE}=== ComposableRWA System ===${NC}"
echo -e "${BLUE}Bundle:       $BUNDLE_ADDRESS${NC}"
echo -e "${BLUE}Optimizer:    $OPTIMIZER_ADDRESS${NC}"
echo -e "${BLUE}TRS Strategy: $TRS_ADDRESS${NC}"
echo -e "${BLUE}Perpetual:    $PERPETUAL_ADDRESS${NC}"
echo -e "${BLUE}Direct Token: $DIRECT_ADDRESS${NC}"
echo -e "${BLUE}DEX:          $DEX_ADDRESS${NC}"
echo -e "${BLUE}RWA Token:    $RWA_TOKEN_ADDRESS${NC}"

# Update frontend contract addresses
echo -e "\n${YELLOW}Updating frontend contract addresses...${NC}"
FRONTEND_ADDRESSES_FILE="./frontend/src/contracts/addresses.ts"

# Use default addresses if extraction failed for optional contracts
# If no legacy vault was deployed, use the ComposableRWABundle as the vault
if [ -z "$VAULT_ADDRESS" ] || [ "$VAULT_ADDRESS" = "" ]; then
  VAULT_ADDRESS=$BUNDLE_ADDRESS
fi
VAULT_ADDRESS=${VAULT_ADDRESS:-"0x0000000000000000000000000000000000000000"}
REGISTRY_ADDRESS=${REGISTRY_ADDRESS:-"0x0000000000000000000000000000000000000000"}
BUNDLE_ADDRESS=${BUNDLE_ADDRESS:-"0x0000000000000000000000000000000000000000"}
OPTIMIZER_ADDRESS=${OPTIMIZER_ADDRESS:-"0x0000000000000000000000000000000000000000"}
TRS_ADDRESS=${TRS_ADDRESS:-"0x0000000000000000000000000000000000000000"}
PERPETUAL_ADDRESS=${PERPETUAL_ADDRESS:-"0x0000000000000000000000000000000000000000"}
DIRECT_ADDRESS=${DIRECT_ADDRESS:-"0x0000000000000000000000000000000000000000"}
DEX_ADDRESS=${DEX_ADDRESS:-"0x0000000000000000000000000000000000000000"}
RWA_TOKEN_ADDRESS=${RWA_TOKEN_ADDRESS:-"0x0000000000000000000000000000000000000000"}

# Create the updated addresses file content
cat > "$FRONTEND_ADDRESSES_FILE" << EOL
// Contract addresses - automatically updated by run.sh script
// Last updated: $(date)
export const CONTRACT_ADDRESSES = {
  // Legacy vault addresses (for backward compatibility)
  VAULT: '$VAULT_ADDRESS',
  LEGACY_VAULT: '$VAULT_ADDRESS',
  REGISTRY: '$REGISTRY_ADDRESS',
  LEGACY_REGISTRY: '$REGISTRY_ADDRESS',

  // ComposableRWA System
  COMPOSABLE_RWA_BUNDLE: '$BUNDLE_ADDRESS',
  STRATEGY_OPTIMIZER: '$OPTIMIZER_ADDRESS',

  // Exposure Strategies
  TRS_EXPOSURE_STRATEGY: '$TRS_ADDRESS',
  PERPETUAL_STRATEGY: '$PERPETUAL_ADDRESS',
  DIRECT_TOKEN_STRATEGY: '$DIRECT_ADDRESS',

  // Mock tokens
  USDC: '$USDC_ADDRESS',
  MOCK_USDC: '$USDC_ADDRESS',
  WBTC: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  WETH: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  LINK: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  UNI: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  AAVE: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',

  // Infrastructure
  PRICE_ORACLE: '$PRICE_ORACLE_ADDRESS',
  DEX: '$DEX_ADDRESS',
  RWA_TOKEN: '$RWA_TOKEN_ADDRESS',
};
EOL

echo -e "${GREEN}Frontend contract addresses updated successfully!${NC}"

# Mint additional USDC to test accounts
echo -e "\n${YELLOW}Minting USDC to test accounts...${NC}"
forge script script/MintUSDC.s.sol:MintUSDC --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 >> deploy.log 2>&1

# Check if USDC minting was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: USDC minting failed.${NC}"
    echo -e "${YELLOW}Check deploy.log for details.${NC}"
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}USDC minted successfully!${NC}"

# Start frontend in the background
echo -e "\n${YELLOW}Starting frontend application...${NC}"
cd frontend
npm start > ../frontend.log 2>&1 &
frontend_pid=$!

# Check if frontend started successfully
sleep 5
if ! ps -p $frontend_pid > /dev/null; then
    echo -e "${RED}Error: Failed to start frontend.${NC}"
    echo -e "${YELLOW}Check frontend.log for details.${NC}"
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}Frontend running with PID: $frontend_pid${NC}"
echo -e "${BLUE}Frontend available at: http://localhost:3000${NC}"

echo -e "\n${GREEN}Web3 Index Fund development environment is now running!${NC}"
echo -e "${YELLOW}Press Ctrl+C to shut down all services.${NC}"

# Keep the script running until user interrupts
wait
