const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ConcreteRWAIndexFundVault", function () {
  let mockUSDC;
  let mockPriceOracle;
  let mockDEX;
  let mockPerpetualTrading;
  let rwaSyntheticSP500;
  let indexRegistry;
  let capitalAllocationManager;
  let rwaIndexFundVault;
  let owner;
  let user;
  let marketId;

  const initialPrice = ethers.parseEther("5000"); // $5000 per SP500 token
  
  beforeEach(async function () {
    // Get signers
    [owner, user] = await ethers.getSigners();
    
    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    mockUSDC = await MockUSDC.deploy();
    
    // Mint USDC to owner and user
    const mintAmount = ethers.parseUnits("1000000", 6); // 1 million USDC
    await mockUSDC.mint(owner.address, mintAmount);
    await mockUSDC.mint(user.address, mintAmount);
    
    // Deploy MockPriceOracle
    const MockPriceOracle = await ethers.getContractFactory("MockPriceOracle");
    mockPriceOracle = await MockPriceOracle.deploy(await mockUSDC.getAddress());
    
    // Deploy MockDEX
    const MockDEX = await ethers.getContractFactory("MockDEX");
    mockDEX = await MockDEX.deploy(mockPriceOracle);
    
    // Deploy MockPerpetualTrading
    const MockPerpetualTrading = await ethers.getContractFactory("MockPerpetualTrading");
    mockPerpetualTrading = await MockPerpetualTrading.deploy(await mockUSDC.getAddress());
    
    // Deploy RWASyntheticSP500
    const RWASyntheticSP500 = await ethers.getContractFactory("RWASyntheticSP500");
    rwaSyntheticSP500 = await RWASyntheticSP500.deploy(
      await mockUSDC.getAddress(),
      await mockPerpetualTrading.getAddress(),
      await mockPriceOracle.getAddress()
    );
    
    // Set price for the RWA token in the oracle
    await mockPriceOracle.setPrice(await rwaSyntheticSP500.getAddress(), initialPrice);
    
    // Deploy IndexRegistry
    const IndexRegistry = await ethers.getContractFactory("IndexRegistry");
    indexRegistry = await IndexRegistry.deploy();
    
    // Deploy CapitalAllocationManager
    const CapitalAllocationManager = await ethers.getContractFactory("CapitalAllocationManager");
    capitalAllocationManager = await CapitalAllocationManager.deploy(await mockUSDC.getAddress());
    
    // Set allocation percentages (20% RWA, 70% yield, 10% liquidity buffer)
    await capitalAllocationManager.setAllocation(2000, 7000, 1000);
    
    // Add RWA token to the capital allocation manager
    await capitalAllocationManager.addRWAToken(await rwaSyntheticSP500.getAddress(), 10000); // 100% allocation to SP500
    
    // Deploy ConcreteRWAIndexFundVault
    const ConcreteRWAIndexFundVault = await ethers.getContractFactory("ConcreteRWAIndexFundVault");
    rwaIndexFundVault = await ConcreteRWAIndexFundVault.deploy(
      await mockUSDC.getAddress(),
      await indexRegistry.getAddress(),
      await mockPriceOracle.getAddress(),
      await mockDEX.getAddress(),
      await capitalAllocationManager.getAddress()
    );
    
    // Get the market ID
    marketId = await rwaSyntheticSP500.MARKET_ID();
  });
  
  describe("Initialization", function () {
    it("Should initialize with correct values", async function () {
      expect(await rwaIndexFundVault.asset()).to.equal(await mockUSDC.getAddress());
      expect(await rwaIndexFundVault.indexRegistry()).to.equal(await indexRegistry.getAddress());
      expect(await rwaIndexFundVault.priceOracle()).to.equal(await mockPriceOracle.getAddress());
      expect(await rwaIndexFundVault.dex()).to.equal(await mockDEX.getAddress());
      expect(await rwaIndexFundVault.capitalAllocationManager()).to.equal(await capitalAllocationManager.getAddress());
    });
  });
  
  describe("Deposits and Withdrawals", function () {
    const depositAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
    
    beforeEach(async function () {
      // Approve vault to spend owner's USDC
      await mockUSDC.approve(await rwaIndexFundVault.getAddress(), depositAmount.mul(2));
    });
    
    it("Should deposit assets and mint shares", async function () {
      await rwaIndexFundVault.deposit(depositAmount, owner.address);
      
      // Check that shares were minted
      expect(await rwaIndexFundVault.balanceOf(owner.address)).to.be.gt(0);
      
      // Check that assets were transferred
      expect(await mockUSDC.balanceOf(await rwaIndexFundVault.getAddress())).to.equal(depositAmount);
    });
    
    it("Should withdraw assets and burn shares", async function () {
      // First deposit
      await rwaIndexFundVault.deposit(depositAmount, owner.address);
      
      const initialShares = await rwaIndexFundVault.balanceOf(owner.address);
      const initialAssets = await mockUSDC.balanceOf(owner.address);
      
      // Withdraw half
      const withdrawShares = initialShares.div(2);
      await rwaIndexFundVault.redeem(withdrawShares, owner.address, owner.address);
      
      // Check that shares were burned
      expect(await rwaIndexFundVault.balanceOf(owner.address)).to.equal(initialShares.sub(withdrawShares));
      
      // Check that assets were returned
      expect(await mockUSDC.balanceOf(owner.address)).to.be.gt(initialAssets);
    });
  });
  
  describe("Rebalancing", function () {
    const depositAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
    
    beforeEach(async function () {
      // Approve vault to spend owner's USDC
      await mockUSDC.approve(await rwaIndexFundVault.getAddress(), depositAmount.mul(2));
      
      // Deposit assets
      await rwaIndexFundVault.deposit(depositAmount, owner.address);
    });
    
    it("Should rebalance the vault", async function () {
      // Set up index composition
      const tokens = [await mockUSDC.getAddress()];
      const weights = [10000]; // 100%
      await indexRegistry.updateIndex(tokens, weights);
      
      // Rebalance
      await rwaIndexFundVault.rebalance();
      
      // Check that last rebalance timestamp was updated
      expect(await rwaIndexFundVault.lastRebalanceTimestamp()).to.be.gt(0);
    });
    
    it("Should rebalance capital allocation", async function () {
      await rwaIndexFundVault.rebalanceCapitalAllocation();
      
      // Check that last rebalance timestamp was updated
      expect(await rwaIndexFundVault.lastRebalanceTimestamp()).to.be.gt(0);
    });
  });
  
  describe("RWA Token Management", function () {
    it("Should add RWA token", async function () {
      const newRWAToken = user.address; // Using user address as a mock token for simplicity
      const percentage = 5000; // 50%
      
      await rwaIndexFundVault.addRWAToken(newRWAToken, percentage);
      
      // Check that the token was added to the capital allocation manager
      const rwaTokens = await capitalAllocationManager.getRWATokens();
      const found = rwaTokens.some(token => token.rwaToken === newRWAToken && token.percentage.eq(percentage));
      expect(found).to.be.true;
    });
    
    it("Should remove RWA token", async function () {
      // First add a token
      const newRWAToken = user.address;
      const percentage = 5000;
      await rwaIndexFundVault.addRWAToken(newRWAToken, percentage);
      
      // Then remove it
      await rwaIndexFundVault.removeRWAToken(newRWAToken);
      
      // Check that the token was removed
      const rwaTokens = await capitalAllocationManager.getRWATokens();
      const found = rwaTokens.some(token => token.rwaToken === newRWAToken && token.active);
      expect(found).to.be.false;
    });
  });
  
  describe("Fee Collection", function () {
    const depositAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
    
    beforeEach(async function () {
      // Approve vault to spend owner's USDC
      await mockUSDC.approve(await rwaIndexFundVault.getAddress(), depositAmount.mul(2));
      
      // Deposit assets
      await rwaIndexFundVault.deposit(depositAmount, owner.address);
    });
    
    it("Should collect management fee", async function () {
      // Set management fee to 10% for easier testing
      await rwaIndexFundVault.setManagementFeePercentage(1000);
      
      // Fast forward time (1 year)
      await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");
      
      // Rebalance to trigger fee collection
      await rwaIndexFundVault.rebalance();
      
      // Check that owner received fee shares
      expect(await rwaIndexFundVault.balanceOf(owner.address)).to.be.gt(depositAmount);
    });
    
    it("Should collect performance fee", async function () {
      // Set performance fee to 20%
      await rwaIndexFundVault.setPerformanceFeePercentage(2000);
      
      // Increase asset value by adding more USDC to the vault
      await mockUSDC.transfer(await rwaIndexFundVault.getAddress(), depositAmount);
      
      // Rebalance to trigger fee collection
      await rwaIndexFundVault.rebalance();
      
      // Check that owner received fee shares
      expect(await rwaIndexFundVault.balanceOf(owner.address)).to.be.gt(depositAmount);
    });
  });
});
