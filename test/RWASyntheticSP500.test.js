const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RWASyntheticSP500", function () {
  let mockUSDC;
  let mockPriceOracle;
  let mockPerpetualTrading;
  let rwaSyntheticSP500;
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
    
    // Get the market ID
    marketId = await rwaSyntheticSP500.MARKET_ID();
  });
  
  describe("Initialization", function () {
    it("Should initialize with correct values", async function () {
      expect(await rwaSyntheticSP500.name()).to.equal("S&P 500 Index Synthetic");
      expect(await rwaSyntheticSP500.symbol()).to.equal("sSP500");
      expect(await rwaSyntheticSP500.baseAsset()).to.equal(await mockUSDC.getAddress());
      expect(await rwaSyntheticSP500.perpetualTrading()).to.equal(await mockPerpetualTrading.getAddress());
      expect(await rwaSyntheticSP500.priceOracle()).to.equal(await mockPriceOracle.getAddress());
      
      const assetInfo = await rwaSyntheticSP500.getAssetInfo();
      expect(assetInfo.name).to.equal("S&P 500 Index");
      expect(assetInfo.symbol).to.equal("SPX");
      expect(assetInfo.assetType).to.equal(0); // EQUITY_INDEX
      expect(assetInfo.oracle).to.equal(await mockPriceOracle.getAddress());
      expect(assetInfo.marketId).to.equal(marketId);
      expect(assetInfo.isActive).to.equal(true);
    });
  });
  
  describe("Price Updates", function () {
    it("Should update price from perpetual trading platform", async function () {
      const newPrice = ethers.parseEther("5100"); // $5100
      await mockPerpetualTrading.setMarketPrice(marketId, newPrice);
      
      await rwaSyntheticSP500.updatePrice();
      
      const assetInfo = await rwaSyntheticSP500.getAssetInfo();
      expect(assetInfo.lastPrice).to.equal(newPrice);
    });
    
    it("Should get current price", async function () {
      const newPrice = ethers.parseEther("5200"); // $5200
      await mockPerpetualTrading.setMarketPrice(marketId, newPrice);
      await rwaSyntheticSP500.updatePrice();
      
      expect(await rwaSyntheticSP500.getCurrentPrice()).to.equal(newPrice);
    });
  });
  
  describe("Minting and Burning", function () {
    const mintAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
    
    beforeEach(async function () {
      // Approve RWASyntheticSP500 to spend owner's USDC
      await mockUSDC.approve(await rwaSyntheticSP500.getAddress(), mintAmount);
    });
    
    it("Should mint synthetic tokens", async function () {
      await rwaSyntheticSP500.mint(owner.address, mintAmount);
      
      expect(await rwaSyntheticSP500.balanceOf(owner.address)).to.equal(mintAmount);
      expect(await mockUSDC.balanceOf(await rwaSyntheticSP500.getAddress())).to.equal(mintAmount);
      
      // Check that a position was opened
      expect(await rwaSyntheticSP500.activePositionId()).to.not.equal(ethers.ZeroHash);
      expect(await rwaSyntheticSP500.totalCollateral()).to.equal(mintAmount.mul(5000).div(10000)); // 50% collateral
    });
    
    it("Should burn synthetic tokens", async function () {
      // First mint some tokens
      await rwaSyntheticSP500.mint(owner.address, mintAmount);
      
      // Then burn half of them
      const burnAmount = mintAmount.div(2);
      await rwaSyntheticSP500.burn(owner.address, burnAmount);
      
      expect(await rwaSyntheticSP500.balanceOf(owner.address)).to.equal(mintAmount.sub(burnAmount));
      
      // Check that collateral was reduced
      expect(await rwaSyntheticSP500.totalCollateral()).to.equal(mintAmount.sub(burnAmount).mul(5000).div(10000));
    });
    
    it("Should fail to mint with insufficient allowance", async function () {
      // Reduce allowance
      await mockUSDC.approve(await rwaSyntheticSP500.getAddress(), mintAmount.div(2));
      
      await expect(
        rwaSyntheticSP500.mint(owner.address, mintAmount)
      ).to.be.reverted;
    });
    
    it("Should fail to burn more than balance", async function () {
      // Mint some tokens
      await rwaSyntheticSP500.mint(owner.address, mintAmount);
      
      // Try to burn more than balance
      await expect(
        rwaSyntheticSP500.burn(owner.address, mintAmount.mul(2))
      ).to.be.revertedWith("Insufficient balance");
    });
  });
  
  describe("Position Management", function () {
    const mintAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
    
    beforeEach(async function () {
      // Approve RWASyntheticSP500 to spend owner's USDC
      await mockUSDC.approve(await rwaSyntheticSP500.getAddress(), mintAmount.mul(2));
      
      // Mint some tokens
      await rwaSyntheticSP500.mint(owner.address, mintAmount);
    });
    
    it("Should increase position when minting more tokens", async function () {
      const initialCollateral = await rwaSyntheticSP500.totalCollateral();
      const initialPositionId = await rwaSyntheticSP500.activePositionId();
      
      // Mint more tokens
      await rwaSyntheticSP500.mint(owner.address, mintAmount);
      
      // Position should be increased, not replaced
      expect(await rwaSyntheticSP500.activePositionId()).to.equal(initialPositionId);
      expect(await rwaSyntheticSP500.totalCollateral()).to.equal(initialCollateral.mul(2));
    });
    
    it("Should reduce position when burning tokens", async function () {
      const initialCollateral = await rwaSyntheticSP500.totalCollateral();
      
      // Burn half the tokens
      await rwaSyntheticSP500.burn(owner.address, mintAmount.div(2));
      
      // Collateral should be reduced
      expect(await rwaSyntheticSP500.totalCollateral()).to.equal(initialCollateral.div(2));
    });
    
    it("Should close position when burning all tokens", async function () {
      // Burn all tokens
      await rwaSyntheticSP500.burn(owner.address, mintAmount);
      
      // Position should be closed
      expect(await rwaSyntheticSP500.activePositionId()).to.equal(ethers.ZeroHash);
      expect(await rwaSyntheticSP500.totalCollateral()).to.equal(0);
    });
  });
  
  describe("Leverage Settings", function () {
    it("Should set leverage correctly", async function () {
      const newLeverage = 5;
      await rwaSyntheticSP500.setLeverage(newLeverage);
      
      expect(await rwaSyntheticSP500.leverage()).to.equal(newLeverage);
    });
    
    it("Should fail to set invalid leverage", async function () {
      await expect(
        rwaSyntheticSP500.setLeverage(0)
      ).to.be.revertedWith("Invalid leverage value");
      
      await expect(
        rwaSyntheticSP500.setLeverage(11)
      ).to.be.revertedWith("Invalid leverage value");
    });
  });
  
  describe("Oracle Settings", function () {
    it("Should set price oracle correctly", async function () {
      const newOracle = user.address;
      await rwaSyntheticSP500.setPriceOracle(newOracle);
      
      expect(await rwaSyntheticSP500.priceOracle()).to.equal(newOracle);
      
      const assetInfo = await rwaSyntheticSP500.getAssetInfo();
      expect(assetInfo.oracle).to.equal(newOracle);
    });
    
    it("Should fail to set invalid oracle", async function () {
      await expect(
        rwaSyntheticSP500.setPriceOracle(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid price oracle address");
    });
  });
  
  describe("Total Value", function () {
    it("Should calculate total value correctly", async function () {
      const mintAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
      await mockUSDC.approve(await rwaSyntheticSP500.getAddress(), mintAmount);
      await rwaSyntheticSP500.mint(owner.address, mintAmount);
      
      // Set price to 5000 USD
      const price = ethers.parseEther("5000");
      await mockPerpetualTrading.setMarketPrice(marketId, price);
      await rwaSyntheticSP500.updatePrice();
      
      // Total value should be mintAmount * price / 1e18
      const expectedValue = mintAmount.mul(price).div(ethers.parseEther("1"));
      expect(await rwaSyntheticSP500.getTotalValue()).to.equal(expectedValue);
    });
    
    it("Should return zero for empty token", async function () {
      expect(await rwaSyntheticSP500.getTotalValue()).to.equal(0);
    });
  });
});
