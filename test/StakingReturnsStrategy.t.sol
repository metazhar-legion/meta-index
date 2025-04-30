// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StakingReturnsStrategy} from "../src/StakingReturnsStrategy.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {ILiquidStaking} from "../src/interfaces/ILiquidStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

// Configurable mock for ILiquidStaking
contract ConfigurableMockLiquidStaking is ILiquidStaking {
    MockERC20 public baseAsset;
    MockERC20 public stakingToken;
    uint256 public exchangeRate = 1e6; // 1:1 initially (in 6 decimals)
    uint256 public currentAPY = 450; // 4.5%
    bool public shouldRevertStake = false;
    bool public shouldRevertUnstake = false;
    bool public reentryAttempted = false;
    address public reentryTarget;
    bool public enableReentrancy = false;

    constructor(address _baseAsset, address _stakingToken) {
        baseAsset = MockERC20(_baseAsset);
        stakingToken = MockERC20(_stakingToken);
    }

    function getTotalStaked() external view returns (uint256 totalStaked) {
        return stakingToken.totalSupply();
    }

    function stake(uint256 amount) external override returns (uint256) {
        if (shouldRevertStake) revert("Staking failed");
        baseAsset.transferFrom(msg.sender, address(this), amount);
        uint256 stakingTokenAmount = (amount * 1e6) / exchangeRate;
        stakingToken.mint(msg.sender, stakingTokenAmount);
        // Optional reentrancy
        if (enableReentrancy && reentryTarget != address(0) && !reentryAttempted) {
            reentryAttempted = true;
            StakingReturnsStrategy(reentryTarget).deposit(amount);
        }
        return stakingTokenAmount;
    }

    function unstake(uint256 stakingTokenAmount) external override returns (uint256) {
        if (shouldRevertUnstake) revert("Unstaking failed");
        stakingToken.transferFrom(msg.sender, address(this), stakingTokenAmount);
        uint256 baseAssetAmount = (stakingTokenAmount * exchangeRate) / 1e6;
        baseAsset.transfer(msg.sender, baseAssetAmount);
        // Optional reentrancy
        if (enableReentrancy && reentryTarget != address(0) && !reentryAttempted) {
            reentryAttempted = true;
            StakingReturnsStrategy(reentryTarget).withdraw(stakingTokenAmount);
        }
        return baseAssetAmount;
    }

    function getBaseAssetValue(uint256 stakingTokenAmount) external view override returns (uint256) {
        return (stakingTokenAmount * exchangeRate) / 1e6;
    }

    function getStakingTokensForBaseAsset(uint256 baseAssetAmount) external view override returns (uint256) {
        return (baseAssetAmount * 1e6) / exchangeRate;
    }

    function getCurrentAPY() external view override returns (uint256) {
        return currentAPY;
    }

    // Config functions
    function setExchangeRate(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }
    function setAPY(uint256 _apy) external {
        currentAPY = _apy;
    }
    function setShouldRevertStake(bool _shouldRevert) external {
        shouldRevertStake = _shouldRevert;
    }
    function setShouldRevertUnstake(bool _shouldRevert) external {
        shouldRevertUnstake = _shouldRevert;
    }
    function enableReentrancyAttack(address target) external {
        enableReentrancy = true;
        reentryTarget = target;
        reentryAttempted = false;
    }
    function disableReentrancyAttack() external {
        enableReentrancy = false;
        reentryTarget = address(0);
        reentryAttempted = false;
    }
}

contract StakingReturnsStrategyTest is Test {
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public stakingToken;
    ConfigurableMockLiquidStaking public liquidStaking;
    StakingReturnsStrategy public stakingStrategy;

    // Test addresses
    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;
    address public nonOwner;

    // Test amounts
    uint256 public constant INITIAL_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 public constant DEPOSIT_AMOUNT = 100_000e6; // 100k USDC
    uint256 public constant DEFAULT_APY = 450; // 4.5%
    uint256 public constant DEFAULT_RISK_LEVEL = 2; // Low risk

    function setUp() public {
        // Set up test addresses
        owner = address(this);
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        stakingToken = new MockERC20("Staking Token", "stUSDC", 6);

        // Deploy configurable mock liquid staking protocol
        liquidStaking = new ConfigurableMockLiquidStaking(address(usdc), address(stakingToken));

        // Mint initial tokens to users and protocol
        usdc.mint(user1, INITIAL_SUPPLY);
        usdc.mint(user2, INITIAL_SUPPLY);
        usdc.mint(address(liquidStaking), INITIAL_SUPPLY);
        stakingToken.mint(address(liquidStaking), INITIAL_SUPPLY);

        // We'll use the ConfigurableMockLiquidStaking implementation directly
        // instead of vm.mockCall

        // Deploy strategy
        stakingStrategy = new StakingReturnsStrategy(
            "Staking Returns",
            address(usdc),
            address(stakingToken),
            address(liquidStaking),
            feeRecipient,
            DEFAULT_APY,
            DEFAULT_RISK_LEVEL
        );
        
        // Set up mock protocol to handle deposits and withdrawals
        vm.startPrank(address(liquidStaking));
        stakingToken.approve(address(stakingStrategy), type(uint256).max);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(stakingStrategy), type(uint256).max);
        vm.stopPrank();
    }

    // --- Core Functionality Tests ---

    function test_Initialization() public {
        assertEq(stakingStrategy.name(), "Staking Returns Shares", "Strategy name should be set correctly");
        assertEq(stakingStrategy.symbol(), "sStaking Returns", "Strategy symbol should be set correctly");
        assertEq(address(stakingStrategy.baseAsset()), address(usdc), "Base asset should be set correctly");
        assertEq(address(stakingStrategy.stakingToken()), address(stakingToken), "Staking token should be set correctly");
        // Access risk level via getStrategyInfo() struct
        IYieldStrategy.StrategyInfo memory info = stakingStrategy.getStrategyInfo();
        assertEq(info.risk, DEFAULT_RISK_LEVEL, "Risk level should be set correctly");
        assertEq(stakingStrategy.getCurrentAPY(), DEFAULT_APY, "APY should be set correctly");
    }

    // --- Edge Case and Error Tests ---

    function test_Deposit_RevertOnStake() public {
        liquidStaking.setShouldRevertStake(true);
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        vm.expectRevert(bytes("Staking failed"));
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        liquidStaking.setShouldRevertStake(false);
    }

    function test_Withdraw_RevertOnUnstake() public {
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        liquidStaking.setShouldRevertUnstake(true);
        vm.expectRevert(bytes("Unstaking failed"));
        stakingStrategy.withdraw(DEPOSIT_AMOUNT);
        vm.stopPrank();
        liquidStaking.setShouldRevertUnstake(false);
    }

    function test_Deposit_ReentrancyProtection() public {
        // Enable reentrancy attack
        liquidStaking.enableReentrancyAttack(address(stakingStrategy));
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        vm.expectRevert(); // Should revert due to nonReentrant
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        liquidStaking.disableReentrancyAttack();
    }

    function test_Withdraw_ReentrancyProtection() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(stakingStrategy), DEPOSIT_AMOUNT);
        stakingStrategy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        // Enable reentrancy attack
        liquidStaking.enableReentrancyAttack(address(stakingStrategy));
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to nonReentrant
        stakingStrategy.withdraw(DEPOSIT_AMOUNT);
        vm.stopPrank();
        liquidStaking.disableReentrancyAttack();
    }
}
