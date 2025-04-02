// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StablecoinLendingStrategy} from "../src/StablecoinLendingStrategy.sol";
import {TokenizedTBillStrategy} from "../src/TokenizedTBillStrategy.sol";
import {StakingReturnsStrategy} from "../src/StakingReturnsStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ILiquidStaking} from "../src/interfaces/ILiquidStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldStrategiesTest is Test {
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public aUsdc;
    MockERC20 public tBillToken;
    MockERC20 public stakingToken;
    
    // Yield strategies
    StablecoinLendingStrategy public lendingStrategy;
    TokenizedTBillStrategy public tBillStrategy;
    StakingReturnsStrategy public stakingStrategy;
    
    // Mock protocol addresses (will be EOAs for testing)
    address public lendingProtocol;
    address public tBillProtocol;
    address public stakingProtocol;
    
    // Test addresses
    address public owner = address(this);
    address public feeRecipient = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);
    
    // Test amounts
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant DEPOSIT_AMOUNT = 100_000e6; // 100k USDC
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        tBillToken = new MockERC20("T-Bill Token", "USDC-T", 6);
        stakingToken = new MockERC20("Staking Token", "stUSDC", 6);
        
        // Create mock protocol addresses
        lendingProtocol = makeAddr("lendingProtocol");
        tBillProtocol = makeAddr("tBillProtocol");
        stakingProtocol = makeAddr("stakingProtocol");
        
        // Mint initial tokens to users and protocols
        usdc.mint(user1, INITIAL_SUPPLY);
        usdc.mint(user2, INITIAL_SUPPLY);
        usdc.mint(lendingProtocol, INITIAL_SUPPLY);
        usdc.mint(tBillProtocol, INITIAL_SUPPLY);
        usdc.mint(stakingProtocol, INITIAL_SUPPLY);
        
        // Mint aTokens, tBill tokens, and staking tokens to protocols
        aUsdc.mint(lendingProtocol, INITIAL_SUPPLY);
        tBillToken.mint(tBillProtocol, INITIAL_SUPPLY);
        stakingToken.mint(stakingProtocol, INITIAL_SUPPLY);
        
        // Deploy strategies
        lendingStrategy = new StablecoinLendingStrategy(
            "Stablecoin Lending",
            address(usdc),
            lendingProtocol,
            address(aUsdc),
            feeRecipient
        );
        
        tBillStrategy = new TokenizedTBillStrategy(
            "Tokenized T-Bill",
            address(usdc),
            address(tBillToken),
            tBillProtocol,
            feeRecipient
        );
        
        stakingStrategy = new StakingReturnsStrategy(
            "Staking Returns",
            address(usdc),
            address(stakingToken),
            stakingProtocol,
            feeRecipient,
            450, // 4.5% initial APY
            2    // Low risk level
        );
        
        // Setup mock protocols to handle deposits and withdrawals
        // For lending protocol
        vm.startPrank(lendingProtocol);
        aUsdc.approve(address(lendingStrategy), type(uint256).max);
        usdc.approve(address(lendingStrategy), type(uint256).max);
        vm.stopPrank();
        
        // For T-Bill protocol
        vm.startPrank(tBillProtocol);
        tBillToken.approve(address(tBillStrategy), type(uint256).max);
        usdc.approve(address(tBillStrategy), type(uint256).max);
        vm.stopPrank();
        
        // For staking protocol
        vm.startPrank(stakingProtocol);
        stakingToken.approve(address(stakingStrategy), type(uint256).max);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();
        
        // Approve strategies to spend user tokens
        vm.startPrank(user1);
        usdc.approve(address(lendingStrategy), type(uint256).max);
        usdc.approve(address(tBillStrategy), type(uint256).max);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(lendingStrategy), type(uint256).max);
        usdc.approve(address(tBillStrategy), type(uint256).max);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();
        
        // Set up hooks for deposit and withdrawal
        vm.mockCall(
            lendingProtocol,
            abi.encodeWithSignature("deposit(address,uint256,address,uint16)", address(usdc), 0, address(0), 0),
            abi.encode(true)
        );
        
        vm.mockCall(
            tBillProtocol,
            abi.encodeWithSignature("deposit(uint256)", 0),
            abi.encode(0)
        );
        
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("stake(uint256)", 0),
            abi.encode(0)
        );
        
        // Mock the new ILiquidStaking methods with more specific values
        // Mock getBaseAssetValue for any input amount
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("getBaseAssetValue(uint256)", DEPOSIT_AMOUNT),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Mock getStakingTokensForBaseAsset for any input amount
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("getStakingTokensForBaseAsset(uint256)", DEPOSIT_AMOUNT),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Mock getCurrentAPY
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("getCurrentAPY()"),
            abi.encode(450) // 4.5% APY
        );
        
        // Mock unstake for any input amount
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("unstake(uint256)", DEPOSIT_AMOUNT),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Add wildcard mocks for any amount
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("getBaseAssetValue(uint256)", uint256(0)),
            abi.encode(uint256(0))
        );
        
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("getStakingTokensForBaseAsset(uint256)", uint256(0)),
            abi.encode(uint256(0))
        );
        
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("unstake(uint256)", uint256(0)),
            abi.encode(uint256(0))
        );
    }
    
    function testLendingStrategyDeposit() public {
        vm.startPrank(user1);
        
        // Initial balances
        uint256 initialUserBalance = usdc.balanceOf(user1);
        // We'll verify the user balance change, no need to track strategy balance
        
        // Deposit
        uint256 shares = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance - DEPOSIT_AMOUNT, "User balance should decrease");
        assertEq(lendingStrategy.balanceOf(user1), shares, "User should receive shares");
        
        // Verify strategy info
        IYieldStrategy.StrategyInfo memory info = lendingStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, DEPOSIT_AMOUNT, "Total deposited should match deposit amount");
        
        vm.stopPrank();
    }
    
    function testTBillStrategyDeposit() public {
        vm.startPrank(user1);
        
        // Initial balances
        uint256 initialUserBalance = usdc.balanceOf(user1);
        // We'll verify the user balance change, no need to track strategy balance
        
        // Deposit
        uint256 shares = tBillStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance - DEPOSIT_AMOUNT, "User balance should decrease");
        assertEq(tBillStrategy.balanceOf(user1), shares, "User should receive shares");
        
        // Verify strategy info
        IYieldStrategy.StrategyInfo memory info = tBillStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, DEPOSIT_AMOUNT, "Total deposited should match deposit amount");
        
        vm.stopPrank();
    }
    
    function testStakingStrategyDeposit() public {
        vm.startPrank(user1);
        
        // Initial balances
        uint256 initialUserBalance = usdc.balanceOf(user1);
        
        // Mock the stake function to simulate successful staking
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("stake(uint256)", DEPOSIT_AMOUNT),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Simulate the protocol sending staking tokens to the strategy after staking
        vm.stopPrank();
        vm.prank(stakingProtocol);
        stakingToken.transfer(address(stakingStrategy), DEPOSIT_AMOUNT);
        vm.startPrank(user1);
        
        // Deposit
        uint256 shares = stakingStrategy.deposit(DEPOSIT_AMOUNT);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance - DEPOSIT_AMOUNT, "User balance should decrease");
        assertEq(stakingStrategy.balanceOf(user1), shares, "User should receive shares");
        
        // Verify strategy info
        IYieldStrategy.StrategyInfo memory info = stakingStrategy.getStrategyInfo();
        assertEq(info.totalDeposited, DEPOSIT_AMOUNT, "Total deposited should match deposit amount");
        
        vm.stopPrank();
    }
    
    function testLendingStrategyWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        uint256 shares = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate the protocol sending aTokens to the strategy
        vm.startPrank(lendingProtocol);
        aUsdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Simulate yield generation by transferring additional aTokens to the strategy
        uint256 yieldAmount = DEPOSIT_AMOUNT / 10; // 10% yield
        aUsdc.transfer(address(lendingStrategy), yieldAmount);
        vm.stopPrank();
        
        // Now withdraw
        // First, ensure the protocol has enough USDC to send back during withdrawal
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT + yieldAmount);
        
        vm.startPrank(user1);
        uint256 initialUserBalance = usdc.balanceOf(user1);
        uint256 withdrawAmount = lendingStrategy.withdraw(shares);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance + withdrawAmount, "User balance should increase");
        assertEq(lendingStrategy.balanceOf(user1), 0, "User should have no shares left");
        
        vm.stopPrank();
    }
    
    function testTBillStrategyWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        uint256 shares = tBillStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate the protocol sending T-Bill tokens to the strategy
        vm.startPrank(tBillProtocol);
        tBillToken.transfer(address(tBillStrategy), DEPOSIT_AMOUNT);
        
        // Simulate yield generation by transferring additional T-Bill tokens to the strategy
        uint256 yieldAmount = DEPOSIT_AMOUNT / 25; // 4% yield
        tBillToken.transfer(address(tBillStrategy), yieldAmount);
        vm.stopPrank();
        
        // Now withdraw
        // First, ensure the protocol has enough USDC to send back during withdrawal
        vm.prank(tBillProtocol);
        usdc.transfer(address(tBillStrategy), DEPOSIT_AMOUNT + yieldAmount);
        
        vm.startPrank(user1);
        uint256 initialUserBalance = usdc.balanceOf(user1);
        uint256 withdrawAmount = tBillStrategy.withdraw(shares);
        
        // Verify balances
        assertEq(usdc.balanceOf(user1), initialUserBalance + withdrawAmount, "User balance should increase");
        assertEq(tBillStrategy.balanceOf(user1), 0, "User should have no shares left");
        
        vm.stopPrank();
    }
    
    function testStakingStrategyWithdraw() public {
        console.log("Starting testStakingStrategyWithdraw");
        
        // Setup: Mint tokens to user and protocols
        usdc.mint(user1, DEPOSIT_AMOUNT);
        stakingToken.mint(stakingProtocol, DEPOSIT_AMOUNT * 2); // Extra for simulating yield
        usdc.mint(stakingProtocol, DEPOSIT_AMOUNT * 2); // Extra for withdrawal
        
        console.log("Initial USDC balance of user1:", usdc.balanceOf(user1));
        console.log("Initial staking token balance of protocol:", stakingToken.balanceOf(stakingProtocol));
        
        // Step 1: Mock all necessary calls for deposit and withdrawal
        console.log("Setting up mock calls");
        
        // For deposit
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSignature("stake(uint256)", DEPOSIT_AMOUNT),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // For withdrawal - use more specific mocks to control the test flow
        
        // Mock getBaseAssetValue to return DEPOSIT_AMOUNT for any staking token amount
        // This ensures that getTotalValue() returns a predictable value
        bytes4 getBaseAssetValueSelector = bytes4(keccak256("getBaseAssetValue(uint256)"));
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSelector(getBaseAssetValueSelector),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Mock getStakingTokensForBaseAsset to return DEPOSIT_AMOUNT for any base asset amount
        // This ensures that _withdrawFromStakingProtocol uses a predictable amount of staking tokens
        bytes4 getStakingTokensSelector = bytes4(keccak256("getStakingTokensForBaseAsset(uint256)"));
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSelector(getStakingTokensSelector),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Mock unstake to return DEPOSIT_AMOUNT for any staking token amount
        bytes4 unstakeSelector = bytes4(keccak256("unstake(uint256)"));
        vm.mockCall(
            stakingProtocol,
            abi.encodeWithSelector(unstakeSelector),
            abi.encode(DEPOSIT_AMOUNT)
        );
        
        // Step 2: User deposits
        console.log("User depositing");
        vm.startPrank(user1);
        uint256 shares = stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        console.log("Deposit complete, shares received:", shares);
        
        // Step 3: Simulate staking protocol sending staking tokens to strategy
        console.log("Simulating staking token transfer to strategy");
        vm.prank(stakingProtocol);
        stakingToken.transfer(address(stakingStrategy), DEPOSIT_AMOUNT);
        console.log("Staking token balance of strategy:", stakingToken.balanceOf(address(stakingStrategy)));
        
        // Step 4: Transfer USDC to strategy to simulate unstaking
        console.log("Transferring USDC to strategy to simulate unstaking");
        vm.prank(stakingProtocol);
        // Transfer 3x the deposit amount to cover the withdrawal calculation in the contract
        usdc.transfer(address(stakingStrategy), DEPOSIT_AMOUNT * 3);
        console.log("USDC balance of strategy:", usdc.balanceOf(address(stakingStrategy)));
        
        // Step 5: User withdraws
        console.log("User withdrawing");
        vm.startPrank(user1);
        uint256 initialUserBalance = usdc.balanceOf(user1);
        console.log("Initial user balance before withdrawal:", initialUserBalance);
        
        // Add a try-catch to see where it fails
        try stakingStrategy.withdraw(shares) returns (uint256 withdrawAmount) {
            console.log("Withdrawal successful, amount:", withdrawAmount);
            
            // Step 6: Verify results
            assertEq(withdrawAmount, DEPOSIT_AMOUNT, "Withdraw amount should match deposit");
            assertEq(usdc.balanceOf(user1), initialUserBalance + withdrawAmount, "User balance should increase");
            assertEq(stakingStrategy.balanceOf(user1), 0, "User should have no shares left");
        } catch Error(string memory reason) {
            console.log("Withdrawal failed with reason:", reason);
            // Use assert to fail the test with the reason
            assertTrue(false, reason);
        } catch (bytes memory) {
            console.log("Withdrawal failed with unknown error");
            // Use assert to fail the test
            assertTrue(false, "Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function testHarvestYield() public {
        // First deposit
        vm.startPrank(user1);
        lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate the protocol sending aTokens to the strategy
        vm.startPrank(lendingProtocol);
        aUsdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Simulate yield generation by transferring additional aTokens to the strategy
        uint256 yieldAmount = DEPOSIT_AMOUNT / 10; // 10% yield
        aUsdc.transfer(address(lendingStrategy), yieldAmount);
        vm.stopPrank();
        
        // Ensure the protocol has enough USDC to send back during yield harvesting
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), yieldAmount);
        
        // Initial balances
        uint256 initialFeeRecipientBalance = usdc.balanceOf(feeRecipient);
        uint256 initialOwnerBalance = usdc.balanceOf(owner);
        
        // Harvest yield
        uint256 harvested = lendingStrategy.harvestYield();
        
        // Verify balances
        uint256 expectedFee = (yieldAmount * 50) / 10000; // 0.5% fee
        uint256 expectedNetYield = yieldAmount - expectedFee;
        
        assertEq(usdc.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedFee, "Fee recipient should receive fee");
        assertEq(usdc.balanceOf(owner), initialOwnerBalance + expectedNetYield, "Owner should receive net yield");
        assertEq(harvested, expectedNetYield, "Harvested amount should match net yield");
    }
    
    function testMultipleUsersDeposit() public {
        // User 1 deposits
        vm.startPrank(user1);
        uint256 shares1 = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate the protocol sending aTokens to the strategy for user 1's deposit
        vm.startPrank(lendingProtocol);
        aUsdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Simulate some yield
        uint256 yieldAmount = DEPOSIT_AMOUNT / 20; // 5% yield
        aUsdc.transfer(address(lendingStrategy), yieldAmount);
        vm.stopPrank();
        
        // User 2 deposits
        vm.startPrank(user2);
        uint256 shares2 = lendingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Simulate the protocol sending aTokens to the strategy for user 2's deposit
        vm.prank(lendingProtocol);
        aUsdc.transfer(address(lendingStrategy), DEPOSIT_AMOUNT);
        
        // Verify shares - user 2 should get fewer shares due to yield accrual
        assertGt(shares1, shares2, "User 2 should receive fewer shares due to yield accrual");
        
        // Ensure the protocol has enough USDC to send back during withdrawals
        vm.prank(lendingProtocol);
        usdc.transfer(address(lendingStrategy), 2 * DEPOSIT_AMOUNT + yieldAmount);
        
        // Both users withdraw
        vm.startPrank(user1);
        uint256 withdrawAmount1 = lendingStrategy.withdraw(shares1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 withdrawAmount2 = lendingStrategy.withdraw(shares2);
        vm.stopPrank();
        
        // Verify withdraw amounts
        assertGt(withdrawAmount1, DEPOSIT_AMOUNT, "User 1 should receive original deposit plus yield");
        assertEq(withdrawAmount2, DEPOSIT_AMOUNT, "User 2 should receive original deposit");
    }
}
