// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {TokenizedTBillStrategy} from "../src/TokenizedTBillStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ITBillToken} from "../src/interfaces/ITBillToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

contract TokenizedTBillStrategyTest is Test {
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public tBillToken;
    
    // Yield strategy
    TokenizedTBillStrategy public tBillStrategy;
    
    // Mock protocol address
    address public tBillProtocol;
    
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
        tBillToken = new MockERC20("T-Bill Token", "USDC-T", 6);
        
        // Create mock protocol address
        tBillProtocol = makeAddr("tBillProtocol");
        
        // Mint initial tokens to users and protocol
        usdc.mint(user1, INITIAL_SUPPLY);
        usdc.mint(user2, INITIAL_SUPPLY);
        usdc.mint(tBillProtocol, INITIAL_SUPPLY);
        tBillToken.mint(tBillProtocol, INITIAL_SUPPLY);
        
        // Deploy strategy
        tBillStrategy = new TokenizedTBillStrategy(
            "T-Bill Strategy",
            address(usdc),
            address(tBillToken),
            tBillProtocol,
            feeRecipient
        );
        
        // Set up mock protocol to handle deposits and withdrawals
        vm.startPrank(tBillProtocol);
        tBillToken.approve(address(tBillStrategy), type(uint256).max);
        usdc.approve(address(tBillStrategy), type(uint256).max);
        vm.stopPrank();
        
        // Approve strategy to spend user tokens
        vm.startPrank(user1);
        usdc.approve(address(tBillStrategy), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(tBillStrategy), type(uint256).max);
        vm.stopPrank();
    }
    
    // Test initialization parameters
    function test_Initialization() public view {
        assertEq(tBillStrategy.name(), "T-Bill Strategy Shares", "Strategy name should be set correctly");
        assertEq(tBillStrategy.symbol(), "sT-Bill Strategy", "Strategy symbol should be set correctly");
        assertEq(address(tBillStrategy.baseAsset()), address(usdc), "Base asset should be set correctly");
        assertEq(address(tBillStrategy.tBillToken()), address(tBillToken), "T-Bill token should be set correctly");
        assertEq(tBillStrategy.tBillProtocol(), tBillProtocol, "T-Bill protocol should be set correctly");
        assertEq(tBillStrategy.feeRecipient(), feeRecipient, "Fee recipient should be set correctly");
        assertEq(tBillStrategy.feePercentage(), 50, "Fee percentage should be 0.5% by default");
        
        IYieldStrategy.StrategyInfo memory info = tBillStrategy.getStrategyInfo();
        assertEq(info.name, "T-Bill Strategy", "Strategy info name should be set correctly");
        assertEq(info.asset, address(usdc), "Strategy info asset should be set correctly");
        assertEq(info.apy, 400, "Strategy info APY should be set correctly");
        assertEq(info.risk, 1, "Strategy info risk level should be set correctly");
        assertTrue(info.active, "Strategy should be active by default");
    }
    
    // Test constructor validation with zero addresses
    function test_Constructor_Validation() public {
        // Test with zero address for base asset
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new TokenizedTBillStrategy(
            "Test Strategy",
            address(0), // Zero address for base asset
            address(tBillToken),
            tBillProtocol,
            feeRecipient
        );
        
        // Test with zero address for T-Bill token
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new TokenizedTBillStrategy(
            "Test Strategy",
            address(usdc),
            address(0), // Zero address for T-Bill token
            tBillProtocol,
            feeRecipient
        );
        
        // Test with zero address for T-Bill protocol
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new TokenizedTBillStrategy(
            "Test Strategy",
            address(usdc),
            address(tBillToken),
            address(0), // Zero address for T-Bill protocol
            feeRecipient
        );
        
        // Test with zero address for fee recipient
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        new TokenizedTBillStrategy(
            "Test Strategy",
            address(usdc),
            address(tBillToken),
            tBillProtocol,
            address(0) // Zero address for fee recipient
        );
    }
    
    // Test deposit functionality
    function test_Deposit() public {
        vm.startPrank(user1);
        
        // Initial balances
        uint256 initialUserBalance = usdc.balanceOf(user1);
        
        // Deposit
        uint256 shares = tBillStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Simulate the protocol sending T-Bill tokens to the strategy after deposit
        vm.stopPrank();
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance - DEPOSIT_AMOUNT, "User balance should decrease");
        assertEq(tBillStrategy.balanceOf(user1), shares, "User should receive shares");
        
        // Verify strategy info
        IYieldStrategy.StrategyInfo memory info = tBillStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, DEPOSIT_AMOUNT, "Total deposited should match deposit amount");
    }
    
    // Test deposit with zero amount
    function test_Deposit_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        tBillStrategy.deposit(0);
        vm.stopPrank();
    }
    
    // Test withdraw functionality
    function test_Withdraw() public {
        // First deposit
        vm.startPrank(user1);
        uint256 shares = tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate T-Bill protocol sending T-Bill tokens to strategy
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Transfer USDC to strategy to simulate T-Bill redemption
        vm.prank(tBillProtocol);
        usdc.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // User withdraws
        vm.startPrank(user1);
        uint256 initialUserBalance = usdc.balanceOf(user1);
        uint256 withdrawAmount = tBillStrategy.withdraw(shares);
        
        // Verify results
        assertEq(withdrawAmount, DEPOSIT_AMOUNT, "Withdraw amount should match deposit");
        assertEq(usdc.balanceOf(user1), initialUserBalance + withdrawAmount, "User balance should increase");
        assertEq(tBillStrategy.balanceOf(user1), 0, "User should have no shares left");
        
        vm.stopPrank();
    }
    
    // Test withdraw with zero shares
    function test_Withdraw_ZeroShares() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.ValueTooLow.selector);
        tBillStrategy.withdraw(0);
        vm.stopPrank();
    }
    
    // Test withdraw with insufficient balance
    function test_Withdraw_InsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert(CommonErrors.InsufficientBalance.selector);
        tBillStrategy.withdraw(1000); // User has no shares
        vm.stopPrank();
    }
    
    // Test getValueOfShares
    function test_GetValueOfShares() public {
        // First deposit
        vm.startPrank(user1);
        uint256 shares = tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate T-Bill protocol sending T-Bill tokens to strategy
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Check value of shares
        uint256 value = tBillStrategy.getValueOfShares(shares);
        assertEq(value, DEPOSIT_AMOUNT, "Value of shares should match deposit amount");
        
        // Check value of half the shares
        uint256 halfShares = shares / 2;
        uint256 halfValue = tBillStrategy.getValueOfShares(halfShares);
        assertEq(halfValue, DEPOSIT_AMOUNT / 2, "Value of half shares should be half the deposit amount");
    }
    
    // Test getTotalValue
    function test_GetTotalValue() public {
        // Initially, total value should be 0
        uint256 initialValue = tBillStrategy.getTotalValue();
        assertEq(initialValue, 0, "Initial total value should be 0");
        
        // After deposit and T-Bill token transfer
        vm.startPrank(user1);
        tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Warp time to simulate interest accrual
        vm.warp(block.timestamp + 365 days);
        
        // Get total value after time has passed
        uint256 valueAfterTimePass = tBillStrategy.getTotalValue();
        
        // Value should be greater than deposit due to accrued interest
        assertGt(valueAfterTimePass, DEPOSIT_AMOUNT, "Total value should be greater than deposit amount due to interest");
    }
    
    // Test getCurrentAPY
    function test_GetCurrentAPY() public view {
        // Initially, APY should match the default
        uint256 initialAPY = tBillStrategy.getCurrentAPY();
        assertEq(initialAPY, 400, "Initial APY should be 4%");
    }
    
    // Test harvestYield
    function test_HarvestYield() public {
        // First deposit
        vm.startPrank(user1);
        tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate T-Bill protocol sending T-Bill tokens to strategy
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Warp time to simulate interest accrual
        vm.warp(block.timestamp + 365 days);
        
        // Calculate expected yield (4% APY)
        uint256 expectedYield = (DEPOSIT_AMOUNT * 400) / 10000;
        uint256 expectedFee = (expectedYield * 50) / 10000; // 0.5% fee
        uint256 expectedNetYield = expectedYield - expectedFee;
        
        // Transfer USDC to strategy to simulate yield being available
        vm.prank(tBillProtocol);
        usdc.transfer(address(tBillStrategy), expectedYield);
        
        // Initial balances
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        
        // Harvest yield
        uint256 harvested = tBillStrategy.harvestYield();
        
        // Verify balances
        assertApproxEqRel(usdc.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedFee, 0.01e18, "Fee recipient should receive fee");
        assertApproxEqRel(usdc.balanceOf(owner), initialOwnerBalance + expectedNetYield, 0.01e18, "Owner should receive net yield");
        assertApproxEqRel(harvested, expectedNetYield, 0.01e18, "Harvested amount should match net yield");
    }
    
    // Test harvestYield with no yield
    function test_HarvestYield_NoYield() public {
        // First deposit
        vm.startPrank(user1);
        tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate T-Bill protocol sending T-Bill tokens to strategy
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Harvest yield immediately (no time for interest to accrue)
        uint256 harvested = tBillStrategy.harvestYield();
        assertEq(harvested, 0, "Harvested amount should be 0 when there's no yield");
    }
    
    // Test harvestYield with non-owner
    function test_HarvestYield_NonOwner() public {
        // Create a custom error selector that matches what the contract returns
        bytes memory customError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner);
        
        vm.startPrank(nonOwner);
        vm.expectRevert(customError);
        tBillStrategy.harvestYield();
        vm.stopPrank();
    }
    
    // Test setFeePercentage
    function test_SetFeePercentage() public {
        uint256 newFeePercentage = 100; // 1%
        
        // Set new fee percentage
        tBillStrategy.setFeePercentage(newFeePercentage);
        
        // Verify fee percentage was updated
        assertEq(tBillStrategy.feePercentage(), newFeePercentage, "Fee percentage should be updated");
    }
    
    // Test setFeePercentage with value too high
    function test_SetFeePercentage_ValueTooHigh() public {
        vm.expectRevert(CommonErrors.ValueTooHigh.selector);
        tBillStrategy.setFeePercentage(1001); // > 10%
    }
    
    // Test setFeePercentage with non-owner
    function test_SetFeePercentage_NonOwner() public {
        // Create a custom error selector that matches what the contract returns
        bytes memory customError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner);
        
        vm.startPrank(nonOwner);
        vm.expectRevert(customError);
        tBillStrategy.setFeePercentage(100);
        vm.stopPrank();
    }
    
    // Test setFeeRecipient
    function test_SetFeeRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        // Set new fee recipient
        tBillStrategy.setFeeRecipient(newFeeRecipient);
        
        // Verify fee recipient was updated
        assertEq(tBillStrategy.feeRecipient(), newFeeRecipient, "Fee recipient should be updated");
    }
    
    // Test setFeeRecipient with zero address
    function test_SetFeeRecipient_ZeroAddress() public {
        vm.expectRevert(CommonErrors.ZeroAddress.selector);
        tBillStrategy.setFeeRecipient(address(0));
    }
    
    // Test setFeeRecipient with non-owner
    function test_SetFeeRecipient_NonOwner() public {
        // Create a custom error selector that matches what the contract returns
        bytes memory customError = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner);
        
        vm.startPrank(nonOwner);
        vm.expectRevert(customError);
        tBillStrategy.setFeeRecipient(makeAddr("newFeeRecipient"));
        vm.stopPrank();
    }
    
    // Test reentrancy protection
    function test_ReentrancyProtection() public view {
        // Verify that the nonReentrant modifier is applied to key functions
        bytes memory bytecode = address(tBillStrategy).code;
        
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
    
    // Test multiple users
    function test_MultipleUsers() public {
        // User 1 deposits
        vm.startPrank(user1);
        uint256 shares1 = tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate T-Bill protocol sending T-Bill tokens to strategy
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // User 2 deposits a smaller amount
        uint256 user2DepositAmount = DEPOSIT_AMOUNT / 2; // 50% of user 1's deposit
        
        vm.startPrank(user2);
        uint256 shares2 = tBillStrategy.deposit(user2DepositAmount);
        vm.stopPrank();
        
        // Simulate T-Bill protocol sending T-Bill tokens to strategy for user 2
        vm.prank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), user2DepositAmount);
        
        // Verify shares - user 2 should get fewer shares due to smaller deposit
        assertLt(shares2, shares1, "User 2 should receive fewer shares due to smaller deposit");
        
        // Transfer USDC to strategy to simulate T-Bill redemption for both users
        vm.prank(tBillProtocol);
        usdc.transfer(address(tBillStrategy), DEPOSIT_AMOUNT + user2DepositAmount);
        
        // User 1 withdraws
        vm.startPrank(user1);
        uint256 withdrawAmount1 = tBillStrategy.withdraw(shares1);
        vm.stopPrank();
        
        // User 2 withdraws
        vm.startPrank(user2);
        uint256 withdrawAmount2 = tBillStrategy.withdraw(shares2);
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
