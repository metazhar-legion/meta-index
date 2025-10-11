# Meta Index Protocol
## Technical Specification Document

**Version 1.0 | October 2025**  
**Status:** Draft - Pre-Audit

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Smart Contract Specifications](#smart-contract-specifications)
3. [Security Model](#security-model)
4. [Integration Patterns](#integration-patterns)
5. [Gas Optimization Strategies](#gas-optimization-strategies)
6. [Oracle & Price Feed Architecture](#oracle--price-feed-architecture)
7. [Upgrade Mechanisms](#upgrade-mechanisms)
8. [Testing & Deployment](#testing--deployment)

---

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Governance Layer                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ GovernorDAO  │  │   Timelock   │  │ MultiSig     │       │
│  │   Contract   │─▶│   Contract   │  │  Emergency   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                     Core Protocol Layer                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Registry   │  │   Whitelist  │  │    Router    │       │
│  │   Contract   │  │   Contract   │  │   Contract   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Vault Layer (ERC-4626)                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  Balanced    │  │    DeFi      │  │  Real Yield  │       │
│  │    Vault     │  │  Innovation  │  │    Vault     │       │
│  │              │  │    Vault     │  │              │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Strategy Layer                           │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ Crypto  │  │  DeFi   │  │   RWA   │  │  Yield  │         │
│  │Strategy │  │Strategy │  │Strategy │  │Strategy │         │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Integration Layer                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │  DEX    │  │  Oracle │  │ Lending │  │   RWA   │         │
│  │Aggreg.  │  │  Feeds  │  │Protocols│  │ Tokens  │         │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

**User Deposit Flow:**
```
1. User approves USDC/ETH to Vault
2. Vault.deposit(amount) called
3. Vault queries StrategyManager for current allocations
4. Vault converts deposit to proportional asset purchases
5. StrategyManager executes swaps via DEX aggregator
6. Assets distributed to Strategy contracts
7. ERC-4626 shares minted to user
8. Event emitted for indexing
```

**Rebalancing Flow:**
```
1. Keeper calls Vault.rebalance() (permissionless)
2. StrategyManager calculates current vs. target allocations
3. Determines required swaps to reach targets
4. Executes trades via optimal routing
5. Updates internal accounting
6. Emits RebalanceComplete event
```

---

## Smart Contract Specifications

### 1. MetaIndexVault.sol (ERC-4626)

**Purpose:** Core vault contract implementing ERC-4626 standard for tokenized vault shares.

**Key Functions:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract MetaIndexVault is ERC4626, AccessControl, ReentrancyGuard, Pausable {
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    
    IStrategyManager public strategyManager;
    IFeeCollector public feeCollector;
    
    uint256 public managementFee; // 75 basis points (0.75%)
    uint256 public performanceFee; // 1000 basis points (10%)
    uint256 public lastFeeCollection;
    
    uint256 public tvlCap; // Phased rollout cap
    uint256 public minDeposit; // Minimum deposit amount
    
    // Events
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event Rebalanced(uint256 timestamp, uint256 gasUsed);
    event FeesCollected(uint256 managementFees, uint256 performanceFees);
    event TVLCapUpdated(uint256 oldCap, uint256 newCap);
    
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _strategyManager,
        address _feeCollector
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        strategyManager = IStrategyManager(_strategyManager);
        feeCollector = IFeeCollector(_feeCollector);
        
        managementFee = 75; // 0.75%
        performanceFee = 1000; // 10%
        lastFeeCollection = block.timestamp;
        
        tvlCap = 1_000_000e6; // $1M initial cap
        minDeposit = 100e6; // $100 minimum
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, _strategyManager);
    }
    
    /**
     * @notice Deposit assets and receive vault shares
     * @param assets Amount of underlying asset to deposit
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
        require(assets >= minDeposit, "Below minimum deposit");
        require(totalAssets() + assets <= tvlCap, "Exceeds TVL cap");
        
        shares = super.deposit(assets, receiver);
        
        // Allocate assets according to strategy
        strategyManager.allocateDeposit(assets);
        
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
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Calculate proportional share of each underlying asset
        shares = previewWithdraw(assets);
        
        // Withdraw from strategies proportionally
        strategyManager.withdrawAssets(assets, receiver);
        
        shares = super.withdraw(assets, receiver, owner);
        
        emit Withdrawn(receiver, assets, shares);
        return shares;
    }
    
    /**
     * @notice Execute rebalancing to target allocations
     * @dev Permissionless, can be called by anyone (keepers)
     */
    function rebalance() external nonReentrant whenNotPaused {
        uint256 gasStart = gasleft();
        
        // Collect management fees before rebalancing
        _collectManagementFees();
        
        // Execute rebalancing via strategy manager
        strategyManager.rebalance();
        
        uint256 gasUsed = gasStart - gasleft();
        emit Rebalanced(block.timestamp, gasUsed);
    }
    
    /**
     * @notice Calculate total assets under management
     * @return Total value of all assets in vault
     */
    function totalAssets() public view override returns (uint256) {
        return strategyManager.getTotalValue();
    }
    
    /**
     * @dev Collect management fees (called automatically during rebalance)
     */
    function _collectManagementFees() internal {
        uint256 timeSinceLastCollection = block.timestamp - lastFeeCollection;
        if (timeSinceLastCollection == 0) return;
        
        uint256 annualFee = (totalAssets() * managementFee) / 10000;
        uint256 feeAmount = (annualFee * timeSinceLastCollection) / 365 days;
        
        if (feeAmount > 0) {
            // Mint shares to fee collector
            uint256 sharesFee = convertToShares(feeAmount);
            _mint(address(feeCollector), sharesFee);
            
            lastFeeCollection = block.timestamp;
            emit FeesCollected(feeAmount, 0);
        }
    }
    
    /**
     * @notice Emergency pause (guardian only)
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause (admin only)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Update TVL cap (governance)
     */
    function updateTVLCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldCap = tvlCap;
        tvlCap = newCap;
        emit TVLCapUpdated(oldCap, newCap);
    }
}
```

**State Variables:**
- `strategyManager`: Address of strategy execution contract
- `managementFee`: Annual fee in basis points (75 = 0.75%)
- `performanceFee`: Performance fee percentage (1000 = 10%)
- `tvlCap`: Maximum total value locked (phased rollout)
- `minDeposit`: Minimum deposit amount

**Access Control:**
- `DEFAULT_ADMIN_ROLE`: DAO/Timelock (parameter changes)
- `MANAGER_ROLE`: Strategy manager (execution)
- `GUARDIAN_ROLE`: Multi-sig (emergency pause)

---

### 2. StrategyManager.sol

**Purpose:** Orchestrates allocation across multiple strategies based on index methodology.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IStrategy.sol";
import "./interfaces/IRegistry.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract StrategyManager is AccessControl {
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    
    IRegistry public registry;
    IIndexMethodology public methodology;
    
    // Strategy tracking
    address[] public activeStrategies;
    mapping(address => bool) public isActiveStrategy;
    mapping(address => uint256) public strategyAllocations; // Basis points
    
    // Rebalancing parameters
    uint256 public rebalanceThreshold; // 100 = 1% deviation triggers rebalance
    uint256 public lastRebalance;
    uint256 public rebalanceInterval; // Minimum time between rebalances
    
    // Slippage protection
    uint256 public maxSlippage; // 50 = 0.5% max slippage
    
    event StrategyAdded(address indexed strategy, uint256 allocation);
    event StrategyRemoved(address indexed strategy);
    event AllocationUpdated(address indexed strategy, uint256 newAllocation);
    event RebalanceExecuted(uint256 timestamp, address[] strategies);
    
    constructor(address _registry, address _methodology) {
        registry = IRegistry(_registry);
        methodology = IIndexMethodology(_methodology);
        
        rebalanceThreshold = 100; // 1%
        rebalanceInterval = 1 days;
        maxSlippage = 50; // 0.5%
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Add a new strategy with target allocation
     * @param strategy Address of strategy contract
     * @param allocation Target allocation in basis points (100 = 1%)
     */
    function addStrategy(address strategy, uint256 allocation) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(!isActiveStrategy[strategy], "Strategy already active");
        require(allocation > 0, "Allocation must be > 0");
        require(_totalAllocations() + allocation <= 10000, "Total allocation exceeds 100%");
        
        activeStrategies.push(strategy);
        isActiveStrategy[strategy] = true;
        strategyAllocations[strategy] = allocation;
        
        emit StrategyAdded(strategy, allocation);
    }
    
    /**
     * @notice Allocate deposited funds across strategies
     * @param totalAmount Total amount to allocate
     */
    function allocateDeposit(uint256 totalAmount) 
        external 
        onlyRole(VAULT_ROLE) 
    {
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            uint256 allocation = strategyAllocations[strategy];
            uint256 amount = (totalAmount * allocation) / 10000;
            
            if (amount > 0) {
                IStrategy(strategy).deposit(amount);
            }
        }
    }
    
    /**
     * @notice Execute rebalancing to target allocations
     */
    function rebalance() external onlyRole(REBALANCER_ROLE) {
        require(
            block.timestamp >= lastRebalance + rebalanceInterval,
            "Rebalance interval not met"
        );
        
        // Get current allocations
        uint256 totalValue = getTotalValue();
        uint256[] memory currentValues = new uint256[](activeStrategies.length);
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            currentValues[i] = IStrategy(activeStrategies[i]).totalValue();
        }
        
        // Check if rebalance needed
        if (!_needsRebalance(currentValues, totalValue)) {
            return;
        }
        
        // Calculate required swaps
        (
            address[] memory fromStrategies,
            address[] memory toStrategies,
            uint256[] memory amounts
        ) = _calculateRebalanceSwaps(currentValues, totalValue);
        
        // Execute swaps
        _executeSwaps(fromStrategies, toStrategies, amounts);
        
        lastRebalance = block.timestamp;
        emit RebalanceExecuted(block.timestamp, activeStrategies);
    }
    
    /**
     * @notice Get total value across all strategies
     * @return Total USD value (scaled by asset decimals)
     */
    function getTotalValue() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            total += IStrategy(activeStrategies[i]).totalValue();
        }
        return total;
    }
    
    /**
     * @dev Check if rebalancing is needed based on threshold
     */
    function _needsRebalance(uint256[] memory currentValues, uint256 totalValue) 
        internal 
        view 
        returns (bool) 
    {
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            uint256 currentAllocation = (currentValues[i] * 10000) / totalValue;
            uint256 targetAllocation = strategyAllocations[activeStrategies[i]];
            
            uint256 deviation = currentAllocation > targetAllocation
                ? currentAllocation - targetAllocation
                : targetAllocation - currentAllocation;
            
            if (deviation >= rebalanceThreshold) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Calculate optimal swaps for rebalancing
     */
    function _calculateRebalanceSwaps(
        uint256[] memory currentValues,
        uint256 totalValue
    ) internal view returns (
        address[] memory fromStrategies,
        address[] memory toStrategies,
        uint256[] memory amounts
    ) {
        // Implementation: Calculate minimal set of swaps
        // to reach target allocations efficiently
        // This is a complex optimization problem
        // Use greedy algorithm or linear programming approach
    }
    
    /**
     * @dev Execute calculated swaps via DEX aggregator
     */
    function _executeSwaps(
        address[] memory fromStrategies,
        address[] memory toStrategies,
        uint256[] memory amounts
    ) internal {
        // Implementation: Execute swaps through optimal routing
        // Use DEX aggregator for best prices
        // Apply slippage protection
    }
    
    function _totalAllocations() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            total += strategyAllocations[activeStrategies[i]];
        }
        return total;
    }
}
```

---

### 3. Strategy Contracts (Base Implementation)

**Purpose:** Individual strategy contracts for each asset category.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BaseStrategy is IStrategy {
    
    address public vault;
    address public strategyManager;
    
    modifier onlyManager() {
        require(msg.sender == strategyManager, "Only manager");
        _;
    }
    
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }
    
    /**
     * @notice Deposit funds into strategy
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external virtual onlyManager {
        _deposit(amount);
    }
    
    /**
     * @notice Withdraw funds from strategy
     * @param amount Amount to withdraw
     * @param recipient Address to receive funds
     */
    function withdraw(uint256 amount, address recipient) 
        external 
        virtual 
        onlyManager 
    {
        _withdraw(amount, recipient);
    }
    
    /**
     * @notice Get total value in strategy
     * @return Value in USD (scaled)
     */
    function totalValue() external view virtual returns (uint256);
    
    /**
     * @dev Internal deposit implementation (strategy-specific)
     */
    function _deposit(uint256 amount) internal virtual;
    
    /**
     * @dev Internal withdraw implementation (strategy-specific)
     */
    function _withdraw(uint256 amount, address recipient) internal virtual;
}
```

**Concrete Implementations:**

**CryptoStrategy.sol** - Holds BTC, ETH, major crypto assets
**DeFiStrategy.sol** - Holds UNI, AAVE, LINK, protocol tokens
**RWAStrategy.sol** - Holds BUIDL, OUSG, tokenized securities
**YieldStrategy.sol** - Holds stETH, aUSDC, yield positions

---

### 4. AssetWhitelist.sol

**Purpose:** Governance-controlled whitelist of approved assets.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AssetWhitelist {
    
    enum RiskTier { 
        Tier1,      // Auto-approved (Treasuries, stablecoins)
        Tier2,      // Standard review (Private credit, corp bonds)
        Tier3,      // Enhanced review (Equities, REITs)
        Prohibited  // Not allowed
    }
    
    struct AssetInfo {
        address token;
        RiskTier tier;
        bool hasTransferRestrictions;
        bool requiresKYC;
        address issuer;
        uint256 approvedTimestamp;
        string metadata; // IPFS hash with details
    }
    
    mapping(address => AssetInfo) public whitelistedAssets;
    mapping(address => bool) public isWhitelisted;
    
    event AssetProposed(address indexed token, RiskTier tier);
    event AssetApproved(address indexed token, uint256 timestamp);
    event AssetRemoved(address indexed token);
    
    /**
     * @notice Propose new asset for whitelist (governance)
     */
    function proposeAsset(
        address token,
        RiskTier tier,
        bool hasRestrictions,
        bool requiresKYC,
        address issuer,
        string calldata metadata
    ) external onlyGovernance returns (uint256 proposalId) {
        // Create governance proposal
        // Return proposal ID for voting
    }
    
    /**
     * @notice Check if asset is approved and meets criteria
     */
    function canInclude(address token) external view returns (bool) {
        return isWhitelisted[token];
    }
    
    /**
     * @notice Get detailed asset information
     */
    function getAssetInfo(address token) 
        external 
        view 
        returns (AssetInfo memory) 
    {
        return whitelistedAssets[token];
    }
}
```

---

### 5. Oracle Integration

**Purpose:** Secure, manipulation-resistant price feeds.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    
    struct PriceFeed {
        address chainlinkFeed;
        address backupFeed;
        uint256 heartbeat; // Max time between updates
        uint256 deviationThreshold; // Max % deviation between feeds
    }
    
    mapping(address => PriceFeed) public priceFeeds;
    
    /**
     * @notice Get price with validation
     * @param token Token address
     * @return price Price in USD (8 decimals)
     */
    function getPrice(address token) external view returns (uint256 price) {
        PriceFeed memory feed = priceFeeds[token];
        
        // Get primary price
        (uint256 primaryPrice, uint256 primaryTimestamp) = 
            _getChainlinkPrice(feed.chainlinkFeed);
        
        // Validate freshness
        require(
            block.timestamp - primaryTimestamp <= feed.heartbeat,
            "Stale price"
        );
        
        // Get backup price for comparison
        if (feed.backupFeed != address(0)) {
            (uint256 backupPrice,) = _getChainlinkPrice(feed.backupFeed);
            
            // Check deviation
            uint256 deviation = _calculateDeviation(primaryPrice, backupPrice);
            require(
                deviation <= feed.deviationThreshold,
                "Price deviation too high"
            );
        }
        
        return primaryPrice;
    }
    
    function _getChainlinkPrice(address feed) 
        internal 
        view 
        returns (uint256 price, uint256 timestamp) 
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        require(answeredInRound >= roundId, "Stale price");
        require(answer > 0, "Invalid price");
        
        return (uint256(answer), updatedAt);
    }
    
    function _calculateDeviation(uint256 price1, uint256 price2) 
        internal 
        pure 
        returns (uint256) 
    {
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        return (diff * 10000) / price1; // Return basis points
    }
}
```

---

## Security Model

### Multi-Layered Security Architecture

**Layer 1: Access Control**
```
┌─────────────────────────────────────┐
│         Role Hierarchy              │
├─────────────────────────────────────┤
│ DEFAULT_ADMIN (DAO/Timelock)        │ ← Parameter changes
│   ├─ MANAGER_ROLE                   │ ← Strategy execution
│   ├─ GUARDIAN_ROLE (MultiSig)       │ ← Emergency pause
│   └─ REBALANCER_ROLE (Keepers)      │ ← Rebalance calls
└─────────────────────────────────────┘
```

**Layer 2: Economic Security**
- Management fees aligned with long-term success
- Performance fees only on positive returns
- Slippage protection on all swaps
- TVL caps during early phases

**Layer 3: Technical Security**
- ReentrancyGuard on all state-changing functions
- Pausable emergency circuit breaker
- Timelock on governance changes (48 hours)
- Oracle manipulation protection

**Layer 4: Operational Security**
- Multi-signature requirement for critical operations
- Gradual rollout with monitoring
- Bug bounty program
- Continuous monitoring and alerting

### Attack Vectors & Mitigations

**1. Flash Loan Attacks**
- **Risk:** Manipulate asset prices during rebalancing
- **Mitigation:** 
  - TWAP (Time-Weighted Average Price) oracles
  - Minimum time between price updates
  - Deviation circuit breakers
  - Slippage limits on swaps

**2. Oracle Manipulation**
- **Risk:** Feed false prices to extract value
- **Mitigation:**
  - Multiple oracle sources
  - Cross-validation between feeds
  - Heartbeat checks
  - Manual fallback for extreme deviations

**3. Governance Attacks**
- **Risk:** Malicious proposal execution
- **Mitigation:**
  - 48-hour timelock on changes
  - High quorum requirements
  - Guardian multisig can veto
  - Gradual token distribution

**4. Front-Running**
- **Risk:** MEV extraction during rebalances
- **Mitigation:**
  - Batch transactions
  - Private mempools (Flashbots)
  - Slippage protection
  - MEV-aware routing

**5. RWA Token Restrictions**
- **Risk:** Transfer failures halt operations
- **Mitigation:**
  - Try/catch on all RWA transfers
  - Graceful degradation
  - Alternative allocation paths
  - Per-asset pause capability

### Emergency Procedures

**Level 1: Asset-Specific Issue**
```solidity
function pauseAsset(address token) external onlyGuardian {
    assetStatus[token] = Status.Paused;
    emit AssetPaused(token);
}
```

**Level 2: Strategy Issue**
```solidity
function pauseStrategy(address strategy) external onlyGuardian {
    isActiveStrategy[strategy] = false;
    emit StrategyPaused(strategy);
}
```

**Level 3: Vault Emergency**
```solidity
function pause() external onlyGuardian {
    _pause(); // Stops all deposits/withdrawals
    emit EmergencyPause(block.timestamp);
}
```

**Recovery Process:**
1. Guardian pauses affected component
2. Team investigates and prepares fix
3. Fix deployed and tested on testnet
4. DAO votes on reactivation
5. Timelock executes unpause after delay

---

## Integration Patterns

### DEX Aggregator Integration

**Purpose:** Optimal swap routing for rebalancing.

```solidity
interface IDEXAggregator {
    struct SwapParams {
        address fromToken;
        address toToken;
        uint256 amount;
        uint256 minReturn;
        address recipient;
        bytes calldata;
    }
    
    function swap(SwapParams calldata params) 
        external 
        returns (uint256 returnAmount);
}

contract SwapRouter {
    IDEXAggregator public aggregator;
    
    function executeSwap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 maxSlippage
    ) internal returns (uint256) {
        // Get expected output from oracle
        uint256 expectedOutput = _getExpectedOutput(fromToken, toToken, amount);
        
        // Calculate minimum acceptable return
        uint256 minReturn = (expectedOutput * (10000 - maxSlippage)) / 10000;
        
        // Execute swap
        IDEXAggregator.SwapParams memory params = IDEXAggregator.SwapParams({
            fromToken: fromToken,
            toToken: toToken,
            amount: amount,
            minReturn: minReturn,
            recipient: address(this),
            calldata: _getOptimalRoute(fromToken, toToken, amount)
        });
        
        uint256 returnAmount = aggregator.swap(params);
        
        require(returnAmount >= minReturn, "Slippage too high");
        return returnAmount;
    }
}
```

**Supported Aggregators:**
- 1inch (primary)
- Paraswap (backup)
- 0x Protocol (fallback)

### Lending Protocol Integration

**Purpose:** Deploy idle capital to earn yield.

```solidity
interface ILendingPool {
    function deposit(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function getBalance(address asset) external view returns (uint256);
}

contract YieldStrategy is BaseStrategy {
    ILendingPool public aave;
    
    function _deposit(uint256 amount) internal override {
        IERC20(asset).approve(address(aave), amount);
        aave.deposit(asset, amount);
    }
    
    function totalValue() external view override returns (uint256) {
        return aave.getBalance(asset);
    }
}
```

### RWA Token Integration

**Purpose:** Handle tokens with transfer restrictions.

```solidity
contract RWAStrategy is BaseStrategy {
    
    mapping(address => bool) public hasRestrictions;
    
    function _deposit(uint256 amount) internal override {
        address token = /* RWA token address */;
        
        // Attempt transfer with graceful failure handling
        try IERC20(token).transferFrom(msg.sender, address(this), amount) {
            emit RWADeposited(token, amount);
        } catch Error(string memory reason) {
            emit RWATransferFailed(token, amount, reason);
            
            // Allocate to alternative asset instead
            _allocateToAlternative(amount);
        }
    }
    
    function _allocateToAlternative(uint256 amount) internal {
        // If RWA transfer fails (user not KYC'd), allocate to:
        // 1. Other RWA tokens in same category
        // 2. Stablecoins as fallback
        // 3. Return to vault if no alternatives
    }
}
```

---

## Gas Optimization Strategies

### Batch Operations

**Problem:** Individual user rebalancing costs 200k+ gas
**Solution:** Batch all users in single rebalance

```solidity
contract OptimizedVault {
    
    // Store rebalance operations and execute in batch
    struct PendingRebalance {
        address[] fromTokens;
        address[] toTokens;
        uint256[] amounts;
    }
    
    PendingRebalance public pending;
    
    function queueRebalanceOperation(
        address from,
        address to,
        uint256 amount
    ) internal {
        pending.fromTokens.push(from);
        pending.toTokens.push(to);
        pending.amounts.push(amount);
    }
    
    function executeBatchRebalance() external {
        // Net out offsetting trades
        _netTrades(pending);
        
        // Execute minimized set of swaps
        for (uint256 i = 0; i < pending.fromTokens.length; i++) {
            _executeSwap(
                pending.fromTokens[i],
                pending.toTokens[i],
                pending.amounts[i]
            );
        }
        
        // Clear pending operations
        delete pending;
    }
}
```

**Gas Savings:**
- Per-user cost: ~15k gas (amortized)
- vs. individual: ~200k gas
- **93% reduction**

### Storage Optimization

```solidity
// Bad: Multiple SLOADs
function getBadTotal() external view returns (uint256) {
    return strategies[0].value + strategies[1].value + strategies[2].value;
}

// Good: Single SLOAD with caching
function getGoodTotal() external view returns (uint256) {
    uint256 total;
    uint256 length = strategies.length;
    for (uint256 i = 0; i < length;) {
        total += strategies[i].value;
        unchecked { ++i; }
    }
    return total;
}
```

### Calldata Optimization

```solidity
// Use calldata instead of memory for read-only arrays
function processAssets(address[] calldata assets) external {
    // 64 gas per word vs. 3 gas for calldata
}
```

### Event Optimization

```solidity
// Index frequently queried fields
event Deposited(
    address indexed user,
    uint256 indexed vaultId,
    uint256 assets,
    uint256 shares
);
```

---

## Oracle & Price Feed Architecture

### Multi-Source Price Aggregation

```
┌──────────────────────────────────────────────────┐
│          Price Oracle System                     │
├──────────────────────────────────────────────────┤
│                                                  │
│  Primary: Chainlink ────┐                        │
│                         ├─→ Aggregator ──→ Price │
│  Backup: Band Protocol ─┘                        │
│                                                  │
│  Validation:                                     │
│  - Deviation check (< 2%)                        │
│  - Freshness check (< 1 hour)                    │
│  - Circuit breaker (> 10% move)                  │
└──────────────────────────────────────────────────┘
```

### TWAP Implementation

```solidity
contract TWAPOracle {
    
    struct Observation {
        uint256 timestamp;
        uint256 price;
    }
    
    mapping(address => Observation[]) public observations;
    uint256 public constant TWAP_PERIOD = 30 minutes;
    
    function getTWAP(address token) external view returns (uint256) {
        Observation[] memory obs = observations[token];
        uint256 cutoff = block.timestamp - TWAP_PERIOD;
        
        uint256 priceSum = 0;
        uint256 timeSum = 0;
        
        for (uint256 i = obs.length - 1; i >= 0; i--) {
            if (obs[i].timestamp < cutoff) break;
            
            uint256 weight = i == obs.length - 1 
                ? block.timestamp - obs[i].timestamp
                : obs[i + 1].timestamp - obs[i].timestamp;
            
            priceSum += obs[i].price * weight;
            timeSum += weight;
        }
        
        return priceSum / timeSum;
    }
}
```

---

## Upgrade Mechanisms

### Proxy Pattern with Timelock

```solidity
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract GovernanceTimelock {
    
    uint256 public constant DELAY = 2 days;
    
    mapping(bytes32 => bool) public queuedTransactions;
    
    function queueUpgrade(
        address proxy,
        address newImplementation
    ) external onlyGovernance returns (bytes32) {
        bytes32 txHash = keccak256(
            abi.encode(proxy, newImplementation, block.timestamp + DELAY)
        );
        
        queuedTransactions[txHash] = true;
        emit UpgradeQueued(proxy, newImplementation, block.timestamp + DELAY);
        
        return txHash;
    }
    
    function executeUpgrade(
        address proxy,
        address newImplementation,
        uint256 eta
    ) external {
        bytes32 txHash = keccak256(abi.encode(proxy, newImplementation, eta));
        
        require(queuedTransactions[txHash], "Not queued");
        require(block.timestamp >= eta, "Timelock not met");
        require(block.timestamp <= eta + GRACE_PERIOD, "Expired");
        
        // Execute upgrade
        TransparentUpgradeableProxy(payable(proxy)).upgradeTo(newImplementation);
        
        queuedTransactions[txHash] = false;
        emit UpgradeExecuted(proxy, newImplementation);
    }
}
```

### Version Control

```solidity
contract Versioned {
    string public constant VERSION = "1.0.0";
    
    event VersionUpdated(string oldVersion, string newVersion);
    
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }
}
```

---

## Testing & Deployment

### Testing Strategy

**Unit Tests (Foundry)**
```solidity
// test/MetaIndexVault.t.sol
contract MetaIndexVaultTest is Test {
    
    MetaIndexVault public vault;
    MockERC20 public usdc;
    
    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        vault = new MetaIndexVault(
            address(usdc),
            "Meta Index Vault",
            "mIndex",
            address(strategyManager),
            address(feeCollector)
        );
    }
    
    function testDeposit() public {
        uint256 depositAmount = 1000e6;
        usdc.mint(address(this), depositAmount);
        usdc.approve(address(vault), depositAmount);
        
        uint256 shares = vault.deposit(depositAmount, address(this));
        
        assertEq(vault.balanceOf(address(this)), shares);
        assertEq(vault.totalAssets(), depositAmount);
    }
    
    function testRebalance() public {
        // Test rebalancing logic
    }
    
    function testFeeCollection() public {
        // Test management fee accrual
    }
    
    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, vault.minDeposit(), vault.tvlCap());
        // Fuzz testing for edge cases
    }
}
```

**Integration Tests**
```solidity
contract IntegrationTest is Test {
    
    function testFullUserJourney() public {
        // 1. Deposit
        // 2. Wait for rebalance
        // 3. Check allocations
        // 4. Withdraw
        // 5. Verify accounting
    }
    
    function testMultiStrategyRebalance() public {
        // Test complex rebalancing scenarios
    }
}
```

**Fork Tests (Mainnet)**
```solidity
contract ForkTest is Test {
    
    function setUp() public {
        vm.createSelectFork("arbitrum_mainnet");
    }
    
    function testRealWorldSwaps() public {
        // Test against actual DEX liquidity
    }
    
    function testRWAIntegration() public {
        // Test with real BUIDL, OUSG tokens
    }
}
```

### Deployment Checklist

**Pre-Deployment:**
- [ ] All tests passing (100% coverage)
- [ ] Audit completed and issues resolved
- [ ] Gas optimization verified
- [ ] Documentation complete
- [ ] Testnet deployment successful
- [ ] Community testing phase complete

**Deployment Sequence:**

1. **Deploy Core Contracts**
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $ARBITRUM_RPC --broadcast --verify
```

2. **Initialize Contracts**
```solidity
// Set up roles
vault.grantRole(MANAGER_ROLE, address(strategyManager));
vault.grantRole(GUARDIAN_ROLE, address(multisig));

// Configure parameters
vault.updateTVLCap(1_000_000e6);
strategyManager.setRebalanceInterval(1 days);
```

3. **Deploy Strategies**
```bash
forge script script/DeployStrategies.s.sol
```

4. **Verify Contracts**
```bash
forge verify-contract <address> MetaIndexVault --chain-id 42161
```

5. **Transfer Ownership to Timelock**
```solidity
vault.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));
vault.renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
```

### Monitoring & Alerts

**Key Metrics:**
- Total Value Locked (TVL)
- Asset allocations vs. targets
- Fee collection amounts
- Rebalance frequency and gas costs
- Oracle price deviations
- User deposits/withdrawals

**Alert Triggers:**
- Asset allocation deviation > 5%
- Oracle price staleness
- Unusual withdrawal volume
- Smart contract pause events
- Gas costs exceeding threshold

**Dashboard:**
```
- Real-time TVL
- Current vs. target allocations
- Historical performance
- Gas cost analytics
- User statistics
```

---

## Appendix A: Interface Definitions

```solidity
interface IStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount, address recipient) external;
    function totalValue() external view returns (uint256);
}

interface IStrategyManager {
    function allocateDeposit(uint256 amount) external;
    function withdrawAssets(uint256 amount, address recipient) external;
    function rebalance() external;
    function getTotalValue() external view returns (uint256);
}

interface IIndexMethodology {
    function getTargetAllocations() external view returns (
        address[] memory assets,
        uint256[] memory allocations
    );
    function needsRebalance() external view returns (bool);
}

interface IFeeCollector {
    function collectFees(uint256 amount) external;
    function distributeToDAO() external;
}
```

---

## Appendix B: Gas Cost Estimates

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| Deposit | ~150k | Initial deposit |
| Withdraw | ~120k | Simple withdrawal |
| Rebalance (per user) | ~15k | Amortized batch cost |
| Add Strategy | ~100k | One-time governance |
| Update Allocation | ~50k | Governance change |

---

## Appendix C: Security Audit Scope

**In Scope:**
- MetaIndexVault.sol
- StrategyManager.sol
- All Strategy contracts
- AssetWhitelist.sol
- PriceOracle.sol
- GovernanceTimelock.sol

**Focus Areas:**
1. Access control verification
2. Reentrancy protection
3. Oracle manipulation resistance
4. Arithmetic overflow/underflow
5. Fee calculation accuracy
6. Emergency pause functionality

**Out of Scope:**
- Third-party integrations (Chainlink, DEXs)
- Governance token contract
- Frontend application

---

**Meta Index Protocol - Technical Specification**
*Version 1.0 | Pre-Audit Draft*

© 2025 Meta Index Protocol