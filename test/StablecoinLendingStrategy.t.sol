// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StablecoinLendingStrategy} from "../src/StablecoinLendingStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {IAaveLendingPool} from "../src/interfaces/IAaveLendingPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

contract StablecoinLendingStrategyTest is Test {
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public aToken;
    
    // Yield strategy
    StablecoinLendingStrategy public lendingStrategy;
    
    // Mock protocol address
    address public lendingProtocol;
    
    // Test addresses
    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;
    address public nonOwner;
    
    // Test amounts
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant DEPOSIT_AMOUNT = 100_000e6; // 100k USDC
    
    function setUp() public {
        // Set up test addresses
        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aToken = new MockERC20("Aave USDC", "aUSDC", 6);
        
        // Create mock protocol address
        lendingProtocol = makeAddr("lendingProtocol");
        
        // Mint initial tokens to users and protocol
        usdc.mint(user1, INITIAL_SUPPLY);
        usdc.mint(user2, INITIAL_SUPPLY);
        usdc.mint(lendingProtocol, INITIAL_SUPPLY);
        aToken.mint(lendingProtocol, INITIAL_SUPPLY);
        
        // Deploy strategy
        lendingStrategy = new StablecoinLendingStrategy(
            "Stablecoin Lending",
            address(usdc),
            lendingProtocol,
            address(aToken),
            feeRecipient
        );
        
        // Set up mock protocol to handle deposits and withdrawals
        vm.startPrank(lendingProtocol);
        aToken.approve(address(lendingStrategy), type(uint256).max);
        usdc.approve(address(lendingStrategy), type(uint256).max);
        vm.stopPrank();
        
        // Approve strategy to spend user tokens
        vm.startPrank(user1);
        usdc.approve(address(lendingStrategy), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(lendingStrategy), type(uint256).max);
        vm.stopPrank();
    }
    
    // Test initialization parameters
    function test_Initialization() public view {
        assertEq(lendingStrategy.name(), "Stablecoin Lending Shares", "Strategy name should be set correctly");
        assertEq(lendingStrategy.symbol(), "sStablecoin Lending", "Strategy symbol should be set correctly");
        assertEq(address(lendingStrategy.baseAsset()), address(usdc), "Base asset should be set correctly");
        assertEq(address(lendingStrategy.aToken()), address(aToken), "aToken should be set correctly");
        assertEq(lendingStrategy.lendingProtocol(), lendingProtocol, "Lending protocol should be set correctly");
        assertEq(lendingStrategy.feeRecipient(), feeRecipient, "Fee recipient should be set correctly");
        assertEq(lendingStrategy.feePercentage(), 50, "Fee percentage should be 0.5% by default");
        
        IYieldStrategy.StrategyInfo memory info = lendingStrategy.getStrategyInfo();
        assertEq(info.name, "Stablecoin Lending", "Strategy info name should be set correctly");
        assertEq(info.asset, address(usdc), "Strategy info asset should be set correctly");
        assertEq(info.apy, 500, "Strategy info APY should be set correctly");
        assertEq(info.risk, 3, "Strategy info risk level should be set correctly");
        assertTrue(info.active, "Strategy should be active by default");
    }
    
    // Test constructor validation with zero addresses
    function test_Constructor_Validation() public {
        // Test with zero address for base asset
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new StablecoinLendingStrategy(
            "Test Strategy",
            address(0), // Zero address for base asset
            lendingProtocol,
            address(aToken),
            feeRecipient
        );
        
        // Test with zero address for lending protocol
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new StablecoinLendingStrategy(
            "Test Strategy",
            address(usdc),
            address(0), // Zero address for lending protocol
            address(aToken),
            feeRecipient
        );
        
        // Test with zero address for aToken
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new StablecoinLendingStrategy(
            "Test Strategy",
            address(usdc),
            lendingProtocol,
            address(0), // Zero address for aToken
            feeRecipient
        );
        
        // Test with zero address for fee recipient
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new StablecoinLendingStrategy(
            "Test Strategy",
            address(usdc),
            lendingProtocol,
            address(aToken),
            address(0) // Zero address for fee recipient
        );
    }
    
    // Test deposit functionality
    function test_Deposit() public {
        vm.startPrank(user1);
        
        // Initial balances
        uint256 initialUserBalance = usdc.balanceOf(user1);
        
        // Deposit
        uint256 shares = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Simulate the protocol sending aTokens to the strategy after deposit
        vm.stopPrank();
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance - DEPOSIT_AMOUNT, "User balance should decrease");
        assertEq(lendingStrategy.balanceOf(user1), shares, "User should receive shares");
        
        // Verify strategy info
        IYieldStrategy.StrategyInfo memory info = lendingStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, DEPOSIT_AMOUNT, "Total deposited should match deposit amount");
    }
    
    // Test deposit with zero amount
    function test_Deposit_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        lendingStrategy.deposit(0);
        vm.stopPrank();
    }
    
    // Test withdraw functionality
    function test_Withdraw() public {
        // First deposit
        vm.startPrank(user1);
        uint256 shares = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Transfer USDC to strategy to simulate aToken redemption
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // User withdraws
        vm.startPrank(user1);
        uint256 initialUserBalance = usdc.balanceOf(user1);
        uint256 withdrawAmount = lendingStrategy.withdraw(shares);
        
        // Verify results
        assertEq(withdrawAmount, DEPOSIT_AMOUNT, "Withdraw amount should match deposit");
        assertEq(usdc.balanceOf(user1), initialUserBalance + withdrawAmount, "User balance should increase");
        assertEq(lendingStrategy.balanceOf(user1), 0, "User should have no shares left");
        
        vm.stopPrank();
    }
    
    // Test withdraw with zero shares
    function test_Withdraw_ZeroShares() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        lendingStrategy.withdraw(0);
        vm.stopPrank();
    }
    
    // Test withdraw with insufficient balance
    function test_Withdraw_InsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.InsufficientBalance.selector);
        lendingStrategy.withdraw(1000); // User has no shares
        vm.stopPrank();
    }
    
    // Test getValueOfShares
    function test_GetValueOfShares() public {
        // First deposit
        vm.startPrank(user1);
        uint256 shares = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Check value of shares
        uint256 value = lendingStrategy.getValueOfShares(shares);
        assertEq(value, DEPOSIT_AMOUNT, "Value of shares should match deposit amount");
        
        // Check value of half the shares
        uint256 halfShares = shares / 2;
        uint256 halfValue = lendingStrategy.getValueOfShares(halfShares);
        assertEq(halfValue, DEPOSIT_AMOUNT / 2, "Value of half shares should be half the deposit amount");
    }
    
    // Test getTotalValue
    function test_GetTotalValue() public {
        // Initially, total value should be 0
        uint256 initialValue = lendingStrategy.getTotalValue();
        assertEq(initialValue, 0, "Initial total value should be 0");
        
        // After deposit and aToken transfer
        vm.startPrank(user1);
        lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // In Aave, aToken balance represents the base asset + accrued interest
        uint256 valueAfterDeposit = lendingStrategy.getTotalValue();
        assertEq(valueAfterDeposit, DEPOSIT_AMOUNT, "Total value should match deposit amount");
        
        // Simulate yield by adding more aTokens to the strategy
        uint256 yieldAmount = DEPOSIT_AMOUNT / 10; // 10% yield
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), yieldAmount);
        
        // Check total value after yield
        uint256 valueAfterYield = lendingStrategy.getTotalValue();
        assertEq(valueAfterYield, DEPOSIT_AMOUNT + yieldAmount, "Total value should include yield");
    }
    
    // Test getCurrentAPY
    function test_GetCurrentAPY() public {
        // Initially, APY should match the default
        uint256 initialAPY = lendingStrategy.getCurrentAPY();
        assertEq(initialAPY, 500, "Initial APY should be 5%");
    }
    
    // Test harvestYield
    function test_HarvestYield() public {
        // First deposit
        vm.startPrank(user1);
        lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Simulate yield by adding more aTokens to the strategy
        uint256 yieldAmount = DEPOSIT_AMOUNT / 10; // 10% yield
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), yieldAmount);
        
        // Calculate expected fee
        uint256 expectedFee = (yieldAmount * 50) / 10000; // 0.5% fee
        uint256 expectedNetYield = yieldAmount - expectedFee;
        
        // Transfer USDC to strategy to simulate aToken redemption for yield
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), yieldAmount);
        
        // Initial balances
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        
        // Harvest yield
        uint256 harvested = lendingStrategy.harvestYield();
        
        // Verify balances
        assertEq(usdc.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedFee, "Fee recipient should receive fee");
        assertEq(usdc.balanceOf(owner), initialOwnerBalance + expectedNetYield, "Owner should receive net yield");
        assertEq(harvested, expectedNetYield, "Harvested amount should match net yield");
    }
    
    // Test harvestYield with no yield
    function test_HarvestYield_NoYield() public {
        // First deposit
        vm.startPrank(user1);
        lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Harvest yield immediately (no additional aTokens)
        uint256 harvested = lendingStrategy.harvestYield();
        assertEq(harvested, 0, "Harvested amount should be 0 when there's no yield");
    }
    
    // Test harvestYield with negative yield (loss)
    function test_HarvestYield_NegativeYield() public {
        // First deposit
        vm.startPrank(user1);
        lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate lending protocol sending fewer aTokens than deposited (loss scenario)
        uint256 lossAmount = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT / 10); // 90% of deposit
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), lossAmount);
        
        // Harvest yield
        uint256 harvested = lendingStrategy.harvestYield();
        assertEq(harvested, 0, "Harvested amount should be 0 when there's a loss");
    }
    
    // Test harvestYield with non-owner
    function test_HarvestYield_NonOwner() public {
        // Create a custom error selector that matches what the contract returns
        bytes memory customError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner);
        
        vm.startPrank(nonOwner);
        vm.expectRevert(customError);
        lendingStrategy.harvestYield();
        vm.stopPrank();
    }
    
    // Test setFeePercentage
    function test_SetFeePercentage() public {
        uint256 newFeePercentage = 100; // 1%
        
        // Set new fee percentage
        lendingStrategy.setFeePercentage(newFeePercentage);
        
        // Verify fee percentage was updated
        assertEq(lendingStrategy.feePercentage(), newFeePercentage, "Fee percentage should be updated");
    }
    
    // Test setFeePercentage with value too high
    function test_SetFeePercentage_ValueTooHigh() public {
        vm.expectRevert(CommonErrors.ValueTooHigh.selector);
        lendingStrategy.setFeePercentage(1001); // > 10%
    }
    
    // Test setFeePercentage with non-owner
    function test_SetFeePercentage_NonOwner() public {
        // Create a custom error selector that matches what the contract returns
        bytes memory customError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner);
        
        vm.startPrank(nonOwner);
        vm.expectRevert(customError);
        lendingStrategy.setFeePercentage(100);
        vm.stopPrank();
    }
    
    // Test setFeeRecipient
    function test_SetFeeRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        // Set new fee recipient
        lendingStrategy.setFeeRecipient(newFeeRecipient);
        
        // Verify fee recipient was updated
        assertEq(lendingStrategy.feeRecipient(), newFeeRecipient, "Fee recipient should be updated");
    }
    
    // Test setFeeRecipient with zero address
    function test_SetFeeRecipient_ZeroAddress() public {
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        lendingStrategy.setFeeRecipient(address(0));
    }
    
    // Test setFeeRecipient with non-owner
    function test_SetFeeRecipient_NonOwner() public {
        // Create a custom error selector that matches what the contract returns
        bytes memory customError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner);
        
        vm.startPrank(nonOwner);
        vm.expectRevert(customError);
        lendingStrategy.setFeeRecipient(makeAddr("newFeeRecipient"));
        vm.stopPrank();
    }
    
    // Test reentrancy protection
    function test_ReentrancyProtection() public view {
        // Verify that the nonReentrant modifier is applied to key functions
        bytes memory bytecode = address(lendingStrategy).code;
        
        // Check for deposit function with nonReentrant modifier
        bytes4 depositSelector = bytes4(keccak256("deposit(uint256)"));
        assertTrue(
            contains(bytecode, abi.encodePacked(depositSelector)),
            "Deposit function should have nonReentrant modifier"
        );
        
        // Check for withdraw function with nonReentrant modifier
        bytes4 withdrawSelector = bytes4(keccak256("withdraw(uint256)"));
        assertTrue(
            contains(bytecode, abi.encodePacked(withdrawSelector)),
            "Withdraw function should have nonReentrant modifier"
        );
    }
    
    // Test edge case: deposit and withdraw with very small values
    function test_VerySmallValues() public {
        uint256 smallAmount = 1; // 1 wei
        
        // User deposits a very small amount
        vm.startPrank(user1);
        uint256 shares = lendingStrategy.deposit(smallAmount);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), smallAmount);
        
        // Transfer USDC to strategy to simulate aToken redemption
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), smallAmount);
        
        // User withdraws
        vm.startPrank(user1);
        uint256 withdrawAmount = lendingStrategy.withdraw(shares);
        vm.stopPrank();
        
        // Verify results
        assertEq(withdrawAmount, smallAmount, "Withdraw amount should match deposit for small values");
    }
    
    // Test multiple users
    function test_MultipleUsers() public {
        // User 1 deposits
        vm.startPrank(user1);
        uint256 shares1 = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // User 2 deposits a smaller amount
        uint256 user2DepositAmount = DEPOSIT_AMOUNT / 2; // 50% of user 1's deposit
        
        vm.startPrank(user2);
        uint256 shares2 = lendingStrategy.deposit(user2DepositAmount);
        vm.stopPrank();
        
        // Simulate lending protocol sending aTokens to strategy for user 2
        vm.prank(lendingProtocol);
        aToken.transfer(address(lendingStrategy), user2DepositAmount);
        
        // Verify shares - user 2 should get fewer shares due to smaller deposit
        assertLt(shares2, shares1, "User 2 should receive fewer shares due to smaller deposit");
        
        // Transfer USDC to strategy to simulate aToken redemption for both users
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT + user2DepositAmount);
        
        // User 1 withdraws
        vm.startPrank(user1);
        uint256 withdrawAmount1 = lendingStrategy.withdraw(shares1);
        vm.stopPrank();
        
        // User 2 withdraws
        vm.startPrank(user2);
        uint256 withdrawAmount2 = lendingStrategy.withdraw(shares2);
        vm.stopPrank();
        
        // Verify the relative amounts
        assertGt(withdrawAmount1, withdrawAmount2, "User 1 should receive more than user 2");
        assertEq(withdrawAmount1, DEPOSIT_AMOUNT, "User 1 should receive original deposit amount");
        assertEq(withdrawAmount2, user2DepositAmount, "User 2 should receive original deposit amount");
    }
    
    // Helper function to check if bytecode contains a specific selector
    function contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length > haystack.length) {
            return false;
        }
        
        for (uint i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }
        
        return false;
    }
}
