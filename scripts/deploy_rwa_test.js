// SPDX-License-Identifier: MIT
const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying RWA test contracts...");

  // Get signers
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy MockUSDC
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const mockUSDC = await MockUSDC.deploy();
  await mockUSDC.waitForDeployment();
  console.log("MockUSDC deployed to:", await mockUSDC.getAddress());

  // Mint some USDC to the deployer
  const mintAmount = ethers.parseUnits("1000000", 6); // 1 million USDC
  await mockUSDC.mint(deployer.address, mintAmount);
  console.log("Minted", ethers.formatUnits(mintAmount, 6), "USDC to deployer");

  // Deploy MockPriceOracle
  const MockPriceOracle = await ethers.getContractFactory("MockPriceOracle");
  const mockPriceOracle = await MockPriceOracle.deploy(await mockUSDC.getAddress());
  await mockPriceOracle.waitForDeployment();
  console.log("MockPriceOracle deployed to:", await mockPriceOracle.getAddress());

  // Deploy MockDEX
  const MockDEX = await ethers.getContractFactory("MockDEX");
  const mockDEX = await MockDEX.deploy(await mockPriceOracle.getAddress());
  await mockDEX.waitForDeployment();
  console.log("MockDEX deployed to:", await mockDEX.getAddress());

  // Deploy MockPerpetualTrading
  const MockPerpetualTrading = await ethers.getContractFactory("MockPerpetualTrading");
  const mockPerpetualTrading = await MockPerpetualTrading.deploy(await mockUSDC.getAddress());
  await mockPerpetualTrading.waitForDeployment();
  console.log("MockPerpetualTrading deployed to:", await mockPerpetualTrading.getAddress());

  // Deploy RWASyntheticSP500
  const RWASyntheticSP500 = await ethers.getContractFactory("RWASyntheticSP500");
  const rwaSyntheticSP500 = await RWASyntheticSP500.deploy(
    await mockUSDC.getAddress(),
    await mockPerpetualTrading.getAddress(),
    await mockPriceOracle.getAddress()
  );
  await rwaSyntheticSP500.waitForDeployment();
  console.log("RWASyntheticSP500 deployed to:", await rwaSyntheticSP500.getAddress());

  // Set up price for the RWA token in the oracle
  await mockPriceOracle.setPrice(await rwaSyntheticSP500.getAddress(), ethers.parseEther("5000")); // $5000 per SP500 token
  console.log("Set price for RWASyntheticSP500 in the oracle");

  // Deploy IndexRegistry
  const IndexRegistry = await ethers.getContractFactory("IndexRegistry");
  const indexRegistry = await IndexRegistry.deploy();
  await indexRegistry.waitForDeployment();
  console.log("IndexRegistry deployed to:", await indexRegistry.getAddress());

  // Deploy CapitalAllocationManager
  const CapitalAllocationManager = await ethers.getContractFactory("CapitalAllocationManager");
  const capitalAllocationManager = await CapitalAllocationManager.deploy(await mockUSDC.getAddress());
  await capitalAllocationManager.waitForDeployment();
  console.log("CapitalAllocationManager deployed to:", await capitalAllocationManager.getAddress());

  // Set allocation percentages (20% RWA, 70% yield, 10% liquidity buffer)
  await capitalAllocationManager.setAllocation(2000, 7000, 1000);
  console.log("Set allocation percentages in CapitalAllocationManager");

  // Add RWA token to the capital allocation manager
  await capitalAllocationManager.addRWAToken(await rwaSyntheticSP500.getAddress(), 10000); // 100% allocation to SP500
  console.log("Added RWASyntheticSP500 to CapitalAllocationManager");

  // Deploy ConcreteRWAIndexFundVault
  const RWAIndexFundVault = await ethers.getContractFactory("ConcreteRWAIndexFundVault");
  try {
    const rwaIndexFundVault = await RWAIndexFundVault.deploy(
      await mockUSDC.getAddress(),
      await indexRegistry.getAddress(),
      await mockPriceOracle.getAddress(),
      await mockDEX.getAddress(),
      await capitalAllocationManager.getAddress()
    );
    await rwaIndexFundVault.waitForDeployment();
    console.log("ConcreteRWAIndexFundVault deployed to:", await rwaIndexFundVault.getAddress());

    // Approve the vault to spend USDC
    const approveAmount = ethers.parseUnits("100000", 6); // 100,000 USDC
    await mockUSDC.approve(await rwaIndexFundVault.getAddress(), approveAmount);
    console.log("Approved ConcreteRWAIndexFundVault to spend", ethers.formatUnits(approveAmount, 6), "USDC");

    // Deposit into the vault
    const depositAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
    await rwaIndexFundVault.deposit(depositAmount, deployer.address);
    console.log("Deposited", ethers.formatUnits(depositAmount, 6), "USDC into ConcreteRWAIndexFundVault");

    // Get vault share balance
    const shareBalance = await rwaIndexFundVault.balanceOf(deployer.address);
    console.log("Vault share balance:", ethers.formatEther(shareBalance));

    // Rebalance the vault
    await rwaIndexFundVault.rebalance();
    console.log("Rebalanced the vault");

    console.log("RWA test deployment and setup completed successfully!");
  } catch (error) {
    console.error("Error deploying ConcreteRWAIndexFundVault:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
