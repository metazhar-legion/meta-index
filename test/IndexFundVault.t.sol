// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IndexRegistry} from "../src/IndexRegistry.sol";
import {IndexFundVault} from "../src/IndexFundVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockFeeManager} from "../src/mocks/MockFeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";

/**
 * @title IndexFundVaultTest
 * @dev Test contract for the IndexFundVault
 */
contract IndexFundVaultTest is Test {
    IndexFundVault public vault;
    IndexRegistry public registry;
    MockERC20 public usdc;
    MockERC20 public wbtc;
    MockERC20 public weth;
    MockPriceOracle public priceOracle;
    MockDEX public dex;
    MockFeeManager public mockFeeManager;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        
        // Deploy price oracle
        priceOracle = new MockPriceOracle(address(usdc));
        priceOracle.setPrice(address(wbtc), 50_000 * 1e18);
        priceOracle.setPrice(address(weth), 3_000 * 1e18);
        
        // Deploy DEX
        dex = new MockDEX(priceOracle);
        
        // Deploy index registry
        registry = new IndexRegistry();
        
        // Deploy MockFeeManager
        mockFeeManager = new MockFeeManager();
        
        // Deploy vault
        vault = new IndexFundVault(
            usdc,
            registry,
            priceOracle,
            dex,
            IFeeManager(address(mockFeeManager))
        );
        
        // Set up initial index
        registry.addToken(address(wbtc), 7000); // 70%
        registry.addToken(address(weth), 3000); // 30%
        
        // Mint tokens for testing
        usdc.mint(owner, 1_000_000 * 1e6); // 1M USDC
        usdc.mint(user1, 10_000 * 1e6);    // 10k USDC
        usdc.mint(user2, 5_000 * 1e6);     // 5k USDC
        
        wbtc.mint(address(dex), 100 * 1e8);  // 100 BTC
        weth.mint(address(dex), 1000 * 1e18); // 1000 ETH
        
        vm.stopPrank();
    }
    
    function testDeposit() public {
        vm.startPrank(user1);
        
        uint256 depositAmount = 1_000 * 1e6; // 1,000 USDC
        
        // Approve the vault to spend USDC
        usdc.approve(address(vault), depositAmount);
        
        // Deposit USDC into the vault
        uint256 sharesBefore = vault.balanceOf(user1);
        vault.deposit(depositAmount, user1);
        uint256 sharesAfter = vault.balanceOf(user1);
        
        // Check that shares were minted
        assertGt(sharesAfter, sharesBefore);
        
        vm.stopPrank();
    }
    
    function testWithdraw() public {
        vm.startPrank(user1);
        
        uint256 depositAmount = 1_000 * 1e6; // 1,000 USDC
        
        // Approve the vault to spend USDC
        usdc.approve(address(vault), depositAmount);
        
        // Deposit USDC into the vault
        vault.deposit(depositAmount, user1);
        
        // Get the shares balance
        uint256 shares = vault.balanceOf(user1);
        
        // Withdraw half of the shares
        uint256 withdrawShares = shares / 2;
        uint256 usdcBefore = usdc.balanceOf(user1);
        vault.redeem(withdrawShares, user1, user1);
        uint256 usdcAfter = usdc.balanceOf(user1);
        
        // Check that USDC was returned
        assertGt(usdcAfter, usdcBefore);
        
        vm.stopPrank();
    }
    
    function testRebalance() public {
        vm.startPrank(owner);
        
        // Deposit a large amount to have funds for rebalancing
        uint256 depositAmount = 100_000 * 1e6; // 100,000 USDC
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, owner);
        
        // Rebalance the vault
        vault.rebalance();
        
        // Check that the vault has the correct token balances
        (address[] memory tokens, uint256[] memory weights) = vault.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(wbtc));
        assertEq(tokens[1], address(weth));
        assertEq(weights[0], 7000);
        assertEq(weights[1], 3000);
        
        vm.stopPrank();
    }
    
    function testUpdateIndex() public {
        vm.startPrank(owner);
        
        // Update the index weights
        registry.updateTokenWeight(address(wbtc), 6000); // 60%
        registry.updateTokenWeight(address(weth), 4000); // 40%
        
        // Check that the index was updated
        (address[] memory tokens, uint256[] memory weights) = vault.getCurrentIndex();
        
        assertEq(tokens.length, 2);
        assertEq(weights[0], 6000);
        assertEq(weights[1], 4000);
        
        vm.stopPrank();
    }
    
    function testFees() public {
        vm.startPrank(owner);
        
        // Set fees
        vault.setManagementFee(100); // 1%
        vault.setPerformanceFee(1000); // 10%
        
        // Deposit a large amount
        uint256 depositAmount = 100_000 * 1e6; // 100,000 USDC
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, owner);
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Rebalance to collect fees
        uint256 ownerSharesBefore = vault.balanceOf(owner);
        vault.rebalance();
        uint256 ownerSharesAfter = vault.balanceOf(owner);
        
        // Check that the owner received fees
        assertGt(ownerSharesAfter, ownerSharesBefore);
        
        vm.stopPrank();
    }
}
