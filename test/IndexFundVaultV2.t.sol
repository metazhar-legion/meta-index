// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {RWAAssetWrapper} from "../src/RWAAssetWrapper.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
import {MockFeeManager} from "../src/mocks/MockFeeManager.sol";
import {RWASyntheticSP500} from "../src/RWASyntheticSP500.sol";
import {StableYieldStrategy} from "../src/StableYieldStrategy.sol";
import {MockPerpetualTrading} from "../src/mocks/MockPerpetualTrading.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

contract IndexFundVaultV2Test is Test {
    // Contracts
    IndexFundVaultV2 public vault;
    RWAAssetWrapper public rwaWrapper;
    MockUSDC public mockUSDC;
    MockPriceOracle public mockPriceOracle;
    MockDEX public mockDEX;
    MockFeeManager public mockFeeManager;
    RWASyntheticSP500 public rwaSyntheticSP500;
    StableYieldStrategy public stableYieldStrategy;
    MockPerpetualTrading public mockPerpetualTrading;
    
    // Users
    address public owner;
    address public user1;
    address public user2;
    
    // Constants
    uint256 public constant INITIAL_PRICE = 5000 * 1e6; // $5000 in USDC decimals
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 1e6; // 10000 USDC
    uint256 public constant INITIAL_BALANCE = 100000 * 1e6; // 100000 USDC initial balance for users
    
    // Events
    event AssetAdded(address indexed assetAddress, uint256 weight);
    event Rebalanced();
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    
    function setUp() public {
        owner = address(this); // Test contract is the owner
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock contracts
        mockUSDC = new MockUSDC();
        mockPriceOracle = new MockPriceOracle(address(mockUSDC));
        mockDEX = new MockDEX(address(mockPriceOracle));
        mockFeeManager = new MockFeeManager();
        mockPerpetualTrading = new MockPerpetualTrading(address(mockUSDC));
        
        // Deploy RWA synthetic token
        rwaSyntheticSP500 = new RWASyntheticSP500(
            address(mockUSDC),
            address(mockPerpetualTrading),
            address(mockPriceOracle)
        );
        
        // Set initial price in the oracle
        mockPriceOracle.setPrice(address(rwaSyntheticSP500), INITIAL_PRICE);
        
        // Mint USDC to this contract for allocating to RWA
        mockUSDC.mint(address(this), 1000000 * 1e6); // 1M USDC
        
        // Deploy yield strategy
        stableYieldStrategy = new StableYieldStrategy(
            "Stable Yield",
            address(mockUSDC),
            address(0x1), // Mock yield protocol
            address(mockUSDC), // Using USDC as yield token for simplicity
            address(this) // Fee recipient
        );
        
        // Deploy RWA wrapper (owned by this test contract)
        rwaWrapper = new RWAAssetWrapper(
            "S&P 500 RWA",
            IERC20(address(mockUSDC)),
            rwaSyntheticSP500,
            stableYieldStrategy,
            mockPriceOracle
        );
        
        // Transfer ownership of RWA token to the wrapper
        rwaSyntheticSP500.transferOwnership(address(rwaWrapper));
        
        // Deploy vault (owned by this test contract)
        vault = new IndexFundVaultV2(
            IERC20(address(mockUSDC)),
            mockFeeManager,
            mockPriceOracle,
            mockDEX
        );
        
        // Approve USDC for the RWA wrapper
        mockUSDC.approve(address(rwaWrapper), type(uint256).max);
        
        // Approve USDC for the vault to spend
        mockUSDC.approve(address(vault), type(uint256).max);
        
        // Mint USDC to users
        mockUSDC.mint(user1, INITIAL_BALANCE);
        mockUSDC.mint(user2, INITIAL_BALANCE);
        
        // Approve USDC for the vault
        vm.startPrank(user1);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockUSDC.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }
    
    function test_Initialization() public {
        assertEq(address(vault.asset()), address(mockUSDC));
        assertEq(address(vault.feeManager()), address(mockFeeManager));
        assertEq(address(vault.priceOracle()), address(mockPriceOracle));
        assertEq(address(vault.dex()), address(mockDEX));
    }
    
    function test_AddAsset() public {
        // Add RWA wrapper to the vault
        vm.expectEmit(true, true, true, true);
        emit AssetAdded(address(rwaWrapper), 5000); // 50% weight
        
        vault.addAsset(address(rwaWrapper), 5000);
        
        // Check asset was added correctly
        (address wrapper, uint256 weight, bool active) = vault.getAssetInfo(address(rwaWrapper));
        assertEq(wrapper, address(rwaWrapper));
        assertEq(weight, 5000);
        assertTrue(active);
        
        // Check total weight
        assertEq(vault.getTotalWeight(), 5000);
    }
    
    function test_Deposit() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Make sure the RWA token can mint
        mockUSDC.mint(address(rwaSyntheticSP500), 1000000 * 1e6); // Ensure RWA token has USDC
        
        // Deposit from user1
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user1, user1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT); // 1:1 ratio initially
        
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Check user1 received shares
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT);
        
        // Check total assets
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    }
    
    function test_Withdraw() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Withdraw half
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 sharesToWithdraw = vault.previewWithdraw(withdrawAmount);
        
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user1, user1, user1, withdrawAmount, sharesToWithdraw);
        
        vault.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();
        
        // Check user1 shares were burned
        assertEq(vault.balanceOf(user1), sharesBefore - sharesToWithdraw);
        
        // Check user1 received USDC
        assertEq(mockUSDC.balanceOf(user1), INITIAL_BALANCE - DEPOSIT_AMOUNT + withdrawAmount);
    }
    
    function test_Rebalance() public {
        // Add RWA wrapper to the vault with 50% weight
        vault.addAsset(address(rwaWrapper), 5000);
        
        // Make sure the RWA token can mint
        mockUSDC.mint(address(rwaSyntheticSP500), 1000000 * 1e6); // Ensure RWA token has USDC
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Force rebalance interval to pass
        vm.warp(block.timestamp + vault.rebalanceInterval() + 1);
        
        // Rebalance (as owner - this test contract)
        vault.rebalance();
        
        // Check assets were allocated according to weights
        uint256 totalAssets = vault.totalAssets();
        uint256 rwaValue = rwaWrapper.getValueInBaseAsset();
        
        // Allow for small rounding errors (within 0.1%)
        assertApproxEqRel(rwaValue, totalAssets / 2, 0.001e18);
    }
    
    function test_MultipleAssets() public {
        // Create a second RWA token for the second wrapper
        RWASyntheticSP500 rwaSyntheticSP500_2 = new RWASyntheticSP500(
            address(mockUSDC),
            address(mockPerpetualTrading),
            address(mockPriceOracle)
        );
        
        // Set initial price in the oracle
        mockPriceOracle.setPrice(address(rwaSyntheticSP500_2), INITIAL_PRICE);
        
        // Create a second RWA wrapper (owned by this test contract)
        RWAAssetWrapper rwaWrapper2 = new RWAAssetWrapper(
            "Second RWA",
            IERC20(address(mockUSDC)),
            rwaSyntheticSP500_2,
            stableYieldStrategy,
            mockPriceOracle
        );
        
        // Transfer ownership of second RWA token to the second wrapper
        rwaSyntheticSP500_2.transferOwnership(address(rwaWrapper2));
        
        // Approve USDC for the second RWA wrapper
        mockUSDC.approve(address(rwaWrapper2), type(uint256).max);
        
        // Make sure the RWA tokens can mint
        mockUSDC.mint(address(rwaSyntheticSP500), 1000000 * 1e6); // Ensure first RWA token has USDC
        mockUSDC.mint(address(rwaSyntheticSP500_2), 1000000 * 1e6); // Ensure second RWA token has USDC
        
        // Add both wrappers to the vault
        vault.addAsset(address(rwaWrapper), 4000); // 40%
        vault.addAsset(address(rwaWrapper2), 6000); // 60%
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Force rebalance interval to pass
        vm.warp(block.timestamp + vault.rebalanceInterval() + 1);
        
        // Rebalance
        vault.rebalance();
        
        // Check assets were allocated according to weights
        uint256 totalAssets = vault.totalAssets();
        uint256 rwa1Value = rwaWrapper.getValueInBaseAsset();
        uint256 rwa2Value = rwaWrapper2.getValueInBaseAsset();
        
        // Allow for small rounding errors (within 0.1%)
        assertApproxEqRel(rwa1Value, totalAssets * 4000 / 10000, 0.001e18);
        assertApproxEqRel(rwa2Value, totalAssets * 6000 / 10000, 0.001e18);
    }
    
    function test_HarvestYield() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 10000); // 100% weight
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Make sure the RWA token can mint
        mockUSDC.mint(address(rwaSyntheticSP500), 1000000 * 1e6); // Ensure RWA token has USDC
        
        // Simulate yield by minting USDC to the yield strategy
        mockUSDC.mint(address(stableYieldStrategy), 1000 * 1e6);
        
        // Harvest yield (as owner)
        uint256 harvestedAmount = vault.harvestYield();
        
        // Check harvested amount
        assertEq(harvestedAmount, 1000 * 1e6);
        
        // Check USDC balance of vault increased
        assertEq(mockUSDC.balanceOf(address(vault)), 1000 * 1e6);
    }
    
    function test_UpdateAssetWeight() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 5000); // 50% weight
        
        // Update weight to 70%
        vault.updateAssetWeight(address(rwaWrapper), 7000);
        
        // Check weight was updated
        (,uint256 weight,) = vault.getAssetInfo(address(rwaWrapper));
        assertEq(weight, 7000);
        
        // Check total weight
        assertEq(vault.getTotalWeight(), 7000);
    }
    
    function test_RemoveAsset() public {
        // Add RWA wrapper to the vault
        vault.addAsset(address(rwaWrapper), 5000); // 50% weight
        
        // Make sure the RWA token can mint
        mockUSDC.mint(address(rwaSyntheticSP500), 1000000 * 1e6); // Ensure RWA token has USDC
        
        // Deposit from user1
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Force rebalance to allocate assets
        vm.warp(block.timestamp + vault.rebalanceInterval() + 1);
        vault.rebalance();
        
        // Remove the asset (as owner)
        vault.removeAsset(address(rwaWrapper));
        
        // Check asset was removed
        (,uint256 weight, bool active) = vault.getAssetInfo(address(rwaWrapper));
        assertEq(weight, 0);
        assertFalse(active);
        
        // Check total weight
        assertEq(vault.getTotalWeight(), 0);
        
        // Check funds were returned to the vault
        assertGt(mockUSDC.balanceOf(address(vault)), 0);
    }
}
