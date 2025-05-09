#!/bin/bash

# Web3 Index Fund - Run Script
# This script starts both the local blockchain and the frontend application

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
echo -e "\n${YELLOW}Deploying contracts to local blockchain...${NC}"
forge script script/DeployBasicSetup.s.sol:DeployBasicSetup --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 > deploy.log 2>&1

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
VAULT_ADDRESS=$(grep "IndexFundVaultV2 deployed at:" deploy.log | awk '{print $NF}')
USDC_ADDRESS=$(grep "MockUSDC deployed at:" deploy.log | awk '{print $NF}')
PRICE_ORACLE_ADDRESS=$(grep "MockPriceOracle deployed at:" deploy.log | awk '{print $NF}')
DEX_ADDRESS=$(grep "MockDEX deployed at:" deploy.log | awk '{print $NF}')

if [ -z "$VAULT_ADDRESS" ] || [ -z "$USDC_ADDRESS" ]; then
    echo -e "${RED}Error: Could not extract contract addresses.${NC}"
    echo -e "${YELLOW}Check deploy.log for details.${NC}"
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}Contract addresses extracted successfully:${NC}"
echo -e "${BLUE}Vault: $VAULT_ADDRESS${NC}"
echo -e "${BLUE}USDC: $USDC_ADDRESS${NC}"
echo -e "${BLUE}Price Oracle: $PRICE_ORACLE_ADDRESS${NC}"
echo -e "${BLUE}DEX: $DEX_ADDRESS${NC}"

# Update frontend contract addresses
echo -e "\n${YELLOW}Updating frontend contract addresses...${NC}"
FRONTEND_ADDRESSES_FILE="./frontend/src/contracts/addresses.ts"

# Create the updated addresses file content
cat > "$FRONTEND_ADDRESSES_FILE" << EOL
// Contract addresses - automatically updated by run.sh script
export const CONTRACT_ADDRESSES = {
  // Updated with the latest deployment addresses
  VAULT: '$VAULT_ADDRESS',
  REGISTRY: '0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82', // Using existing registry address
  // Mock tokens
  USDC: '$USDC_ADDRESS',
  WBTC: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512', // Using existing address
  WETH: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0', // Using existing address
  LINK: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9', // Using existing address
  UNI: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9', // Using existing address
  AAVE: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707', // Using existing address
  // Infrastructure
  PRICE_ORACLE: '$PRICE_ORACLE_ADDRESS',
  DEX: '$DEX_ADDRESS',
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
