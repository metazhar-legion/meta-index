# Web3 Index Fund - Architecture

This document provides a detailed overview of the Web3 Index Fund architecture, including both smart contracts and frontend components.

## System Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│                         Web3 Index Fund System                        │
│                                                                       │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │
                ┌───────────────────┴───────────────────┐
                │                                       │
┌───────────────▼───────────────┐       ┌───────────────▼───────────────┐
│                               │       │                               │
│     Smart Contract Layer      │       │       Frontend Layer          │
│                               │       │                               │
└───────────────┬───────────────┘       └───────────────┬───────────────┘
                │                                       │
    ┌───────────┴───────────┐               ┌───────────┴───────────┐
    │                       │               │                       │
┌───▼───┐   ┌───────┐   ┌───▼───┐       ┌───▼───┐   ┌───────┐   ┌───▼───┐
│       │   │       │   │       │       │       │   │       │   │       │
│ Vault │◄──┤Registry│◄──┤  DAO  │       │  UI   │◄──┤Web3   │◄──┤ API   │
│       │   │       │   │       │       │       │   │Context│   │Service│
└───┬───┘   └───────┘   └───────┘       └───────┘   └───┬───┘   └───────┘
    │                                                   │
┌───▼───────────────────────┐                   ┌───────▼─────────────────┐
│                           │                   │                         │
│  External Integrations    │◄──────────────────┤    User Interactions    │
│  (Oracle, DEX, RWAs)      │                   │                         │
└───────────────────────────┘                   └─────────────────────────┘
```

## Smart Contract Architecture

### Core Contracts

#### RWAIndexFundVault (ERC4626)

The main vault contract that implements the ERC4626 standard, handling deposits, withdrawals, and accounting with RWA support.

```
┌─────────────────────────────────────────────────────────────┐
│                     RWAIndexFundVault                       │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - asset: IERC20                                             │
│ - indexRegistry: IIndexRegistry                             │
│ - priceOracle: IPriceOracle                                 │
│ - dex: IDEX                                                 │
│ - capitalAllocationManager: ICapitalAllocationManager       │
│ - managementFeePercentage: uint256                          │
│ - performanceFeePercentage: uint256                         │
│ - highWaterMark: uint256                                    │
│ - lastRebalanceTimestamp: uint256                           │
│ - rebalancingInterval: uint256                              │
│ - rebalancingThreshold: uint256                             │
├─────────────────────────────────────────────────────────────┤
│ Core ERC4626 Functions:                                     │
│ - deposit(uint256 assets, address receiver)                 │
│ - mint(uint256 shares, address receiver)                    │
│ - withdraw(uint256 assets, address receiver, address owner) │
│ - redeem(uint256 shares, address receiver, address owner)   │
├─────────────────────────────────────────────────────────────┤
│ RWA Index Fund Specific Functions:                          │
│ - rebalance()                                               │
│ - addRWAToken(address token, uint256 allocation)            │
│ - removeRWAToken(address token)                             │
│ - addYieldStrategy(address strategy, uint256 allocation)    │
│ - removeYieldStrategy(address strategy)                     │
│ - setManagementFee(uint256 newFee)                          │
│ - setPerformanceFee(uint256 newFee)                         │
│ - setPriceOracle(address newOracle)                         │
│ - setDEX(address newDEX)                                    │
│ - totalAssets()                                             │
│ - _collectFees()                                            │
└─────────────────────────────────────────────────────────────┘
```

#### IndexRegistry

Manages the composition of the index, including token addresses and their weights.

```
┌─────────────────────────────────────────────────────────────┐
│                     IndexRegistry                           │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - tokens: address[]                                         │
│ - weights: mapping(address => uint256)                      │
│ - totalWeight: uint256                                      │
│ - owner: address                                            │
│ - dao: address                                              │
├─────────────────────────────────────────────────────────────┤
│ Core Functions:                                             │
│ - addToken(address token, uint256 weight)                   │
│ - removeToken(address token)                                │
│ - updateWeight(address token, uint256 newWeight)            │
│ - getTokens() returns (address[])                           │
│ - getWeight(address token) returns (uint256)                │
│ - getTotalWeight() returns (uint256)                        │
└─────────────────────────────────────────────────────────────┘
```

#### DAO Governance

Allows token holders to vote on proposals to change the index composition.

```
┌─────────────────────────────────────────────────────────────┐
│                     DAOGovernance                           │
├─────────────────────────────────────────────────────────────┤
│ State Variables:                                            │
│ - proposals: mapping(uint256 => Proposal)                   │
│ - nextProposalId: uint256                                   │
│ - votingPeriod: uint256                                     │
│ - quorum: uint256                                           │
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

## Frontend Architecture

### Core Components

#### Web3Context

Manages wallet connection, authentication, and contract interactions.

```
┌─────────────────────────────────────────────────────────────┐
│                     Web3Context                             │
├─────────────────────────────────────────────────────────────┤
│ State:                                                      │
│ - account: string                                           │
│ - chainId: number                                           │
│ - library: Web3Provider                                     │
│ - active: boolean                                           │
│ - error: Error                                              │
│ - userRole: UserRole                                        │
├─────────────────────────────────────────────────────────────┤
│ Functions:                                                  │
│ - connect()                                                 │
│ - disconnect()                                              │
│ - setUserRole(role: UserRole)                               │
└─────────────────────────────────────────────────────────────┘
```

#### useContracts Hook

Custom hook for interacting with smart contracts.

```
┌─────────────────────────────────────────────────────────────┐
│                     useContracts                            │
├─────────────────────────────────────────────────────────────┤
│ Returns:                                                    │
│ - vaultContract: Contract                                   │
│ - registryContract: Contract                                │
│ - daoContract: Contract                                     │
│ - tokenBalances: Record<string, BigNumber>                  │
│ - vaultStatistics: VaultStatistics                          │
│ - indexComposition: IndexToken[]                            │
├─────────────────────────────────────────────────────────────┤
│ Functions:                                                  │
│ - deposit(amount: BigNumber)                                │
│ - withdraw(shares: BigNumber)                               │
│ - addToken(token: string, weight: number)                   │
│ - removeToken(token: string)                                │
│ - updateWeight(token: string, weight: number)               │
│ - rebalance()                                               │
│ - collectFees()                                             │
└─────────────────────────────────────────────────────────────┘
```

### Page Components

#### InvestorPage

Dashboard for investors to deposit, withdraw, and view statistics.

```
┌─────────────────────────────────────────────────────────────┐
│                     InvestorPage                            │
├─────────────────────────────────────────────────────────────┤
│ Components:                                                 │
│ - VaultStatistics                                           │
│ - IndexComposition                                          │
│ - DepositForm                                               │
│ - WithdrawForm                                              │
│ - TransactionHistory                                        │
└─────────────────────────────────────────────────────────────┘
```

#### DAOMemberPage

Dashboard for DAO members to manage index composition.

```
┌─────────────────────────────────────────────────────────────┐
│                     DAOMemberPage                           │
├─────────────────────────────────────────────────────────────┤
│ Components:                                                 │
│ - IndexComposition                                          │
│ - AddTokenForm                                              │
│ - UpdateWeightForm                                          │
│ - RemoveTokenForm                                           │
│ - ProposalList (future)                                     │
└─────────────────────────────────────────────────────────────┘
```

#### PortfolioManagerPage

Dashboard for portfolio managers to rebalance and collect fees.

```
┌─────────────────────────────────────────────────────────────┐
│                     PortfolioManagerPage                    │
├─────────────────────────────────────────────────────────────┤
│ Components:                                                 │
│ - VaultStatistics                                           │
│ - IndexComposition                                          │
│ - RebalanceButton                                           │
│ - FeeCollection                                             │
│ - ConfigurationForm                                         │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌──────────┐    ┌───────────┐    ┌──────────────┐    ┌──────────────┐
│          │    │           │    │              │    │              │
│  User    │───►│  Frontend │───►│  Web3/Ethers │───►│  Blockchain  │
│          │    │           │    │              │    │              │
└──────────┘    └───────────┘    └──────────────┘    └──────────────┘
      ▲               │                 ▲                   │
      │               │                 │                   │
      │               ▼                 │                   ▼
┌──────────┐    ┌───────────┐    ┌──────────────┐    ┌──────────────┐
│          │    │           │    │              │    │              │
│  Browser │◄───┤  React UI │◄───┤  Contracts   │◄───┤  Smart       │
│          │    │           │    │  Context     │    │  Contracts   │
└──────────┘    └───────────┘    └──────────────┘    └──────────────┘
```

## Deployment Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                      Client's Browser                            │
│                                                                  │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                      Frontend Hosting                            │
│                  (AWS S3/CloudFront/GitHub Pages)                │
│                                                                  │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
┌────────────────▼─────────────┐   ┌─────────▼────────────────────┐
│                              │   │                              │
│     Ethereum Blockchain      │   │      External Services       │
│     (Mainnet/Testnet)        │   │      (IPFS, TheGraph)        │
│                              │   │                              │
└──────────────────────────────┘   └──────────────────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                      Security Layers                            │
│                                                                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
┌─────────────▼───────┐ ┌─────▼──────┐ ┌──────▼─────────┐
│                     │ │            │ │                │
│  Smart Contract     │ │ Frontend   │ │ Infrastructure │
│  Security           │ │ Security   │ │ Security       │
│                     │ │            │ │                │
└─────────────────────┘ └────────────┘ └────────────────┘

Smart Contract Security:
- Reentrancy Guards
- Access Controls
- Input Validation
- Fee Limits
- Emergency Pause

Frontend Security:
- Input Validation
- Error Handling
- No Private Keys
- HTTPS Only
- Content Security Policy

Infrastructure Security:
- DDOS Protection
- Regular Backups
- Monitoring
- Alerting
- Secure Deployments
```

## Conclusion

This architecture document provides a high-level overview of the Web3 Index Fund system. The modular design allows for flexibility and extensibility, enabling future enhancements and integrations with the broader DeFi ecosystem.
