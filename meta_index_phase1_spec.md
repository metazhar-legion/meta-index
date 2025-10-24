# Meta Index Protocol - Phase 1 Implementation Spec
## Development Specification for Claude Code

**Version:** 1.0  
**Target:** Foundry + Solidity 0.8.24  
**Phase:** Testnet MVP  
**Timeline:** 4-6 weeks

---

## Overview

This specification breaks down Phase 1 implementation into manageable, testable modules. Each module can be developed, tested, and validated independently before integration.

**Phase 1 Goal:** Deploy a functional, single-index vault on Arbitrum Sepolia testnet with the Balanced OnChain Portfolio (BOCP) strategy.

---

## Development Phases

### Phase 1A: Core Infrastructure (Week 1-2)
- Basic vault contract (ERC-4626)
- Access control system
- Mock tokens for testing
- Initial test suite

### Phase 1B: Strategy System (Week 2-3)
- Strategy manager contract
- Base strategy implementation
- Single strategy (crypto basket)
- Integration tests

### Phase 1C: Oracle & Pricing (Week 3-4)
- Price oracle system
- Chainlink integration
- Mock price feeds for testing
- Price validation logic

### Phase 1D: Rebalancing Logic (Week 4-5)
- Rebalancing calculations
- DEX integration (Uniswap V3)
- Slippage protection
- Gas optimization

### Phase 1E: Integration & Deployment (Week 5-6)
- Full integration testing
- Testnet deployment scripts
- Documentation
- Initial frontend data hooks

---

## Project Structure

```
meta-index-protocol/
├── foundry.toml
├── .env.example
├── README.md
├── script/
│   ├── Deploy.s.sol
│   ├── SetupTestnet.s.sol
│   └── helpers/
│       └── DeployHelpers.sol
├── src/
│   ├── MetaIndexVault.sol
│   ├── StrategyManager.sol
│   ├── strategies/
│   │   ├── BaseStrategy.sol
│   │   ├── CryptoStrategy.sol
│   │   └── MockStrategy.sol
│   ├── oracle/
│   │   ├── PriceOracle.sol
│   │   └── ChainlinkAdapter.sol
│   ├── libraries/
│   │   ├── FixedPointMath.sol
│   │   └── RebalanceLib.sol
│   ├── interfaces/
│   │   ├── IMetaIndexVault.sol
│   │   ├── IStrategy.sol
│   │   ├── IStrategyManager.sol
│   │   └── IPriceOracle.sol
│   └── mocks/
│       ├── MockERC20.sol
│       ├── MockChainlinkOracle.sol
│       └── MockUniswapV3.sol
├── test/
│   ├── unit/
│   │   ├── MetaIndexVault.t.sol
│   │   ├── StrategyManager.t.sol
│   │   ├── CryptoStrategy.t.sol
│   │   └── PriceOracle.t.sol
│   ├── integration/
│   │   ├── FullFlow.t.sol
│   │   ├── Rebalancing.t.sol
│   │   └── EdgeCases.t.sol
│   ├── fork/
│   │   ├── ArbitrumFork.t.sol
│   │   └── UniswapIntegration.t.sol
│   └── helpers/
│       └── TestHelpers.sol
└── docs/
    ├── SETUP.md
    ├── TESTING.md
    └── DEPLOYMENT.md
```

---

## Phase 1A: Core Infrastructure

### Module 1A.1: MetaIndexVault.sol (Core)

**Purpose:** ERC-4626 compliant vault with basic deposit/withdraw functionality.

**File:** `src/MetaIndexVault.sol`

**Requirements:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title MetaIndexVault
 * @notice ERC-4626 vault for Meta Index Protocol
 * @dev Phase 1: Basic deposit/withdraw with strategy manager integration
 */
contract MetaIndexVault is ERC4626, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // ============ STATE VARIABLES ============
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    
    address public strategyManager;
    uint256 public tvlCap; // Phase 1: $10k cap for testing
    uint256 public minDeposit;
    
    // Fee tracking (not collected in Phase 1, just tracked)
    uint256 public managementFee; // Basis points (75 = 0.75%)
    uint256 public lastFeeTimestamp;
    
    // ============ EVENTS ============
    
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event TVLCapUpdated(uint256 oldCap, uint256 newCap);
    event StrategyManagerUpdated(address oldManager, address newManager);
    
    // ============ ERRORS ============
    
    error BelowMinimumDeposit();
    error ExceedsTVLCap();
    error ZeroAddress();
    error ZeroAmount();
    
    // ============ CONSTRUCTOR ============
    
    /**
     * @notice Initialize the vault
     * @param _asset Underlying asset (e.g., USDC)
     * @param _name Vault token name
     * @param _symbol Vault token symbol
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Phase 1 defaults
        tvlCap = 10_000e6; // $10k USDC for testing
        minDeposit = 10e6; // $10 minimum
        managementFee = 75; // 0.75%
        lastFeeTimestamp = block.timestamp;
    }
    
    // ============ DEPOSIT/WITHDRAW ============
    
    /**
     * @notice Deposit assets and receive vault shares
     * @param assets Amount of underlying to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets < minDeposit) revert BelowMinimumDeposit();
        if (totalAssets() + assets > tvlCap) revert ExceedsTVLCap();
        if (receiver == address(0)) revert ZeroAddress();
        
        // Standard ERC-4626 deposit
        shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        
        emit Deposited(receiver, assets, shares);
        
        return shares;
    }
    
    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        
        shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        
        emit Withdrawn(receiver, assets, shares);
        
        return shares;
    }
    
    // ============ ACCOUNTING ============
    
    /**
     * @notice Get total assets under management
     * @dev Phase 1: Just vault balance, no strategy calls yet
     * @return Total assets in vault
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @notice Update TVL cap
     * @param newCap New TVL cap
     */
    function updateTVLCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldCap = tvlCap;
        tvlCap = newCap;
        emit TVLCapUpdated(oldCap, newCap);
    }
    
    /**
     * @notice Set strategy manager address
     * @param _manager Strategy manager address
     */
    function setStrategyManager(address _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_manager == address(0)) revert ZeroAddress();
        address oldManager = strategyManager;
        strategyManager = _manager;
        emit StrategyManagerUpdated(oldManager, _manager);
    }
    
    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
```

**Test Requirements:**

File: `test/unit/MetaIndexVault.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MetaIndexVault} from "../../src/MetaIndexVault.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract MetaIndexVaultTest is Test {
    MetaIndexVault public vault;
    MockERC20 public usdc;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public guardian = makeAddr("guardian");
    
    uint256 constant INITIAL_BALANCE = 100_000e6; // $100k
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy vault
        vault = new MetaIndexVault(
            usdc,
            "Meta Index Balanced Portfolio",
            "miBOCP"
        );
        
        // Setup roles
        vault.grantRole(vault.GUARDIAN_ROLE(), guardian);
        
        // Fund users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
    }
    
    // ============ DEPOSIT TESTS ============
    
    function test_deposit_success() public {
        uint256 depositAmount = 1000e6; // $1000
        
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        
        uint256 shares = vault.deposit(depositAmount, alice);
        
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - depositAmount);
        vm.stopPrank();
    }
    
    function test_deposit_revertsWhenBelowMinimum() public {
        uint256 tooSmall = 5e6; // $5 (below $10 minimum)
        
        vm.startPrank(alice);
        usdc.approve(address(vault), tooSmall);
        
        vm.expectRevert(MetaIndexVault.BelowMinimumDeposit.selector);
        vault.deposit(tooSmall, alice);
        vm.stopPrank();
    }
    
    function test_deposit_revertsWhenExceedsCap() public {
        uint256 overCap = 15_000e6; // $15k (cap is $10k)
        
        vm.startPrank(alice);
        usdc.approve(address(vault), overCap);
        
        vm.expectRevert(MetaIndexVault.ExceedsTVLCap.selector);
        vault.deposit(overCap, alice);
        vm.stopPrank();
    }
    
    function test_deposit_revertsWhenPaused() public {
        vm.prank(guardian);
        vault.pause();
        
        uint256 depositAmount = 1000e6;
        
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        
        vm.expectRevert(); // Pausable: paused
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
    }
    
    // ============ WITHDRAW TESTS ============
    
    function test_withdraw_success() public {
        // First deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        
        // Then withdraw
        uint256 withdrawAmount = 500e6;
        vault.withdraw(withdrawAmount, alice, alice);
        
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - depositAmount + withdrawAmount);
        vm.stopPrank();
    }
    
    function test_withdraw_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(MetaIndexVault.ZeroAmount.selector);
        vault.withdraw(0, alice, alice);
    }
    
    // ============ SHARES/ASSETS CONVERSION ============
    
    function test_convertToShares_initialDeposit() public {
        uint256 assets = 1000e6;
        uint256 shares = vault.convertToShares(assets);
        
        // First deposit: 1:1 ratio
        assertEq(shares, assets);
    }
    
    function test_convertToAssets_afterDeposit() public {
        uint256 depositAmount = 1000e6;
        
        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, depositAmount);
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function test_updateTVLCap_success() public {
        uint256 newCap = 50_000e6;
        vault.updateTVLCap(newCap);
        
        assertEq(vault.tvlCap(), newCap);
    }
    
    function test_updateTVLCap_revertsNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.updateTVLCap(50_000e6);
    }
    
    function test_pause_success() public {
        vm.prank(guardian);
        vault.pause();
        
        assert(vault.paused());
    }
    
    function test_unpause_success() public {
        vm.prank(guardian);
        vault.pause();
        
        vault.unpause(); // Admin can unpause
        
        assert(!vault.paused());
    }
    
    // ============ FUZZ TESTS ============
    
    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, vault.minDeposit(), vault.tvlCap());
        
        vm.startPrank(alice);
        usdc.mint(alice, amount); // Ensure enough balance
        usdc.approve(address(vault), amount);
        
        uint256 shares = vault.deposit(amount, alice);
        
        assertGe(shares, 0);
        assertEq(vault.totalAssets(), amount);
        vm.stopPrank();
    }
}
```

**Acceptance Criteria:**
- [ ] All unit tests pass
- [ ] Fuzz tests run 10,000+ iterations without failure
- [ ] Gas benchmarks documented
- [ ] Deployment script works on Anvil local node

---

### Module 1A.2: MockERC20.sol

**Purpose:** Testing token for local development.

**File:** `src/mocks/MockERC20.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
```

---

### Module 1A.3: Initial Test Helpers

**File:** `test/helpers/TestHelpers.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract TestHelpers is Test {
    // Standard test addresses
    address internal constant ALICE = address(0x1);
    address internal constant BOB = address(0x2);
    address internal constant CHARLIE = address(0x3);
    
    // Standard amounts
    uint256 internal constant INITIAL_BALANCE = 100_000e6;
    uint256 internal constant DEPOSIT_AMOUNT = 1_000e6;
    
    /**
     * @notice Create and fund mock ERC20
     */
    function createMockToken(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) internal returns (MockERC20) {
        return new MockERC20(name, symbol, decimals);
    }
    
    /**
     * @notice Fund address with mock tokens
     */
    function fundAddress(
        MockERC20 token,
        address user,
        uint256 amount
    ) internal {
        token.mint(user, amount);
    }
    
    /**
     * @notice Approve and deposit to vault
     */
    function depositToVault(
        address vault,
        MockERC20 token,
        address user,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        token.approve(vault, amount);
        // Assume vault has deposit function
        (bool success,) = vault.call(
            abi.encodeWithSignature(
                "deposit(uint256,address)",
                amount,
                user
            )
        );
        require(success, "Deposit failed");
        vm.stopPrank();
    }
}
```

---

## Phase 1B: Strategy System

### Module 1B.1: IStrategy Interface

**File:** `src/interfaces/IStrategy.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IStrategy
 * @notice Interface for Meta Index strategies
 */
interface IStrategy {
    /**
     * @notice Deposit assets into strategy
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external;
    
    /**
     * @notice Withdraw assets from strategy
     * @param amount Amount to withdraw
     * @param recipient Address to receive assets
     */
    function withdraw(uint256 amount, address recipient) external;
    
    /**
     * @notice Get total value in USD (scaled by asset decimals)
     * @return Total value
     */
    function totalValue() external view returns (uint256);
    
    /**
     * @notice Get strategy name
     * @return Strategy name
     */
    function name() external view returns (string memory);
    
    /**
     * @notice Check if strategy is active
     * @return True if active
     */
    function isActive() external view returns (bool);
}
```

### Module 1B.2: BaseStrategy

**File:** `src/strategies/BaseStrategy.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/**
 * @title BaseStrategy
 * @notice Base implementation for all strategies
 */
abstract contract BaseStrategy is IStrategy {
    using SafeERC20 for IERC20;
    
    // ============ STATE VARIABLES ============
    
    address public immutable vault;
    address public immutable strategyManager;
    address public immutable asset;
    bool public isActive;
    
    // ============ MODIFIERS ============
    
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }
    
    modifier onlyManager() {
        require(msg.sender == strategyManager, "Only manager");
        _;
    }
    
    modifier whenActive() {
        require(isActive, "Strategy not active");
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    constructor(address _vault, address _manager, address _asset) {
        vault = _vault;
        strategyManager = _manager;
        asset = _asset;
        isActive = true;
    }
    
    // ============ EXTERNAL FUNCTIONS ============
    
    /**
     * @notice Deposit assets (manager only)
     */
    function deposit(uint256 amount) external virtual onlyManager whenActive {
        _deposit(amount);
    }
    
    /**
     * @notice Withdraw assets (manager only)
     */
    function withdraw(uint256 amount, address recipient)
        external
        virtual
        onlyManager
    {
        _withdraw(amount, recipient);
    }
    
    /**
     * @notice Get total value (must be implemented)
     */
    function totalValue() external view virtual returns (uint256);
    
    /**
     * @notice Get strategy name (must be implemented)
     */
    function name() external view virtual returns (string memory);
    
    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @dev Internal deposit logic (must be implemented)
     */
    function _deposit(uint256 amount) internal virtual;
    
    /**
     * @dev Internal withdraw logic (must be implemented)
     */
    function _withdraw(uint256 amount, address recipient) internal virtual;
}
```

### Module 1B.3: MockStrategy (For Testing)

**File:** `src/strategies/MockStrategy.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseStrategy} from "./BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockStrategy
 * @notice Simple strategy for testing - just holds assets
 */
contract MockStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    
    constructor(address _vault, address _manager, address _asset)
        BaseStrategy(_vault, _manager, _asset)
    {}
    
    function _deposit(uint256 amount) internal override {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }
    
    function _withdraw(uint256 amount, address recipient) internal override {
        IERC20(asset).safeTransfer(recipient, amount);
    }
    
    function totalValue() external view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
    
    function name() external pure override returns (string memory) {
        return "Mock Strategy";
    }
}
```

**Test File:** `test/unit/MockStrategy.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockStrategy} from "../../src/strategies/MockStrategy.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract MockStrategyTest is Test {
    MockStrategy public strategy;
    MockERC20 public usdc;
    
    address public vault = makeAddr("vault");
    address public manager = makeAddr("manager");
    address public user = makeAddr("user");
    
    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        strategy = new MockStrategy(vault, manager, address(usdc));
    }
    
    function test_deposit_success() public {
        uint256 amount = 1000e6;
        usdc.mint(manager, amount);
        
        vm.startPrank(manager);
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);
        vm.stopPrank();
        
        assertEq(strategy.totalValue(), amount);
    }
    
    function test_deposit_revertsNonManager() public {
        vm.prank(user);
        vm.expectRevert("Only manager");
        strategy.deposit(1000e6);
    }
    
    function test_withdraw_success() public {
        uint256 amount = 1000e6;
        usdc.mint(manager, amount);
        
        vm.startPrank(manager);
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);
        
        strategy.withdraw(amount, user);
        vm.stopPrank();
        
        assertEq(usdc.balanceOf(user), amount);
        assertEq(strategy.totalValue(), 0);
    }
}
```

---

## Development Commands

**File:** `Makefile`

```makefile
# Meta Index Protocol - Development Commands

.PHONY: help install build test test-unit test-integration test-fork deploy clean

help:
	@echo "Meta Index Protocol - Available Commands:"
	@echo "  make install          - Install dependencies"
	@echo "  make build            - Build contracts"
	@echo "  make test             - Run all tests"
	@echo "  make test-unit        - Run unit tests only"
	@echo "  make test-integration - Run integration tests"
	@echo "  make test-fork        - Run fork tests"
	@echo "  make coverage         - Generate coverage report"
	@echo "  make deploy-local     - Deploy to local Anvil"
	@echo "  make deploy-testnet   - Deploy to Arbitrum Sepolia"
	@echo "  make clean            - Clean build artifacts"

install:
	forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
	forge install foundry-rs/forge-std
	npm install --save-dev

build:
	forge build

test:
	forge test -vvv

test-unit:
	forge test --match-path "test/unit/**/*.sol" -vvv

test-integration:
	forge test --match-path "test/integration/**/*.sol" -vvv

test-fork:
	forge test --match-path "test/fork/**/*.sol" --fork-url ${ARBITRUM_RPC_URL} -vvv

coverage:
	forge coverage --report lcov
	genhtml lcov.info -o coverage

gas-report:
	forge test --gas-report

deploy-local:
	forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

deploy-testnet:
	forge script script/Deploy.s.sol --rpc-url ${ARBITRUM_SEPOLIA_RPC} --broadcast --verify

clean:
	forge clean
	rm -rf cache out
```

---

## Foundry Configuration

**File:** `foundry.toml`

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.24"
optimizer = true
optimizer_runs = 1000000
via_ir = false

# Testing
verbosity = 3
fuzz_runs = 1000
ffi = false

# Formatting
line_length = 100
tab_width = 4
bracket_spacing = false

# RPC URLs
[rpc_endpoints]
arbitrum_sepolia = "${ARBITRUM_SEPOLIA_RPC}"
arbitrum_mainnet = "${ARBITRUM_MAINNET_RPC}"

# Etherscan
[etherscan]
arbitrum_sepolia = { key = "${ARBISCAN_API_KEY}" }
arbitrum = { key = "${ARBISCAN_API_KEY}" }
```

---

## Environment Setup

**File:** `.env.example`

```bash
# RPC URLs
ARBITRUM_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
ARBITRUM_MAINNET_RPC=https://arb1.arbitrum.io/rpc

# API Keys
ARBISCAN_API_KEY=your_api_key_here

# Private Keys (NEVER commit real keys!)
DEPLOYER_PRIVATE_KEY=0x...

# Addresses
USDC_ARBITRUM_SEPOLIA=0x... # Will be deployed in Phase 1
```

---

## Next Steps Document

**File:** `docs/PHASE1_CHECKLIST.md`

```markdown
# Phase 1 Development Checklist

## Week 1-2: Core Infrastructure

### Module 1A.1: MetaIndexVault
- [ ] Create `src/MetaIndexVault.sol`
- [ ] Implement constructor
- [ ] Implement deposit function
- [ ] Implement withdraw function
- [ ] Implement totalAssets
- [ ] Add access control
- [ ] Add pause mechanism
- [ ] Create unit tests
- [ ] Run fuzz tests (1000+ runs)
- [ ] Document gas costs

### Module 1A.2: MockERC20
- [ ] Create `src/mocks/MockERC20.sol`
- [ ] Test minting
- [ ] Test burning
- [ ] Test decimals handling

### Module 1A.3: Test Helpers
- [ ] Create `test/helpers/TestHelpers.sol`
- [ ] Implement helper functions
- [ ] Test helpers work correctly

### Milestone 1A Completion Criteria
- [ ] All unit tests pass
- [ ] Gas benchmark < 150k for deposit
- [ ] Can deploy to local Anvil
- [ ] README updated with setup instructions

---

## Week 2-3: Strategy System

### Module 1B.1: Interfaces
- [ ] Create `src/interfaces/IStrategy.sol`
- [ ] Create `src/interfaces/IStrategyManager.sol`
- [ ] Document all function signatures

### Module 1B.2: BaseStrategy
- [ ] Create `src/strategies/BaseStrategy.sol`
- [ ] Implement access control
- [ ] Add safety checks
- [ ] Create unit tests

### Module 1B.3: MockStrategy
- [ ] Create `src/strategies/MockStrategy.sol`
- [ ] Test deposit/withdraw
- [ ] Test value calculation
- [ ] Integration test with vault

### Module 1B.4: StrategyManager (Basic)
- [ ] Create `src/StrategyManager.sol`
- [ ] Implement strategy registration
- [ ] Implement basic allocation
- [ ] Add tests
- [ ] Integration test with vault + strategy

### Milestone 1B Completion Criteria
- [ ] Vault can allocate to strategy
- [ ] Strategy can return funds to vault
- [ ] All integration tests pass
- [ ] Gas costs documented

---

## Week 3-4: Oracle & Pricing

### Module 1C.1: Price Oracle Interface
- [ ] Create `src/interfaces/IPriceOracle.sol`
- [ ] Define price feed structure

### Module 1C.2: MockChainlinkOracle
- [ ] Create `src/mocks/MockChainlinkOracle.sol`
- [ ] Implement price setting
- [ ] Test price retrieval

### Module 1C.3: PriceOracle
- [ ] Create `src/oracle/PriceOracle.sol`
- [ ] Implement Chainlink integration
- [ ] Add staleness checks
- [ ] Add deviation checks
- [ ] Create comprehensive tests

### Module 1C.4: Integration
- [ ] Connect PriceOracle to StrategyManager
- [ ] Test value calculations
- [ ] Test price updates

### Milestone 1C Completion Criteria
- [ ] Oracle provides reliable prices
- [ ] Staleness protection works
- [ ] All price-based calculations correct
- [ ] Fork tests against Arbitrum pass

---

## Week 4-5: Rebalancing Logic

### Module 1D.1: Rebalance Library
- [ ] Create `src/libraries/RebalanceLib.sol`
- [ ] Implement allocation calculations
- [ ] Add deviation checks
- [ ] Test edge cases

### Module 1D.2: DEX Integration
- [ ] Create mock Uniswap interface
- [ ] Implement swap logic in StrategyManager
- [ ] Add slippage protection
- [ ] Test swap execution

### Module 1D.3: Rebalancing Logic
- [ ] Add rebalance() to StrategyManager
- [ ] Implement threshold triggers
- [ ] Add gas optimization
- [ ] Comprehensive testing

### Milestone 1D Completion Criteria
- [ ] Rebalancing works end-to-end
- [ ] Slippage protection prevents bad trades
- [ ] Gas costs reasonable (<500k for rebalance)
- [ ] All edge cases tested

---

## Week 5-6: Integration & Deployment

### Module 1E.1: Full Integration Tests
- [ ] Create `test/integration/FullFlow.t.sol`
- [ ] Test complete user journey
- [ ] Test multiple users
- [ ] Test rebalancing with users
- [ ] Stress test scenarios

### Module 1E.2: Fork Tests
- [ ] Create `test/fork/ArbitrumFork.t.sol`
- [ ] Test against real Arbitrum contracts
- [ ] Test with real price feeds
- [ ] Test with real DEX

### Module 1E.3: Deployment Scripts
- [ ] Create `script/Deploy.s.sol`
- [ ] Add setup script for testnet
- [ ] Add verification script
- [ ] Test deployment on local fork

### Module 1E.4: Documentation
- [ ] Update README with architecture
- [ ] Add testing guide
- [ ] Add deployment guide
- [ ] Add troubleshooting section

### Module 1E.5: Testnet Deployment
- [ ] Deploy to Arbitrum Sepolia
- [ ] Verify contracts on Arbiscan
- [ ] Test deposits/withdrawals
- [ ] Monitor for 48 hours

### Milestone 1E Completion Criteria
- [ ] All tests pass (unit + integration + fork)
- [ ] Successfully deployed to testnet
- [ ] Contracts verified on Arbiscan
- [ ] Documentation complete
- [ ] Ready for frontend integration

---

## Post-Phase 1: Frontend Prep

### Data Hooks for Frontend
- [ ] Document all view functions
- [ ] Create ABI exports
- [ ] Document event structure
- [ ] Create sample queries
- [ ] Document contract addresses

---

## Testing Standards

### Unit Test Requirements
- Minimum 90% code coverage
- All happy paths tested
- All error cases tested
- Access control tested
- Edge cases identified and tested

### Integration Test Requirements
- Full user deposit → withdraw flow
- Multi-user scenarios
- Rebalancing with active users
- Error recovery scenarios

### Fork Test Requirements
- Test against Arbitrum mainnet fork
- Use real contract addresses
- Verify gas costs on real network
- Test price feed accuracy

---

## Gas Benchmarks (Targets)

| Operation | Target Gas | Max Acceptable |
|-----------|------------|----------------|
| Deposit (first) | 120k | 150k |
| Deposit (subsequent) | 100k | 130k |
| Withdraw | 80k | 120k |
| Rebalance | 400k | 600k |

---

## Security Checklist

- [ ] No unprotected state changes
- [ ] All external calls have reentrancy guards
- [ ] Access control on all admin functions
- [ ] Slippage protection on all swaps
- [ ] Integer overflow checks (Solidity 0.8.x)
- [ ] Zero address checks
- [ ] Zero amount checks
- [ ] Pause mechanism works
- [ ] No unbounded loops
- [ ] Events emitted for all state changes
```

---

## Deployment Script Template

**File:** `script/Deploy.s.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MetaIndexVault} from "../src/MetaIndexVault.sol";
import {StrategyManager} from "../src/StrategyManager.sol";
import {MockStrategy} from "../src/strategies/MockStrategy.sol";
import {PriceOracle} from "../src/oracle/PriceOracle.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title Deploy
 * @notice Deployment script for Meta Index Protocol Phase 1
 * @dev Usage: forge script script/Deploy.s.sol --rpc-url <RPC> --broadcast
 */
contract Deploy is Script {
    
    // Deployment addresses
    MetaIndexVault public vault;
    StrategyManager public strategyManager;
    MockStrategy public strategy;
    PriceOracle public priceOracle;
    MockERC20 public usdc; // For testnet only
    
    // Configuration
    address public deployer;
    address public guardian;
    
    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        guardian = vm.envAddress("GUARDIAN_ADDRESS");
    }
    
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        
        console2.log("Deploying Meta Index Protocol - Phase 1");
        console2.log("Deployer:", deployer);
        console2.log("Guardian:", guardian);
        
        // 1. Deploy mock USDC (testnet only)
        console2.log("\n1. Deploying Mock USDC...");
        usdc = new MockERC20("USD Coin", "USDC", 6);
        console2.log("USDC deployed at:", address(usdc));
        
        // 2. Deploy PriceOracle
        console2.log("\n2. Deploying PriceOracle...");
        priceOracle = new PriceOracle();
        console2.log("PriceOracle deployed at:", address(priceOracle));
        
        // 3. Deploy StrategyManager
        console2.log("\n3. Deploying StrategyManager...");
        strategyManager = new StrategyManager(
            address(priceOracle)
        );
        console2.log("StrategyManager deployed at:", address(strategyManager));
        
        // 4. Deploy MetaIndexVault
        console2.log("\n4. Deploying MetaIndexVault...");
        vault = new MetaIndexVault(
            usdc,
            "Meta Index Balanced Portfolio",
            "miBOCP"
        );
        console2.log("Vault deployed at:", address(vault));
        
        // 5. Deploy MockStrategy
        console2.log("\n5. Deploying MockStrategy...");
        strategy = new MockStrategy(
            address(vault),
            address(strategyManager),
            address(usdc)
        );
        console2.log("Strategy deployed at:", address(strategy));
        
        // 6. Configure connections
        console2.log("\n6. Configuring connections...");
        
        vault.setStrategyManager(address(strategyManager));
        console2.log("Vault connected to StrategyManager");
        
        strategyManager.addStrategy(address(strategy), 10000); // 100% allocation
        console2.log("Strategy added to StrategyManager");
        
        // 7. Setup roles
        console2.log("\n7. Setting up roles...");
        
        vault.grantRole(vault.GUARDIAN_ROLE(), guardian);
        console2.log("Guardian role granted to:", guardian);
        
        vault.grantRole(vault.MANAGER_ROLE(), address(strategyManager));
        console2.log("Manager role granted to StrategyManager");
        
        // 8. Summary
        console2.log("\n========================================");
        console2.log("DEPLOYMENT SUMMARY");
        console2.log("========================================");
        console2.log("USDC:            ", address(usdc));
        console2.log("PriceOracle:     ", address(priceOracle));
        console2.log("StrategyManager: ", address(strategyManager));
        console2.log("Vault:           ", address(vault));
        console2.log("Strategy:        ", address(strategy));
        console2.log("========================================");
        
        vm.stopBroadcast();
        
        // 9. Save addresses
        _saveDeploymentAddresses();
    }
    
    function _saveDeploymentAddresses() internal {
        // Save to JSON for frontend consumption
        string memory json = string.concat(
            '{\n',
            '  "vault": "', vm.toString(address(vault)), '",\n',
            '  "strategyManager": "', vm.toString(address(strategyManager)), '",\n',
            '  "priceOracle": "', vm.toString(address(priceOracle)), '",\n',
            '  "usdc": "', vm.toString(address(usdc)), '",\n',
            '  "strategy": "', vm.toString(address(strategy)), '"\n',
            '}'
        );
        
        vm.writeFile("deployments/arbitrum-sepolia.json", json);
        console2.log("\nAddresses saved to: deployments/arbitrum-sepolia.json");
    }
}
```

---

## Setup Scripts

**File:** `script/SetupTestnet.s.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MetaIndexVault} from "../src/MetaIndexVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title SetupTestnet
 * @notice Helper script to setup testnet for testing
 * @dev Mints tokens to test addresses, sets up initial state
 */
contract SetupTestnet is Script {
    
    function run() public {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        
        MockERC20 usdc = MockERC20(usdcAddress);
        MetaIndexVault vault = MetaIndexVault(vaultAddress);
        
        // Mint USDC to test addresses
        address[] memory testUsers = new address[](3);
        testUsers[0] = vm.envAddress("TEST_USER_1");
        testUsers[1] = vm.envAddress("TEST_USER_2");
        testUsers[2] = vm.envAddress("TEST_USER_3");
        
        for (uint i = 0; i < testUsers.length; i++) {
            usdc.mint(testUsers[i], 10_000e6); // $10k each
            console2.log("Minted 10,000 USDC to:", testUsers[i]);
        }
        
        // Increase TVL cap for testing
        vault.updateTVLCap(100_000e6); // $100k
        console2.log("Updated TVL cap to: 100,000 USDC");
        
        vm.stopBroadcast();
        
        console2.log("\nTestnet setup complete!");
    }
}
```

---

## README Template

**File:** `README.md`

```markdown
# Meta Index Protocol - Phase 1

> Non-custodial, DAO-governed index fund protocol bringing institutional-grade diversification to DeFi.

## Overview

Meta Index Protocol enables users to gain diversified exposure to crypto, DeFi, and tokenized real-world assets through automated, rules-based index strategies.

**Phase 1 Status:** Testnet MVP - Single index (Balanced OnChain Portfolio)

## Architecture

```
MetaIndexVault (ERC-4626)
    ↓
StrategyManager
    ↓
Strategies (Crypto, DeFi, RWA, Yield)
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/meta-index-protocol
cd meta-index-protocol

# Install dependencies
make install

# Copy environment file
cp .env.example .env

# Edit .env with your values
```

### Build

```bash
make build
```

### Test

```bash
# Run all tests
make test

# Run specific test suites
make test-unit
make test-integration
make test-fork

# Generate coverage report
make coverage
```

### Deploy

```bash
# Deploy to local Anvil node
anvil # in separate terminal
make deploy-local

# Deploy to Arbitrum Sepolia testnet
make deploy-testnet
```

## Project Structure

```
src/
├── MetaIndexVault.sol          # Main vault (ERC-4626)
├── StrategyManager.sol         # Strategy orchestration
├── strategies/
│   ├── BaseStrategy.sol        # Strategy base class
│   └── MockStrategy.sol        # Testing strategy
├── oracle/
│   └── PriceOracle.sol         # Price feed aggregation
├── interfaces/                 # Contract interfaces
├── libraries/                  # Shared libraries
└── mocks/                      # Testing mocks

test/
├── unit/                       # Unit tests
├── integration/                # Integration tests
├── fork/                       # Fork tests
└── helpers/                    # Test utilities

script/
├── Deploy.s.sol                # Deployment script
└── SetupTestnet.s.sol          # Testnet setup
```

## Phase 1 Features

✅ ERC-4626 compliant vault  
✅ Deposit/withdraw functionality  
✅ Basic strategy system  
✅ Mock strategy for testing  
✅ Access control & pause mechanism  
✅ TVL caps for phased rollout  

🚧 Price oracle integration (in progress)  
🚧 Rebalancing logic (in progress)  
🚧 DEX integration (in progress)  

## Testing

### Unit Tests

```bash
forge test --match-path "test/unit/**/*.sol" -vvv
```

### Integration Tests

```bash
forge test --match-path "test/integration/**/*.sol" -vvv
```

### Fork Tests (Arbitrum)

```bash
forge test --match-path "test/fork/**/*.sol" --fork-url $ARBITRUM_RPC_URL -vvv
```

### Gas Reports

```bash
forge test --gas-report
```

## Deployment Addresses

### Arbitrum Sepolia (Testnet)

```
Vault:           0x... (TBD)
StrategyManager: 0x... (TBD)
PriceOracle:     0x... (TBD)
```

See `deployments/arbitrum-sepolia.json` for complete addresses.

## Contributing

Phase 1 is currently in active development. We welcome:

- Bug reports
- Test improvements
- Documentation updates
- Code reviews

Please open an issue before starting work on major changes.

## Security

⚠️ **This code is unaudited and under active development. Do not use with real funds.**

Phase 1 security measures:
- Comprehensive test suite
- Access control on admin functions
- Reentrancy guards
- Pause mechanism
- TVL caps

Planned for Phase 2:
- Professional security audit
- Bug bounty program
- Gradual TVL increase
- Multi-sig controls

## License

MIT License - see LICENSE file for details

## Links

- [Litepaper](./docs/litepaper.md)
- [Technical Spec](./docs/technical-spec.md)
- [Index Methodology](./docs/index-methodology.md)
- [Discord](https://discord.gg/...) (Coming soon)
- [Twitter](https://twitter.com/...) (Coming soon)

## Support

For questions or issues:
1. Check [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)
2. Open a GitHub issue
3. Ask in Discord (coming soon)
```

---

## Additional Development Files

**File:** `.gitignore`

```
# Foundry
cache/
out/
broadcast/
deployments/*.local.json

# Node
node_modules/
.env

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Coverage
lcov.info
coverage/
```

**File:** `package.json`

```json
{
  "name": "meta-index-protocol",
  "version": "0.1.0",
  "description": "Non-custodial, DAO-governed index fund protocol",
  "scripts": {
    "test": "forge test",
    "build": "forge build",
    "deploy:local": "forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast",
    "deploy:testnet": "forge script script/Deploy.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC --broadcast --verify"
  },
  "keywords": ["defi", "index", "dao", "erc4626"],
  "author": "",
  "license": "MIT",
  "devDependencies": {
    "prettier": "^3.0.0",
    "prettier-plugin-solidity": "^1.1.0"
  }
}
```

---

## Summary for Claude Code

### Phase 1A (Weeks 1-2): Start Here

**Primary Goal:** Get basic vault working with deposit/withdraw.

**Files to create in order:**

1. `src/mocks/MockERC20.sol` (simplest, no dependencies)
2. `test/helpers/TestHelpers.sol` (testing utilities)
3. `src/MetaIndexVault.sol` (core contract)
4. `test/unit/MetaIndexVault.t.sol` (test the vault)

**Success criteria:**
- Can compile with `forge build`
- All tests pass with `forge test`
- Can deposit and withdraw USDC
- Gas benchmarks documented

**Commands to run:**
```bash
forge init meta-index-protocol
cd meta-index-protocol
# Create files per spec above
forge build
forge test -vvv
```

### Then Move to Phase 1B (Weeks 2-3)

**Focus:** Strategy system integration.

**Files to create:**
1. Interfaces first (`src/interfaces/*.sol`)
2. Base implementation (`src/strategies/BaseStrategy.sol`)
3. Mock strategy (`src/strategies/MockStrategy.sol`)
4. Strategy manager (`src/StrategyManager.sol`)
5. Tests for each

### Development Workflow

For each module:
1. ✅ Write interface/spec
2. ✅ Implement contract
3. ✅ Write tests
4. ✅ Run tests (`forge test`)
5. ✅ Check coverage (`forge coverage`)
6. ✅ Optimize gas if needed
7. ✅ Document in README
8. ✅ Move to next module

### Testing Strategy

- Write tests FIRST (TDD approach)
- Aim for 90%+ coverage
- Test happy paths AND error cases
- Use fuzz testing for inputs
- Fork test against real Arbitrum contracts

---

**This spec provides everything needed to implement Phase 1 in manageable chunks with clear milestones and acceptance criteria.**

Ready to start building! 🚀
