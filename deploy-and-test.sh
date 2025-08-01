#!/bin/bash

# ComposableRWA Deployment and Testing Script
# This script deploys the full ComposableRWA system and sets up the frontend for testing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CHAIN_ID=31337
PORT=8545
FRONTEND_PORT=3000

echo -e "${BLUE}🚀 ComposableRWA Deployment and Testing Setup${NC}"
echo "=================================================="

# Check prerequisites
echo -e "\n${YELLOW}📋 Checking prerequisites...${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is required but not installed${NC}"
    exit 1
fi

if ! command -v forge &> /dev/null; then
    echo -e "${RED}❌ Foundry is required but not installed${NC}"
    echo "Install from: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

if ! command -v anvil &> /dev/null; then
    echo -e "${RED}❌ Anvil is required but not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites satisfied${NC}"

# Function to check if a port is in use
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to kill process on port
kill_port() {
    local port=$1
    echo -e "${YELLOW}🔄 Killing existing process on port $port...${NC}"
    if check_port $port; then
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
}

# Step 1: Start Anvil (local blockchain)
echo -e "\n${YELLOW}🔧 Starting local blockchain (Anvil)...${NC}"
kill_port $PORT

# Start anvil in background with specific configuration
anvil --port $PORT --chain-id $CHAIN_ID --accounts 10 --balance 1000 > anvil.log 2>&1 &
ANVIL_PID=$!
echo "Anvil PID: $ANVIL_PID"

# Wait for anvil to start
echo -e "${YELLOW}⏳ Waiting for Anvil to start...${NC}"
sleep 3

# Check if anvil is running
if ! check_port $PORT; then
    echo -e "${RED}❌ Failed to start Anvil on port $PORT${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Anvil started successfully on port $PORT${NC}"

# Step 2: Build contracts
echo -e "\n${YELLOW}🔨 Building smart contracts...${NC}"
forge build

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Contract build failed${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Smart contracts built successfully${NC}"

# Step 3: Run tests to ensure everything works
echo -e "\n${YELLOW}🧪 Running contract tests...${NC}"
forge test --match-contract "ComposableRWA" -v

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Contract tests failed${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Contract tests passed${NC}"

# Step 4: Deploy contracts
echo -e "\n${YELLOW}🚀 Deploying ComposableRWA system...${NC}"

# Set up environment variables for deployment
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"  # Default anvil private key
export RPC_URL="http://localhost:$PORT"

# Deploy the system
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --slow

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Deployment failed${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ ComposableRWA system deployed successfully${NC}"

# Step 5: Extract deployment addresses and update frontend
echo -e "\n${YELLOW}📝 Updating frontend contract addresses...${NC}"

# Extract addresses from the deployment broadcast
BROADCAST_FILE="broadcast/DeployComposableRWA.s.sol/$CHAIN_ID/run-latest.json"

if [ -f "$BROADCAST_FILE" ]; then
    echo -e "${GREEN}✅ Found deployment broadcast file${NC}"
    
    # For now, we'll use the manual process. In production, you could parse the JSON
    echo -e "${YELLOW}📋 Please copy the addresses from the deployment output above to:${NC}"
    echo -e "   ${BLUE}frontend/src/contracts/addresses.ts${NC}"
else
    echo -e "${YELLOW}⚠️  Broadcast file not found. Addresses were logged in deployment output above.${NC}"
fi

# Step 6: Install frontend dependencies
echo -e "\n${YELLOW}📦 Installing frontend dependencies...${NC}"
cd frontend

if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing npm packages...${NC}"
    npm install
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Frontend dependency installation failed${NC}"
        cd ..
        kill $ANVIL_PID 2>/dev/null || true
        exit 1
    fi
else
    echo -e "${GREEN}✅ Frontend dependencies already installed${NC}"
fi

# Step 7: Build frontend to check for errors
echo -e "\n${YELLOW}🔨 Building frontend...${NC}"
npm run build

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Frontend build failed${NC}"
    cd ..
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}✅ Frontend built successfully${NC}"

# Step 8: Start frontend development server
echo -e "\n${YELLOW}🌐 Starting frontend development server...${NC}"
kill_port $FRONTEND_PORT

# Start React development server in background
BROWSER=none npm start > ../frontend.log 2>&1 &
FRONTEND_PID=$!
echo "Frontend PID: $FRONTEND_PID"

cd ..

# Wait for frontend to start
echo -e "${YELLOW}⏳ Waiting for frontend to start...${NC}"
sleep 10

# Check if frontend started successfully
if check_port $FRONTEND_PORT; then
    echo -e "${GREEN}✅ Frontend started successfully on port $FRONTEND_PORT${NC}"
else
    echo -e "${RED}❌ Frontend failed to start on port $FRONTEND_PORT${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    kill $FRONTEND_PID 2>/dev/null || true
    exit 1
fi

# Step 9: Display summary and instructions
echo -e "\n${GREEN}🎉 DEPLOYMENT COMPLETE!${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}📊 System Status:${NC}"
echo -e "  🔗 Blockchain:     http://localhost:$PORT (Chain ID: $CHAIN_ID)"
echo -e "  🌐 Frontend:       http://localhost:$FRONTEND_PORT"
echo -e "  📋 Anvil PID:      $ANVIL_PID"
echo -e "  📋 Frontend PID:   $FRONTEND_PID"
echo ""
echo -e "${BLUE}🎯 Testing Instructions:${NC}"
echo -e "  1. Open ${YELLOW}http://localhost:$FRONTEND_PORT${NC} in your browser"
echo -e "  2. Connect MetaMask to ${YELLOW}http://localhost:$PORT${NC}"
echo -e "  3. Import one of the test accounts from Anvil"
echo -e "  4. Select ${YELLOW}'Composable RWA'${NC} role in the frontend"
echo -e "  5. Start testing the multi-strategy system!"
echo ""
echo -e "${BLUE}💰 Test Accounts (all have 1000 ETH):${NC}"
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --slow 2>/dev/null | grep "Available Accounts" -A 20 | head -n 10 || {
    echo -e "  Account 1: ${YELLOW}0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266${NC}"
    echo -e "  Private Key: ${YELLOW}0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80${NC}"
    echo -e "  (Use 'anvil' command to see all accounts)"
}
echo ""
echo -e "${BLUE}🛠️  Available Commands:${NC}"
echo -e "  📊 View Anvil logs:     ${YELLOW}tail -f anvil.log${NC}"
echo -e "  🌐 View Frontend logs:  ${YELLOW}tail -f frontend.log${NC}"
echo -e "  🧪 Run specific tests:  ${YELLOW}forge test --match-contract ComposableRWABundle -v${NC}"
echo -e "  🔄 Restart services:    ${YELLOW}./deploy-and-test.sh${NC}"
echo ""
echo -e "${BLUE}🔧 Manual Cleanup (if needed):${NC}"
echo -e "  ${YELLOW}kill $ANVIL_PID $FRONTEND_PID${NC}"
echo ""
echo -e "${GREEN}Happy testing! 🚀${NC}"

# Keep script running and monitor processes
echo -e "\n${YELLOW}⏳ Monitoring services... (Press Ctrl+C to stop all services)${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}🛑 Stopping all services...${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    kill $FRONTEND_PID 2>/dev/null || true
    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

# Set trap to cleanup on exit
trap cleanup SIGINT SIGTERM

# Wait and monitor
while true; do
    # Check if processes are still running
    if ! kill -0 $ANVIL_PID 2>/dev/null; then
        echo -e "${RED}❌ Anvil process died${NC}"
        kill $FRONTEND_PID 2>/dev/null || true
        exit 1
    fi
    
    if ! kill -0 $FRONTEND_PID 2>/dev/null; then
        echo -e "${RED}❌ Frontend process died${NC}"
        kill $ANVIL_PID 2>/dev/null || true
        exit 1
    fi
    
    sleep 5
done