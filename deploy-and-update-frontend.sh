#!/bin/bash

# Deploy ComposableRWA system and update frontend addresses
# This script deploys the complete ComposableRWA system to localhost and updates the frontend with deployed addresses

set -e  # Exit on error

echo "🚀 Starting ComposableRWA Deployment and Frontend Update..."
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if anvil is running
echo -e "${BLUE}Checking if Anvil is running...${NC}"
if ! curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
    echo -e "${RED}❌ Anvil is not running!${NC}"
    echo -e "${YELLOW}Please start Anvil in a separate terminal with: anvil${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Anvil is running${NC}"
echo ""

# Deploy ComposableRWA system
echo -e "${BLUE}Deploying ComposableRWA system...${NC}"
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Deploy and capture output
DEPLOY_OUTPUT=$(forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url http://localhost:8545 \
    --broadcast \
    2>&1)

echo "$DEPLOY_OUTPUT"

# Extract deployed addresses from the output
echo ""
echo -e "${BLUE}Extracting deployed contract addresses...${NC}"

# Parse addresses from deployment output
BUNDLE_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -A1 "ComposableRWABundle deployed" | grep "0x" | awk '{print $NF}' | tail -1)
OPTIMIZER_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -A1 "StrategyOptimizer deployed" | grep "0x" | awk '{print $NF}' | tail -1)
TRS_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -A1 "TRSExposureStrategy deployed" | grep "0x" | awk '{print $NF}' | tail -1)
PERP_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -A1 "EnhancedPerpetualStrategy deployed" | grep "0x" | awk '{print $NF}' | tail -1)
DIRECT_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -A1 "DirectTokenStrategy deployed" | grep "0x" | awk '{print $NF}' | tail -1)
USDC_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -A1 "MockUSDC deployed" | grep "0x" | awk '{print $NF}' | tail -1)

# Validate addresses were found
if [ -z "$BUNDLE_ADDR" ] || [ "$BUNDLE_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo -e "${YELLOW}⚠️  Could not extract ComposableRWABundle address from deployment output${NC}"
    echo -e "${YELLOW}Please check the deployment logs above and manually update frontend/src/contracts/addresses.ts${NC}"
    exit 0
fi

echo -e "${GREEN}✅ Deployment successful!${NC}"
echo ""
echo "Deployed Addresses:"
echo "  ComposableRWABundle:      $BUNDLE_ADDR"
echo "  StrategyOptimizer:        $OPTIMIZER_ADDR"
echo "  TRSExposureStrategy:      $TRS_ADDR"
echo "  EnhancedPerpetualStrategy: $PERP_ADDR"
echo "  DirectTokenStrategy:      $DIRECT_ADDR"
echo "  MockUSDC:                 $USDC_ADDR"
echo ""

# Update frontend addresses
echo -e "${BLUE}Updating frontend contract addresses...${NC}"

cat > frontend/src/contracts/addresses.ts << EOF
// Contract addresses - automatically updated by deploy-and-update-frontend.sh
export const CONTRACT_ADDRESSES = {
  // Legacy vault addresses (for backward compatibility)
  VAULT: '0x8A791620dd6260079BF849Dc5567aDC3F2FdC318',
  LEGACY_VAULT: '0x8A791620dd6260079BF849Dc5567aDC3F2FdC318',
  REGISTRY: '0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82',
  LEGACY_REGISTRY: '0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82',

  // ComposableRWA System
  COMPOSABLE_RWA_BUNDLE: '${BUNDLE_ADDR}',
  STRATEGY_OPTIMIZER: '${OPTIMIZER_ADDR}',

  // Exposure Strategies
  TRS_EXPOSURE_STRATEGY: '${TRS_ADDR}',
  PERPETUAL_STRATEGY: '${PERP_ADDR}',
  DIRECT_TOKEN_STRATEGY: '${DIRECT_ADDR}',

  // Mock tokens
  USDC: '${USDC_ADDR}',
  MOCK_USDC: '${USDC_ADDR}',
  WBTC: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  WETH: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  LINK: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  UNI: '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9',
  AAVE: '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',

  // Infrastructure
  PRICE_ORACLE: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  DEX: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
};
EOF

echo -e "${GREEN}✅ Frontend addresses updated!${NC}"
echo ""

echo -e "${GREEN}🎉 Deployment and update complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Start the frontend: cd frontend && npm start"
echo "  2. Connect MetaMask to http://localhost:8545 (Chain ID: 31337)"
echo "  3. Import test account with private key: $PRIVATE_KEY"
echo "  4. Test the ComposableRWA functionality in the UI"
echo ""
