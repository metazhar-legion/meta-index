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
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 > deploy.log 2>&1

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
VAULT_ADDRESS=$(grep "Index Fund Vault deployed at:" deploy.log | awk '{print $NF}')
REGISTRY_ADDRESS=$(grep "Index Registry deployed at:" deploy.log | awk '{print $NF}')
USDC_ADDRESS=$(grep "USDC deployed at:" deploy.log | awk '{print $NF}')

if [ -z "$VAULT_ADDRESS" ] || [ -z "$REGISTRY_ADDRESS" ] || [ -z "$USDC_ADDRESS" ]; then
    echo -e "${RED}Error: Could not extract contract addresses.${NC}"
    echo -e "${YELLOW}Check deploy.log for details.${NC}"
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}Contract addresses:${NC}"
echo -e "${BLUE}Vault: $VAULT_ADDRESS${NC}"
echo -e "${BLUE}Registry: $REGISTRY_ADDRESS${NC}"
echo -e "${BLUE}USDC: $USDC_ADDRESS${NC}"

# Create .env file for frontend
echo -e "\n${YELLOW}Creating frontend environment file...${NC}"
cat > ./frontend/.env.local << EOL
REACT_APP_CHAIN_ID=31337
REACT_APP_NETWORK_NAME=Anvil
REACT_APP_INDEX_FUND_VAULT_ADDRESS=$VAULT_ADDRESS
REACT_APP_INDEX_REGISTRY_ADDRESS=$REGISTRY_ADDRESS
REACT_APP_USDC_ADDRESS=$USDC_ADDRESS
REACT_APP_RPC_URL=http://localhost:8545
REACT_APP_ENABLE_TESTNET_FAUCET=true
REACT_APP_DEFAULT_THEME=dark
EOL

echo -e "${GREEN}Frontend environment file created at ./frontend/.env.local${NC}"

# Start frontend in the background
echo -e "\n${YELLOW}Starting frontend application...${NC}"
cd frontend
npm install > ../frontend-install.log 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to install frontend dependencies.${NC}"
    echo -e "${YELLOW}Check frontend-install.log for details.${NC}"
    cd ..
    kill $anvil_pid
    exit 1
fi

npm start > ../frontend.log 2>&1 &
frontend_pid=$!
cd ..

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

# Display test accounts
echo -e "\n${YELLOW}Test Accounts (from Anvil):${NC}"
echo -e "${BLUE}Account #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266${NC}"
echo -e "${BLUE}Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80${NC}"
echo -e "${BLUE}Account #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8${NC}"
echo -e "${BLUE}Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d${NC}"

# Display instructions
echo -e "\n${GREEN}Development environment is running!${NC}"
echo -e "${YELLOW}Instructions:${NC}"
echo -e "1. Open ${BLUE}http://localhost:3000${NC} in your browser"
echo -e "2. Connect MetaMask to ${BLUE}http://localhost:8545${NC} (Chain ID: 31337)"
echo -e "3. Import test accounts using the private keys above"
echo -e "4. Press ${BLUE}Ctrl+C${NC} to stop all services when done"

# Keep script running until user interrupts
echo -e "\n${YELLOW}Press Ctrl+C to stop all services${NC}"
while true; do
    sleep 1
done
