#!/bin/bash

# Web3 Index Fund - Withdrawal Test Script
# This script tests the withdrawal functionality of the IndexFundVault contract

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}      Web3 Index Fund - Withdrawal Test          ${NC}"
echo -e "${BLUE}=================================================${NC}"

# Check if Foundry is installed
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}Error: Foundry is not installed.${NC}"
    echo -e "${YELLOW}Please install Foundry by following the instructions at:${NC}"
    echo -e "${YELLOW}https://book.getfoundry.sh/getting-started/installation${NC}"
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
    
    echo -e "${GREEN}All services stopped. Goodbye!${NC}"
    exit 0
}

# Set trap for cleanup
trap cleanup SIGINT SIGTERM

# Start Anvil in the background
echo -e "${YELLOW}Starting Anvil local blockchain...${NC}"
anvil --chain-id 31337 --port 8546 > anvil.log 2>&1 &
anvil_pid=$!

# Check if Anvil started successfully
sleep 2
if ! ps -p $anvil_pid > /dev/null; then
    echo -e "${RED}Error: Failed to start Anvil.${NC}"
    echo -e "${YELLOW}Check anvil.log for details.${NC}"
    exit 1
fi

echo -e "${GREEN}Anvil running with PID: $anvil_pid${NC}"
echo -e "${BLUE}Local blockchain available at: http://localhost:8546${NC}"

# Deploy contracts to local Anvil
echo -e "\n${YELLOW}Deploying contracts to local blockchain...${NC}"
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8546 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 > deploy.log 2>&1

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
    cat deploy.log
    kill $anvil_pid
    exit 1
fi

echo -e "${GREEN}Contract addresses:${NC}"
echo -e "${BLUE}Vault: $VAULT_ADDRESS${NC}"
echo -e "${BLUE}Registry: $REGISTRY_ADDRESS${NC}"
echo -e "${BLUE}USDC: $USDC_ADDRESS${NC}"

# Run the withdrawal test
echo -e "\n${YELLOW}Running withdrawal test...${NC}"
echo -e "${YELLOW}Step 1: Depositing funds into the vault...${NC}"

# Create a test script to deposit and withdraw
cat > test_script.js << EOL
const { ethers } = require('ethers');

async function main() {
  // Connect to local Anvil node
  const provider = new ethers.providers.JsonRpcProvider('http://localhost:8546');
  
  // Use the first account from Anvil
  const wallet = new ethers.Wallet('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', provider);
  
  // Contract addresses
  const vaultAddress = '${VAULT_ADDRESS}';
  const usdcAddress = '${USDC_ADDRESS}';
  
  // ABI for ERC20 and Vault
  const erc20Abi = [
    'function balanceOf(address owner) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function transfer(address to, uint256 amount) returns (bool)',
    'function decimals() view returns (uint8)'
  ];
  
  const vaultAbi = [
    'function deposit(uint256 assets, address receiver) returns (uint256)',
    'function redeem(uint256 shares, address receiver, address owner) returns (uint256)',
    'function balanceOf(address owner) view returns (uint256)',
    'function totalAssets() view returns (uint256)',
    'function convertToShares(uint256 assets) view returns (uint256)',
    'function convertToAssets(uint256 shares) view returns (uint256)'
  ];
  
  // Create contract instances
  const usdc = new ethers.Contract(usdcAddress, erc20Abi, wallet);
  const vault = new ethers.Contract(vaultAddress, vaultAbi, wallet);
  
  try {
    // Get USDC balance
    const decimals = await usdc.decimals();
    const usdcBalance = await usdc.balanceOf(wallet.address);
    console.log(\`Initial USDC balance: \${ethers.utils.formatUnits(usdcBalance, decimals)}\`);
    
    // Approve USDC for vault
    const depositAmount = ethers.utils.parseUnits('10000', decimals); // 10,000 USDC
    console.log(\`Approving \${ethers.utils.formatUnits(depositAmount, decimals)} USDC for vault...\`);
    await usdc.approve(vaultAddress, depositAmount);
    
    // Deposit USDC to vault
    console.log(\`Depositing \${ethers.utils.formatUnits(depositAmount, decimals)} USDC to vault...\`);
    const tx = await vault.deposit(depositAmount, wallet.address);
    await tx.wait();
    
    // Get share balance
    const shareBalance = await vault.balanceOf(wallet.address);
    console.log(\`Received \${ethers.utils.formatEther(shareBalance)} vault shares\`);
    
    // Check total assets in vault
    const totalAssets = await vault.totalAssets();
    console.log(\`Total assets in vault: \${ethers.utils.formatUnits(totalAssets, decimals)} USDC\`);
    
    // Wait a bit to simulate some time passing
    console.log('Waiting for 5 seconds...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    // Withdraw half of the shares
    const withdrawShares = shareBalance.div(2);
    console.log(\`Withdrawing \${ethers.utils.formatEther(withdrawShares)} shares from vault...\`);
    const withdrawTx = await vault.redeem(withdrawShares, wallet.address, wallet.address);
    await withdrawTx.wait();
    
    // Check new share balance
    const newShareBalance = await vault.balanceOf(wallet.address);
    console.log(\`New share balance: \${ethers.utils.formatEther(newShareBalance)}\`);
    
    // Check new USDC balance
    const newUsdcBalance = await usdc.balanceOf(wallet.address);
    console.log(\`New USDC balance: \${ethers.utils.formatUnits(newUsdcBalance, decimals)}\`);
    
    // Try a larger withdrawal
    console.log('Attempting to withdraw all remaining shares...');
    const finalWithdrawTx = await vault.redeem(newShareBalance, wallet.address, wallet.address);
    await finalWithdrawTx.wait();
    
    // Check final balances
    const finalShareBalance = await vault.balanceOf(wallet.address);
    const finalUsdcBalance = await usdc.balanceOf(wallet.address);
    console.log(\`Final share balance: \${ethers.utils.formatEther(finalShareBalance)}\`);
    console.log(\`Final USDC balance: \${ethers.utils.formatUnits(finalUsdcBalance, decimals)}\`);
    
    console.log('Withdrawal test completed successfully!');
  } catch (error) {
    console.error('Error during test:', error);
  }
}

main();
EOL

# Install ethers.js if not already installed
if ! [ -d "node_modules/ethers" ]; then
    echo -e "${YELLOW}Installing ethers.js...${NC}"
    npm install --no-save ethers@5.7.2
fi

# Run the test script
echo -e "${YELLOW}Running the test script...${NC}"
node test_script.js

# Run the Foundry test
echo -e "\n${YELLOW}Running Foundry test for withdrawal...${NC}"
forge test --match-test testWithdraw --rpc-url http://localhost:8546 -vv

# Cleanup
echo -e "\n${YELLOW}Test completed. Cleaning up...${NC}"
cleanup
