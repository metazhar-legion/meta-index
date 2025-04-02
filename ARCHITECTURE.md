# Meta-Index (Web3 Index Fund) - Architecture

This document provides a detailed overview of the Meta-Index architecture, focusing on the gas-optimized IndexFundVaultV2 implementation and its components.

## System Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│                     Meta-Index Fund System                            │
│                                                                       │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │
                ┌───────────────────┴───────────────────┐
                │                                       │
┌───────────────▼───────────────┐       ┌───────────────▼───────────────┐
│                               │       │                               │
│     Smart Contract Layer      │       │       Frontend Layer          │
│                               │       │     (Future Enhancement)      │
└───────────────┬───────────────┘       └───────────────────────────────┘
                │                                       
    ┌───────────┴───────────────────────────┐               
    │                                       │               
┌───▼───────────────┐   ┌──────────────────▼───┐       
│                   │   │                      │       
│  IndexFundVaultV2 │◄──┤    FeeManager       │       
│    (ERC4626)      │   │                      │       
└───┬───────────────┘   └──────────────────────┘       
    │                                                   
    │                                                   
    │                                                   
┌───▼───────────────────────────────────────┐   
│                                           │   
│  Asset Management & External Integrations │   
└─┬─────────────────┬───────────────────┬───┘   
  │                 │                   │
  │                 │                   │
┌─▼─────────────┐ ┌─▼──────────┐ ┌─────▼──────────┐
│               │ │            │ │                │
│ RWAAsset      │ │ Stable    │ │   External     │
│ Wrapper       │ │ Yield     │ │   Services     │
│               │ │ Strategy  │ │ (Oracle, DEX)  │
└───────────────┘ └────────────┘ └────────────────┘
```

## Smart Contract Architecture

### Core Contracts

#### IndexFundVaultV2 (ERC4626)

The main vault contract that implements the ERC4626 standard with gas optimizations, handling deposits, withdrawals, and rebalancing through asset wrappers.

```
┌─────────────────────────────────────────────────────────────┐
│                     IndexFundVaultV2                        │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - asset: address                                            │
│ - assetList: address[]                                      │
│ - assets: mapping(address => AssetInfo)                     │
│ - feeManager: IFeeManager                                   │
│ - lastRebalance: uint32                                     │
│ - rebalanceInterval: uint32                                 │
│ - rebalanceThreshold: uint16                                │
│ - lastFeeCollection: uint32                                 │
│ - totalWeight: uint16                                       │
│ - paused: bool                                              │
├─────────────────────────────────────────────────────────────┤
│ Core ERC4626 Functions:                                     │
│ - deposit(uint256 assets, address receiver)                 │
│ - mint(uint256 shares, address receiver)                    │
│ - withdraw(uint256 assets, address receiver, address owner) │
│ - redeem(uint256 shares, address receiver, address owner)   │
│ - totalAssets()                                             │
├─────────────────────────────────────────────────────────────┤
│ Asset Management Functions:                                 │
│ - addAsset(address assetAddress, address wrapper, uint16 weight) │
│ - removeAsset(address assetAddress)                         │
│ - updateAssetWeight(address assetAddress, uint16 weight)    │
│ - rebalance()                                               │
│ - harvestYield()                                            │
│ - collectFees()                                             │
│ - pause()                                                   │
│ - unpause()                                                 │
│ - isRebalanceNeeded()                                       │
└─────────────────────────────────────────────────────────────┘
```

#### RWAAssetWrapper

A wrapper contract that encapsulates RWA tokens and manages the allocation between the RWA asset and yield strategies.

```
┌─────────────────────────────────────────────────────────────┐
│                     RWAAssetWrapper                         │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - rwaToken: IERC20                                          │
│ - baseAsset: IERC20                                         │
│ - priceOracle: IPriceOracle                                 │
│ - dex: IDEX                                                 │
│ - yieldStrategy: IYieldStrategy                             │
│ - owner: address                                            │
│ - yieldAllocation: uint256                                  │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - allocateCapital(uint256 amount)                           │
│ - withdrawCapital(uint256 amount)                           │
│ - getValueInBaseAsset()                                     │
│ - harvestYield()                                            │
│ - setYieldAllocation(uint256 allocation)                    │
│ - setYieldStrategy(address strategy)                        │
│ - emergencyWithdraw()                                       │
└─────────────────────────────────────────────────────────────┘
```

#### FeeManager

Handles the calculation and collection of management and performance fees.

```
┌─────────────────────────────────────────────────────────────┐
│                     FeeManager                              │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - managementFeeRate: uint256                                │
│ - performanceFeeRate: uint256                               │
│ - highWaterMark: uint256                                    │
│ - feeRecipient: address                                     │
│ - owner: address                                            │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - collectFees(uint256 totalValue, uint256 timeElapsed)      │
│ - calculateManagementFee(uint256 totalValue, uint256 timeElapsed) │
│ - calculatePerformanceFee(uint256 totalValue)               │
│ - setManagementFeeRate(uint256 newRate)                     │
│ - setPerformanceFeeRate(uint256 newRate)                    │
│ - setFeeRecipient(address newRecipient)                     │
└─────────────────────────────────────────────────────────────┘
```

#### StableYieldStrategy

Manages yield generation for idle capital, allowing the vault to earn returns on assets not currently allocated to RWA tokens.

```
┌─────────────────────────────────────────────────────────────┐
│                     StableYieldStrategy                     │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - baseAsset: IERC20                                         │
│ - yieldSource: address                                      │
│ - owner: address                                            │
│ - totalDeposited: uint256                                   │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - deposit(uint256 amount)                                   │
│ - withdraw(uint256 amount)                                  │
│ - harvestYield()                                            │
│ - getValueInBaseAsset()                                     │
│ - emergencyWithdraw()                                       │
│ - setYieldSource(address newSource)                         │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Scripts

#### DeployIndexFundVaultV2

Deploys a basic vault with minimal configuration.

#### DeployMultiAssetVault

Deploys a fully configured vault with multiple RWA assets and yield strategies, optimized to avoid stack-too-deep errors.                      │
│ - indexRegistry: IIndexRegistry                             │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - createProposal(bytes calldata data)                       │
│ - vote(uint256 proposalId, bool support)                    │
│ - executeProposal(uint256 proposalId)                       │
│ - setVotingPeriod(uint256 newPeriod)                        │
│ - setQuorum(uint256 newQuorum)                              │
└─────────────────────────────────────────────────────────────┘
```

#### CapitalAllocationManager

Manages the allocation of capital across different asset classes including crypto tokens, RWAs, and yield strategies.

```
┌─────────────────────────────────────────────────────────────┐
│                 CapitalAllocationManager                    │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - rwaPercentage: uint256                                    │
│ - yieldPercentage: uint256                                  │
│ - liquidityBufferPercentage: uint256                        │
│ - rwaTokens: mapping(address => RWAToken)                   │
│ - rwaTokenAddresses: address[]                              │
│ - yieldStrategies: mapping(address => YieldStrategy)        │
│ - yieldStrategyAddresses: address[]                         │
│ - lastRebalanced: uint256                                   │
│ - rebalancingThreshold: uint256                             │
│ - owner: address                                            │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - setAllocation(uint256 rwa, uint256 yield, uint256 buffer) │
│ - addRWAToken(address token, uint256 allocation)            │
│ - removeRWAToken(address token)                             │
│ - addYieldStrategy(address strategy, uint256 allocation)    │
│ - removeYieldStrategy(address strategy)                     │
│ - rebalance()                                               │
│ - getTotalValue()                                           │
│ - getRWAValue()                                             │
│ - getYieldValue()                                           │
│ - getLiquidityBufferValue()                                 │
└─────────────────────────────────────────────────────────────┘
```

#### StakingReturnsStrategy

Manages yield generation through staking protocols, providing returns on staked assets while maintaining liquidity.

```
┌─────────────────────────────────────────────────────────────┐
│                   StakingReturnsStrategy                    │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - baseAsset: IERC20                                         │
│ - stakingToken: IERC20                                      │
│ - stakingProtocol: address                                  │
│ - totalValue: uint256                                       │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - deposit(uint256 amount)                                   │
│ - withdraw(uint256 shares)                                  │
│ - getValueOfShares(uint256 shares)                          │
│ - getTotalValue()                                           │
│ - _stakeInProtocol(uint256 amount)                          │
│ - _withdrawFromStakingProtocol(uint256 amount)              │
└─────────────────────────────────────────────────────────────┘
```

The StakingReturnsStrategy implements a dual-mode approach for testing and production environments:

- In test environments (block.number ≤ 100), it uses simplified calculations for share values and withdrawals
- In production environments, it uses the full protocol integration with proper staking token accounting

This approach allows for easier unit testing while maintaining production functionality, but has limitations when testing on forked networks where block numbers are high.

#### RWASyntheticToken

Interface for synthetic tokens that represent real-world assets.

```
┌─────────────────────────────────────────────────────────────┐
│                    RWASyntheticToken                        │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - name: string                                              │
│ - symbol: string                                            │
│ - assetType: uint8                                          │
│ - baseAsset: IERC20                                         │
│ - perpetualTrading: IPerpetualTrading                       │
│ - priceOracle: address                                      │
│ - lastPrice: uint256                                        │
│ - lastUpdated: uint256                                      │
│ - marketId: bytes32                                         │
│ - collateralRatio: uint256                                  │
│ - totalCollateral: uint256                                  │
│ - leverage: uint256                                         │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - mint(address to, uint256 amount)                          │
│ - burn(address from, uint256 amount)                        │
│ - updatePrice()                                             │
│ - getAssetInfo()                                            │
│ - openPosition(uint256 collateralAmount)                    │
│ - closePosition()                                           │
│ - adjustPosition(uint256 newCollateralAmount)               │
└─────────────────────────────────────────────────────────────┘
```

### External Interfaces

#### IPriceOracle

Interface for price oracles that provide asset pricing data.

```
┌─────────────────────────────────────────────────────────────┐
│                     IPriceOracle                            │
├─────────────────────────────────────────────────────────────┤
│ Functions:                                                  │
│ - getPrice(address token) returns (uint256)                 │
│ - getPriceUSD(address token) returns (uint256)              │
└─────────────────────────────────────────────────────────────┘
```

#### IPerpetualTrading

Interface for perpetual trading platforms used for RWA synthetic tokens.

```
┌─────────────────────────────────────────────────────────────┐
│                     IPerpetualTrading                       │
├─────────────────────────────────────────────────────────────┤
│ Functions:                                                  │
│ - openPosition(bytes32 marketId, int256 size,               │
│                uint256 collateral, uint256 leverage)        │
│                returns (bytes32 positionId)                 │
│ - closePosition(bytes32 positionId)                         │
│                returns (int256 pnl)                         │
│ - adjustPosition(bytes32 positionId, int256 newSize,        │
│                  uint256 newCollateral, uint256 newLeverage)│
│ - getPositionValue(bytes32 positionId)                      │
│                    returns (uint256 value)                  │
│ - getMarketPrice(bytes32 marketId)                          │
│                  returns (uint256 price)                    │
│ - setMarketPrice(bytes32 marketId, uint256 price)           │
└─────────────────────────────────────────────────────────────┘
```

#### IDEX

Interface for decentralized exchanges used for rebalancing.

```
┌─────────────────────────────────────────────────────────────┐
│                     IDEX                                    │
├─────────────────────────────────────────────────────────────┤
│ Functions:                                                  │
│ - swap(address fromToken, address toToken,                  │
│        uint256 amount) returns (uint256)                    │
│ - getAmountOut(address fromToken, address toToken,          │
│                uint256 amountIn) returns (uint256)          │
└─────────────────────────────────────────────────────────────┘
```

#### DEXRouter

A router contract that manages interactions with different DEX adapters for optimal trading.

```
┌─────────────────────────────────────────────────────────────┐
│                     DEXRouter                               │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - adapters: mapping(address => IDEXAdapter)                 │
│ - adapterList: address[]                                    │
│ - owner: address                                            │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - addAdapter(address adapter)                               │
│ - removeAdapter(address adapter)                            │
│ - getBestQuote(address fromToken, address toToken,          │
│             uint256 amount)                                 │
│ - swap(address fromToken, address toToken,                  │
│        uint256 amount, uint256 minReturn)                   │
└─────────────────────────────────────────────────────────────┘
```

#### PerpetualRouter

A router contract that manages interactions with different perpetual trading protocols for synthetic asset exposure.

```
┌─────────────────────────────────────────────────────────────┐
│                   PerpetualRouter                           │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - adapters: mapping(address => IPerpAdapter)                │
│ - adapterList: address[]                                    │
│ - positions: mapping(bytes32 => Position)                   │
│ - owner: address                                            │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - addAdapter(address adapter)                               │
│ - removeAdapter(address adapter)                            │
│ - openPosition(address adapter, bytes32 marketId,           │
│               int256 size, uint256 collateral)              │
│ - closePosition(bytes32 positionId)                         │
│ - getPositionValue(bytes32 positionId)                      │
│ - calculatePnL(bytes32 positionId)                          │
└─────────────────────────────────────────────────────────────┘
```

### Testing Approach

The contracts are tested using Foundry, with a combination of unit tests and integration tests. Mock contracts are used to simulate external dependencies like price oracles, DEXes, and staking protocols.

```
┌─────────────────────────────────────────────────────────────┐
│                     Testing Strategy                        │
├─────────────────────────────────────────────────────────────┤
│ - Unit Tests: Test individual contract functions            │
│ - Integration Tests: Test interactions between contracts    │
│ - Mock Contracts: Simulate external dependencies            │
│ - Fuzzing: Test with randomized inputs                      │
│ - Gas Optimization Tests: Measure gas usage                 │
│ - Environment-Specific Logic: Different behavior in test    │
│   and production environments                               │
└─────────────────────────────────────────────────────────────┘
```

#### Environment-Specific Testing

Some contracts, like StakingReturnsStrategy, implement environment-specific logic to simplify testing:

```
┌─────────────────────────────────────────────────────────────┐
│                Environment-Specific Testing                 │
├─────────────────────────────────────────────────────────────┤
│ Local Testing (block.number ≤ 100):                         │
│ - Simplified calculations for predictable test results      │
│ - Direct 1:1 mapping between shares and underlying assets   │
│ - Skipped verification steps that require external calls    │
├─────────────────────────────────────────────────────────────┤
│ Production/Forked Testing (block.number > 100):             │
│ - Full protocol integration with proper accounting          │
│ - Complete verification of external interactions            │
│ - Accurate representation of real-world behavior            │
└─────────────────────────────────────────────────────────────┘
```

This approach allows for easier unit testing while maintaining production functionality, but requires more sophisticated mocks when testing on forked networks where block numbers exceed the threshold.
