#!/bin/bash

# Check if ETH_RPC_URL is set
if [ -z "$ETH_RPC_URL" ]; then
    echo "Error: ETH_RPC_URL environment variable is not set"
    echo "Please set it to a valid Ethereum RPC URL (e.g., Infura, Alchemy)"
    echo "Example: export ETH_RPC_URL=https://mainnet.infura.io/v3/YOUR_API_KEY"
    exit 1
fi

# Start Anvil in the background with mainnet fork
echo "Starting Anvil with mainnet fork..."
anvil --fork-url $ETH_RPC_URL --block-time 12 &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 3

# Run the setup script
echo "Deploying contracts to local fork..."
forge script script/SetupLocalFork.s.sol --fork-url http://localhost:8545 --broadcast

# Keep Anvil running until user terminates
echo ""
echo "Local mainnet fork is running. Press Ctrl+C to stop."
echo "RPC URL: http://localhost:8545"

# Trap Ctrl+C and kill Anvil
trap "kill $ANVIL_PID; echo 'Stopping local fork'; exit 0" INT

# Wait for Anvil to finish (which it won't unless killed)
wait $ANVIL_PID
