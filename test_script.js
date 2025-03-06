const { ethers } = require('ethers');

async function main() {
  // Connect to local Anvil node
  const provider = new ethers.providers.JsonRpcProvider('http://localhost:8546');
  
  // Use the first account from Anvil
  const wallet = new ethers.Wallet('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', provider);
  
  // Contract addresses
  const vaultAddress = '0x9A676e781A523b5d0C0e43731313A708CB607508';
  const usdcAddress = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
  
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
    console.log(`Initial USDC balance: ${ethers.utils.formatUnits(usdcBalance, decimals)}`);
    
    // Approve USDC for vault
    const depositAmount = ethers.utils.parseUnits('10000', decimals); // 10,000 USDC
    console.log(`Approving ${ethers.utils.formatUnits(depositAmount, decimals)} USDC for vault...`);
    await usdc.approve(vaultAddress, depositAmount);
    
    // Deposit USDC to vault
    console.log(`Depositing ${ethers.utils.formatUnits(depositAmount, decimals)} USDC to vault...`);
    const tx = await vault.deposit(depositAmount, wallet.address);
    await tx.wait();
    
    // Get share balance
    const shareBalance = await vault.balanceOf(wallet.address);
    console.log(`Received ${ethers.utils.formatEther(shareBalance)} vault shares`);
    
    // Check total assets in vault
    const totalAssets = await vault.totalAssets();
    console.log(`Total assets in vault: ${ethers.utils.formatUnits(totalAssets, decimals)} USDC`);
    
    // Wait a bit to simulate some time passing
    console.log('Waiting for 5 seconds...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    // Withdraw half of the shares
    const withdrawShares = shareBalance.div(2);
    console.log(`Withdrawing ${ethers.utils.formatEther(withdrawShares)} shares from vault...`);
    const withdrawTx = await vault.redeem(withdrawShares, wallet.address, wallet.address);
    await withdrawTx.wait();
    
    // Check new share balance
    const newShareBalance = await vault.balanceOf(wallet.address);
    console.log(`New share balance: ${ethers.utils.formatEther(newShareBalance)}`);
    
    // Check new USDC balance
    const newUsdcBalance = await usdc.balanceOf(wallet.address);
    console.log(`New USDC balance: ${ethers.utils.formatUnits(newUsdcBalance, decimals)}`);
    
    // Try a larger withdrawal
    console.log('Attempting to withdraw all remaining shares...');
    const finalWithdrawTx = await vault.redeem(newShareBalance, wallet.address, wallet.address);
    await finalWithdrawTx.wait();
    
    // Check final balances
    const finalShareBalance = await vault.balanceOf(wallet.address);
    const finalUsdcBalance = await usdc.balanceOf(wallet.address);
    console.log(`Final share balance: ${ethers.utils.formatEther(finalShareBalance)}`);
    console.log(`Final USDC balance: ${ethers.utils.formatUnits(finalUsdcBalance, decimals)}`);
    
    console.log('Withdrawal test completed successfully!');
  } catch (error) {
    console.error('Error during test:', error);
  }
}

main();
