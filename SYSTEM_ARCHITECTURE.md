# ComposableRWA System Architecture Diagram

This document provides a comprehensive visual representation of the ComposableRWA system architecture, illustrating the relationships between frontend, smart contracts, and external systems.

## Complete System Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                           ComposableRWA Platform Architecture                           │
│                                (Production-Ready)                                       │
└─────────────────────────────────────┬─────────────────────────────────────────────────┘
                                      │
    ┌─────────────────────────────────┴─────────────────────────────────┐
    │                                                                   │
┌───▼──────────────────────┐                            ┌───────────────▼──────────────────┐
│                          │                            │                                  │
│    Frontend Layer        │◄──────── Web3 ──────────►│     Smart Contract Layer        │
│   (React/TypeScript)     │        Integration        │         (Solidity)              │
│                          │                            │                                  │
│ ┌──────────────────────┐ │                            │ ┌──────────────────────────────┐ │
│ │  ComposableRWA UI    │ │                            │ │    ComposableRWABundle       │ │
│ │                      │ │                            │ │                              │ │
│ │ • Multi-Strategy     │ │◄──────┐           ┌──────►│ │ ┌──────────────────────────┐ │ │
│ │   Dashboard          │ │       │           │       │ │ │ TRSExposureStrategy      │ │ │
│ │ • Capital Allocation │ │       │           │       │ │ │                          │ │ │
│ │ • Real-time Charts   │ │       │           │       │ │ │ • Multi-counterparty     │ │ │
│ │ • Yield Harvesting   │ │       │           │       │ │ │ • Risk management        │ │ │
│ │ • Optimization       │ │       │           │       │ │ │ • Quote optimization     │ │ │
│ └──────────────────────┘ │       │           │       │ │ └──────────────────────────┘ │ │
│                          │       │           │       │ │                              │ │
│ ┌──────────────────────┐ │       │           │       │ │ ┌──────────────────────────┐ │ │
│ │  Legacy Interfaces   │ │       │           │       │ │ │EnhancedPerpetualStrategy │ │ │
│ │                      │ │       │           │       │ │ │                          │ │ │
│ │ • Investor Page      │ │       │           │       │ │ │ • Dynamic leverage       │ │ │
│ │ • DAO Member         │ │       │           │       │ │ │ • PnL tracking          │ │ │
│ │ • Portfolio Manager  │ │       │           │       │ │ │ • Funding rate mgmt     │ │ │
│ └──────────────────────┘ │       │           │       │ │ └──────────────────────────┘ │ │
│                          │       │           │       │ │                              │ │
│ ┌──────────────────────┐ │       │           │       │ │ ┌──────────────────────────┐ │ │
│ │   Data Management    │ │       │           │       │ │ │  DirectTokenStrategy     │ │ │
│ │                      │ │       │           │       │ │ │                          │ │ │
│ │ • Contract Hooks     │ │       │           │       │ │ │ • DEX integration        │ │ │
│ │ • State Sync         │ │◄──────┘           └──────►│ │ │ • Slippage protection   │ │ │
│ │ • Error Handling     │ │                            │ │ │ • Yield optimization     │ │ │
│ │ • Caching (ISSUES)   │ │                            │ │ └──────────────────────────┘ │ │
│ └──────────────────────┘ │                            │ └──────────────────────────────┘ │
└──────────────────────────┘                            │                                  │
              │                                         │ ┌──────────────────────────────┐ │
              │                                         │ │    StrategyOptimizer         │ │
              ▼                                         │ │                              │ │
┌──────────────────────────┐                            │ │ • Real-time cost analysis    │ │
│                          │                            │ │ • Performance tracking       │ │
│    Web3 Integration      │                            │ │ • Auto-rebalancing          │ │
│                          │                            │ │ • Risk assessment            │ │
│ • MetaMask Connection    │                            │ └──────────────────────────────┘ │
│ • Provider Management    │                            └──────────────────────────────────┘
│ • Transaction Handling   │                                              │
│ • Error Recovery         │                                              │
│ • Network Switching      │                ┌─────────────────────────────┴─────────────────────────────┐
└──────────────────────────┘                │                                                           │
                                           │                                                           │
                              ┌────────────▼─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────▼────────┐
                              │                          │  │             │  │             │  │               │
                              │    Mock TRS Provider     │  │ Mock Price  │  │ Mock        │  │  Mock DEX     │
                              │                          │  │ Oracle      │  │ Perpetual   │  │  Router       │
                              │ • Quote management       │  │             │  │ Router      │  │               │
                              │ • Multi-counterparty     │  │ • Asset     │  │             │  │ • Token       │
                              │   support                │  │   pricing   │  │ • Position  │  │   swapping    │
                              │ • Risk assessment        │  │ • Real-time │  │   tracking  │  │ • Liquidity   │
                              │ • Contract lifecycle     │  │   updates   │  │ • Leverage  │  │   management  │
                              └──────────────────────────┘  └─────────────┘  └─────────────┘  └───────────────┘
```

## Frontend Data Flow & Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              Frontend Architecture                                        │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│ ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│ │                 │    │                 │    │                 │    │                 │ │
│ │ ComposableRWA   │    │ Strategy        │    │ Capital         │    │ Error & Loading │ │
│ │ Dashboard       │    │ Components      │    │ Allocation      │    │ Management      │ │
│ │                 │    │                 │    │                 │    │                 │ │
│ │ • Portfolio     │    │ • TRS Strategy  │    │ • USDC Deposits │    │ • Error Bounds  │ │
│ │   Overview      │    │ • Perpetual     │    │ • Withdrawals   │    │ • Loading States│ │
│ │ • Health Status │    │ • Direct Token  │    │ • Approvals     │    │ • Retry Logic   │ │
│ │ • Performance   │    │ • Optimization  │    │ • Balance Mgmt  │    │ • User Feedback │ │
│ └─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│          │                       │                       │                       │        │
│          └───────────────────────┼───────────────────────┼───────────────────────┘        │
│                                  │                       │                                │
│ ┌─────────────────────────────────┼───────────────────────┼─────────────────────────────┐  │
│ │                    Custom Hooks & State Management      │                             │  │
│ │                                 │                       │                             │  │
│ │ ┌─────────────────┐    ┌────────▼────────┐    ┌─────────▼──────┐    ┌─────────────────┐ │  │
│ │ │                 │    │                 │    │                │    │                 │ │  │
│ │ │useComposableRWA │    │ useContracts    │    │ Web3Context    │    │ Error Recovery  │ │  │
│ │ │                 │    │ (Legacy)        │    │                │    │                 │ │  │
│ │ │• Bundle mgmt    │    │                 │    │• Provider mgmt │    │• Retry logic    │ │  │
│ │ │• Strategy ops   │    │• ERC4626 vault  │    │• Account state │    │• State cleanup  │ │  │
│ │ │• Real-time data │    │• Token mgmt     │    │• Network switch│    │• Error messages │ │  │
│ │ │• CACHING ISSUES │    │                 │    │• Connection    │    │• Recovery flows │ │  │
│ │ └─────────────────┘    └─────────────────┘    └────────────────┘    └─────────────────┘ │  │
│ └─────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                              │                                                │
│ ┌─────────────────────────────────────────────▼─────────────────────────────────────────────┐ │
│ │                          Contract Interface Layer                                        │ │
│ │                                                                                         │ │
│ │ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────────┐   │ │
│ │ │                 │ │                 │ │                 │ │                         │   │ │
│ │ │ Contract ABIs   │ │ Type Definitions│ │ Address Config  │ │ Transaction Handling    │   │ │
│ │ │                 │ │                 │ │                 │ │                         │   │ │
│ │ │• ComposableRWA  │ │• Strategy types │ │• Deployed       │ │• Gas estimation        │   │ │
│ │ │• All Strategies │ │• Event types    │ │  addresses      │ │• Error handling         │   │ │  
│ │ │• Optimizer      │ │• Data models    │ │• Network config │ │• Status tracking        │   │ │
│ │ │• Mock contracts │ │• Interface defs │ │• Environment    │ │• Confirmation waits     │   │ │
│ │ └─────────────────┘ └─────────────────┘ └─────────────────┘ └─────────────────────────┘   │ │
│ └─────────────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                                ┌─────────────────────────┐
                                │                         │
                                │   Blockchain Layer      │
                                │  (Local Development)    │
                                │                         │
                                │ • Anvil local node      │
                                │ • Deployed contracts    │ 
                                │ • Test accounts         │
                                │ • Mock infrastructure   │
                                └─────────────────────────┘
```

## Data Flow & Issues

### Current Data Loading Problems

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          Current Data Flow Issues                                        │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│ ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────────────────┐ │
│ │                 │ REQUEST │                 │ RESULT  │                             │ │
│ │ UI Components   │───────► │ Contract Hooks  │────────►│  Contract Interface         │ │
│ │                 │◄─┐      │                 │◄────────│                             │ │
│ │ ❌ Excessive    │  │      │ ❌ No caching   │         │ • Multiple redundant calls │ │
│ │   re-renders    │  │      │ ❌ No batching  │         │ • No request deduplication  │ │
│ │ ❌ Inconsistent │  │      │ ❌ Poor error   │         │ • Synchronous blocking      │ │
│ │   loading states│  │      │   recovery      │         │ • No loading coordination   │ │
│ └─────────────────┘  │      └─────────────────┘         └─────────────────────────────┘ │
│          ▲           │                                                                  │
│          │           │                                                                  │
│    ERROR CASCADING   │                                                                  │
│          │           │                                                                  │
│ ┌────────┴────────┐  │                                                                  │
│ │                 │  │                                                                  │
│ │ Error Handling  │  │                                                                  │
│ │                 │  │                                                                  │  
│ │ ❌ No boundaries│  │                                                                  │
│ │ ❌ UI freezing  │  │                                                                  │
│ │ ❌ Poor UX      │──┘                                                                  │
│ └─────────────────┘                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Proposed Improved Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        Improved Data Flow Architecture                                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│ ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────────────────┐ │
│ │                 │ REQUEST │                 │ RESULT  │                             │ │
│ │ UI Components   │───────► │ React Query     │────────►│  Optimized Contract Layer   │ │
│ │                 │◄─┐      │ Data Layer      │◄────────│                             │ │
│ │ ✅ Optimized    │  │      │                 │         │ • Request batching          │ │
│ │   rendering     │  │      │ ✅ Smart caching│         │ • Deduplication            │ │
│ │ ✅ Loading      │  │      │ ✅ Background   │         │ • Async coordination       │ │
│ │   coordination  │  │      │   updates       │         │ • Error recovery           │ │
│ └─────────────────┘  │      │ ✅ Retry logic  │         └─────────────────────────────┘ │
│          ▲           │      └─────────────────┘                                         │
│          │           │                                                                  │
│    GRACEFUL DEGRADATION                                                                 │
│          │           │                                                                  │
│ ┌────────┴────────┐  │                                                                  │
│ │                 │  │                                                                  │
│ │ Error Boundaries│  │                                                                  │
│ │                 │  │                                                                  │  
│ │ ✅ Comprehensive│  │                                                                  │
│ │ ✅ User-friendly│  │                                                                  │
│ │ ✅ Recovery UX  │──┘                                                                  │
│ └─────────────────┘                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Smart Contract Layer Details

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           Smart Contract Architecture                                    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│                            ComposableRWABundle (Central Hub)                            │
│                                          │                                             │
│       ┌─────────────────────────────────┼─────────────────────────────────┐           │
│       │                                 │                                 │           │
│ ┌─────▼──────┐              ┌───────────▼──────────┐              ┌──────▼─────┐     │
│ │            │              │                      │              │            │     │
│ │    TRS     │              │ EnhancedPerpetual   │              │   Direct   │     │
│ │ Exposure   │              │    Strategy         │              │   Token    │     │
│ │ Strategy   │              │                     │              │  Strategy  │     │
│ │            │              │ • Leverage mgmt     │              │            │     │
│ │ • Multi-   │              │ • PnL tracking      │              │ • DEX      │     │
│ │   counter- │              │ • Funding rates     │              │   integration │   │
│ │   party    │              │ • Risk controls     │              │ • Yield    │     │
│ │ • Risk mgmt│              │ • Emergency exits   │              │   optimization│   │
│ └────────────┘              └─────────────────────┘              └────────────┘     │
│       │                                 │                                 │           │
│       └─────────────────────────────────┼─────────────────────────────────┘           │
│                                         │                                             │
│                               ┌─────────▼──────────┐                                  │
│                               │                    │                                  │
│                               │  StrategyOptimizer │                                  │
│                               │                    │                                  │
│                               │ • Cost analysis    │                                  │
│                               │ • Performance      │                                  │
│                               │ • Rebalancing      │                                  │
│                               │ • Risk assessment  │                                  │
│                               └────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Deployment & Infrastructure

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                             Development Infrastructure                                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│ ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│ │                 │    │                 │    │                 │    │                 │ │
│ │  Local Anvil    │    │  Smart Contract │    │   Frontend      │    │   Testing       │ │
│ │   Blockchain    │    │   Deployment    │    │   Development   │    │   Framework     │ │
│ │                 │    │                 │    │   Server        │    │                 │ │
│ │ • Port 8545     │◄──►│ • Foundry       │◄──►│ • React/TS      │◄──►│ • Forge tests   │ │
│ │ • Chain ID      │    │ • Deploy script │    │ • Port 3000     │    │ • Integration   │ │
│ │   31337         │    │ • Address mgmt  │    │ • Hot reload    │    │ • End-to-end    │ │
│ │ • Test accounts │    │ • Contract ABI  │    │ • Error logging │    │ • Performance   │ │
│ └─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│          │                       │                       │                       │        │
│          └───────────────────────┼───────────────────────┼───────────────────────┘        │
│                                  │                       │                                │
│                 ┌────────────────▼───────────────────────▼────────────────┐               │
│                 │                                                          │               │
│                 │            One-Click Deployment                          │               │
│                 │               (deploy-and-test.sh)                       │               │
│                 │                                                          │               │
│                 │ • Environment setup and validation                       │               │
│                 │ • Blockchain startup and configuration                   │               │
│                 │ • Contract compilation and deployment                     │               │
│                 │ • Frontend build and startup                            │               │
│                 │ • Address management and configuration                   │               │
│                 │ • Service monitoring and health checks                   │               │
│                 └──────────────────────────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

This architecture diagram provides a comprehensive overview of the ComposableRWA system, highlighting both the current implementation and the identified areas for frontend improvement.