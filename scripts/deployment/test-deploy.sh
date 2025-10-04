#!/bin/bash

# Quick test script to verify deployment works
# This tests the deployment without starting the full environment

set -e

# Get the repository root directory (two levels up from this script)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "🧪 Testing ComposableRWA Deployment Script"
echo "=========================================="

# Check if anvil is running
if ! curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
    echo "❌ Anvil is not running"
    echo "Please start Anvil first: anvil"
    exit 1
fi

echo "✅ Anvil is running"

# Export the private key
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

echo "🚀 Deploying contracts..."

# Deploy
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
    --rpc-url http://localhost:8545 \
    --broadcast

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
else
    echo "❌ Deployment failed"
    exit 1
fi
