// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ConcreteRWAIndexFundVault} from "../src/ConcreteRWAIndexFundVault.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";
import {MockIndexRegistry} from "../src/mocks/MockIndexRegistry.sol";
import {MockCapitalAllocationManager} from "../src/mocks/MockCapitalAllocationManager.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIndexRegistry} from "../src/interfaces/IIndexRegistry.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";
import {ICapitalAllocationManager} from "../src/interfaces/ICapitalAllocationManager.sol";

contract ConcreteRWAIndexFundVaultTest is Test {
    ConcreteRWAIndexFundVault public vault;
    RWASyntheticSP500 public rwaSyntheticSP500;
    MockUSDC public mockUSDC;
    MockPriceOracle public mockPriceOracle;
    MockPerpetualTrading public mockPerpetualTrading;
    MockIndexRegistry public mockIndexRegistry;
    MockCapitalAllocationManager public mockCapitalAllocationManager;
    MockDEX public mockDEX;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_PRICE = 5000 * 1e6; // $5000 in USDC decimals
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 1e6; // 10000 USDC
    uint256 public constant COLLATERAL_RATIO = 12000; // 120% in basis points
    uint256 public constant RWA_ALLOCATION = 7000; // 70% in basis points
    uint256 public constant YIELD_ALLOCATION = 2000; // 20% in basis points
    uint256 public constant LIQUIDITY_BUFFER = 1000; // 10% in basis points

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event Rebalanced(uint256 timestamp);
    event RWATokenAdded(address indexed rwaToken, uint256 allocation);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock contracts
        mockUSDC = new MockUSDC();
        mockPriceOracle = new MockPriceOracle(address(mockUSDC));
        mockPerpetualTrading = new MockPerpetualTrading(address(mockUSDC));
        mockIndexRegistry = new MockIndexRegistry();
        mockDEX = new MockDEX(mockPriceOracle);

        // Deploy RWASyntheticSP500
        rwaSyntheticSP500 = new RWASyntheticSP500(
            address(mockUSDC),
            address(mockPerpetualTrading),
            address(mockPriceOracle)
        );
        
        // Set initial price in the oracle
        mockPriceOracle.setPrice(address(rwaSyntheticSP500), INITIAL_PRICE);

        // Deploy CapitalAllocationManager
        mockCapitalAllocationManager = new MockCapitalAllocationManager(mockUSDC);
        mockCapitalAllocationManager.setAllocation(
            RWA_ALLOCATION,
            YIELD_ALLOCATION,
            LIQUIDITY_BUFFER
        );
        mockCapitalAllocationManager.addRWAToken(address(rwaSyntheticSP500), 10000); // 100% allocation to SP500

        // Deploy ConcreteRWAIndexFundVault
        vault = new ConcreteRWAIndexFundVault(
            IERC20(address(mockUSDC)),
            IIndexRegistry(address(mockIndexRegistry)),
            IPriceOracle(address(mockPriceOracle)),
            IDEX(address(mockDEX)),
            ICapitalAllocationManager(address(mockCapitalAllocationManager))
        );

        // Mint some USDC to users for testing
        mockUSDC.mint(user1, 100000 * 1e6);
        mockUSDC.mint(user2, 100000 * 1e6);
    }

    function test_Initialization() public {
        assertEq(vault.name(), "RWA Index Fund Vault");
        assertEq(vault.symbol(), "RWAV");
        assertEq(address(vault.asset()), address(mockUSDC));
        assertEq(address(vault.indexRegistry()), address(mockIndexRegistry));
        assertEq(address(vault.capitalAllocationManager()), address(mockCapitalAllocationManager));
        assertEq(address(vault.dex()), address(mockDEX));
    }

    function test_Deposit() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        
        // Approve USDC spending
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        
        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, depositAmount, depositAmount); // Initial shares = deposit amount
        
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(mockUSDC.balanceOf(address(vault)), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_Withdraw() public {
        // First deposit
        uint256 depositAmount = DEPOSIT_AMOUNT;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        // Now withdraw half
        uint256 withdrawShares = depositAmount / 2;
        uint256 expectedWithdrawAmount = withdrawShares; // 1:1 ratio initially
        
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user1, expectedWithdrawAmount, withdrawShares);
        
        vault.withdraw(withdrawShares);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), depositAmount - withdrawShares);
        assertEq(mockUSDC.balanceOf(address(vault)), depositAmount - expectedWithdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - expectedWithdrawAmount);
    }

    function test_AddRWAToken() public {
        // Create a new RWA token
        RWASyntheticSP500 newRWAToken = new RWASyntheticSP500(
            address(mockUSDC),
            address(mockPerpetualTrading),
            address(mockPriceOracle)
        );
        
        uint256 allocation = 5000; // 50% in basis points
        
        vm.expectEmit(true, true, true, true);
        emit RWATokenAdded(address(newRWAToken), allocation);
        
        vault.addRWAToken(address(newRWAToken), allocation);
        
        // Check that the token was added to the capital allocation manager
        assertEq(mockCapitalAllocationManager.getRWATokenPercentage(address(newRWAToken)), allocation);
    }

    function test_Rebalance() public {
        // First deposit
        uint256 depositAmount = DEPOSIT_AMOUNT;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Rebalance the vault
        vm.expectEmit(true, true, true, true);
        emit Rebalanced(block.timestamp);
        
        vault.rebalance();
        
        // Check that the capital allocation manager was called to rebalance
        // This is a mock, so we just verify the vault's state
        assertEq(vault.lastRebalanced(), block.timestamp);
    }

    function test_MultipleUsersDeposit() public {
        // User 1 deposits
        uint256 depositAmount1 = 10000 * 1e6;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1);
        vm.stopPrank();
        
        // User 2 deposits
        uint256 depositAmount2 = 20000 * 1e6;
        
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2);
        vm.stopPrank();
        
        // Verify balances
        assertEq(vault.balanceOf(user1), depositAmount1);
        assertEq(vault.balanceOf(user2), depositAmount2);
        assertEq(mockUSDC.balanceOf(address(vault)), depositAmount1 + depositAmount2);
        assertEq(vault.totalAssets(), depositAmount1 + depositAmount2);
        assertEq(vault.totalSupply(), depositAmount1 + depositAmount2);
    }

    function test_DepositWithdrawWithYield() public {
        // User 1 deposits
        uint256 depositAmount = 10000 * 1e6;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Simulate yield by directly transferring more USDC to the vault
        uint256 yieldAmount = 1000 * 1e6;
        mockUSDC.mint(address(vault), yieldAmount);
        
        // Total assets should include the yield
        assertEq(vault.totalAssets(), depositAmount + yieldAmount);
        
        // User 1 withdraws all shares
        uint256 withdrawShares = vault.balanceOf(user1);
        uint256 expectedWithdrawAmount = depositAmount + yieldAmount; // All assets including yield
        
        vm.startPrank(user1);
        vault.withdraw(withdrawShares);
        vm.stopPrank();
        
        // Verify user received all assets including yield
        assertEq(mockUSDC.balanceOf(user1), 100000 * 1e6 - depositAmount + expectedWithdrawAmount);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(mockUSDC.balanceOf(address(vault)), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_RevertWhenInsufficientBalance() public {
        // User 1 deposits
        uint256 depositAmount = 10000 * 1e6;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        // Try to withdraw more than deposited
        uint256 tooManyShares = depositAmount + 1;
        
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vault.withdraw(tooManyShares);
        vm.stopPrank();
    }

    function test_RevertWhenVaultPaused() public {
        // Pause the vault
        vault.pause();
        
        uint256 depositAmount = 10000 * 1e6;
        
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), depositAmount);
        
        vm.expectRevert("Pausable: paused");
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Unpause and try again
        vault.unpause();
        
        vm.startPrank(user1);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), depositAmount);
    }

    function test_OnlyOwnerFunctions() public {
        // Create a new RWA token
        RWASyntheticSP500 newRWAToken = new RWASyntheticSP500(
            address(mockUSDC),
            address(mockPerpetualTrading),
            address(mockPriceOracle)
        );
        
        // Try to add RWA token as non-owner
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.addRWAToken(address(newRWAToken), 5000);
        vm.stopPrank();
        
        // Try to rebalance as non-owner
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.rebalance();
        vm.stopPrank();
        
        // Try to pause as non-owner
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.pause();
        vm.stopPrank();
    }
}
