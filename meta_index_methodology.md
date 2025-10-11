# Meta Index Protocol
## Index Methodology Framework

**Version 1.0 | October 2025**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Index Construction Principles](#index-construction-principles)
3. [Rules-Based Methodology Framework](#rules-based-methodology-framework)
4. [Flagship Indices](#flagship-indices)
5. [DAO Governance Process](#dao-governance-process)
6. [Rebalancing Procedures](#rebalancing-procedures)
7. [Asset Selection Criteria](#asset-selection-criteria)
8. [Risk Management](#risk-management)

---

## Introduction

### Purpose

This document establishes the methodological framework for creating, maintaining, and governing indices within the Meta Index Protocol. All indices follow transparent, rules-based methodologies that can be executed algorithmically by smart contracts without human discretion.

### Core Principles

**1. Transparency**
- All methodology rules are publicly documented
- Allocation formulas are open source
- Rebalancing triggers are predetermined
- No black-box decisions

**2. Rules-Based Execution**
- Smart contracts follow predefined algorithms
- No discretionary management
- Objective, verifiable criteria
- Deterministic outcomes

**3. DAO Governance**
- Community proposes new methodologies
- Token holders vote on index additions
- Decentralized oversight of parameters
- Continuous improvement through governance

**4. Institutional Grade**
- Rigorous back-testing requirements
- Clear risk/return objectives
- Professional documentation standards
- Academic research foundations

---

## Index Construction Principles

### Index Design Philosophy

Meta Index methodologies draw on decades of portfolio theory research while adapting to the unique characteristics of digital assets.

**Traditional Finance Foundations:**
- Modern Portfolio Theory (Markowitz)
- Capital Asset Pricing Model (CAPM)
- Factor-based investing (Fama-French)
- Risk parity approaches

**DeFi Adaptations:**
- 24/7 market dynamics
- Higher volatility tolerance
- Composability considerations
- Gas optimization needs
- Smart contract automation

### Key Methodology Components

Every Meta Index methodology must specify:

**1. Investment Objective**
```
Clear statement of:
- Target audience
- Risk profile
- Return expectations
- Time horizon
```

**2. Universe Definition**
```
Eligible assets must meet:
- Asset class criteria
- Liquidity minimums
- Market cap thresholds
- Quality standards
```

**3. Weighting Scheme**
```
How assets are weighted:
- Market capitalization
- Equal weight
- Fundamental metrics
- Risk-adjusted
- Factor-based
```

**4. Rebalancing Rules**
```
When and how to rebalance:
- Frequency (daily/weekly/monthly/quarterly)
- Thresholds (% deviation triggers)
- Methodology (full vs. partial)
- Transaction cost considerations
```

**5. Index Calculations**
```
Mathematical formulas for:
- Index level calculation
- Divisor methodology
- Corporate actions handling
- Fee incorporation
```

---

## Rules-Based Methodology Framework

### Template Structure

All index methodologies follow this standardized template:

```markdown
# [Index Name] Methodology

## 1. Objective
[Clear investment objective statement]

## 2. Eligible Universe
### Inclusion Criteria
- Asset class: [Crypto/DeFi/RWA/Yield]
- Minimum market cap: $[amount]
- Minimum liquidity: $[daily volume]
- Age requirement: [days since launch]
- Quality filters: [additional criteria]

### Exclusion Criteria
- Stablecoins (unless specifically included)
- Wrapped versions (select one canonical)
- Sunset protocols (TVL decline > 50%)
- Security incidents (within 6 months)

## 3. Weighting Methodology
### Formula
[Mathematical specification]

### Caps and Floors
- Maximum single asset: [%]
- Minimum single asset: [%]
- Category maximums: [breakdown]

## 4. Rebalancing
### Frequency
[Schedule]

### Threshold Triggers
[Deviation percentages]

### Methodology
[Full reconstitution vs. incremental]

## 5. Calculations
### Index Level
Index_t = (Sum of Asset Values_t / Divisor_t) * 100

### Divisor Adjustments
[Corporate actions, additions, deletions]

## 6. Backtesting Results
[Historical performance data]

## 7. Risk Metrics
- Volatility: [expected range]
- Maximum drawdown: [historical]
- Sharpe ratio: [target]
- Correlation to benchmarks: [data]
```

### Algorithmic Implementation

Each methodology translates to smart contract logic:

```solidity
interface IIndexMethodology {
    
    struct IndexConfig {
        string name;
        uint256 rebalanceInterval;
        uint256 deviationThreshold;
        uint256 maxAssetWeight;
        uint256 minAssetWeight;
    }
    
    function getTargetAllocations() 
        external 
        view 
        returns (
            address[] memory assets,
            uint256[] memory weights
        );
    
    function needsRebalance() 
        external 
        view 
        returns (bool);
    
    function calculateNewWeights(
        address[] memory currentAssets,
        uint256[] memory currentValues
    ) external view returns (
        uint256[] memory newWeights
    );
}
```

---

## Flagship Indices

### 1. Balanced OnChain Portfolio (BOCP)

**Ticker:** $BOCP  
**Launch Date:** Q1 2026 (Target)

#### Objective
Provide diversified exposure to the onchain economy, balancing growth potential of crypto assets with stability of tokenized real-world assets and yield from DeFi protocols.

**Target Audience:** General investors seeking comprehensive onchain exposure  
**Risk Profile:** Moderate (Volatility: 30-50% annualized)  
**Rebalancing:** Monthly

#### Asset Allocation

**Target Weights:**
- **35% Cryptocurrencies**
  - Bitcoin (wBTC): 15%
  - Ethereum (ETH): 15%
  - Top 5 Alt-L1s: 5% (equal-weighted)
  
- **35% Real-World Assets**
  - U.S. Treasuries (BUIDL, OUSG): 20%
  - Money Market Funds (BENJI): 10%
  - Private Credit: 5%
  
- **20% DeFi Protocol Tokens**
  - Top 10 by TVL: Equal-weighted
  - Examples: UNI, AAVE, CRV, LINK
  
- **10% Yield Strategies**
  - Liquid Staking (stETH, rETH): 5%
  - Lending Positions (aUSDC): 3%
  - LP Positions: 2%

#### Eligibility Criteria

**Cryptocurrencies:**
- Market cap > $1B
- Daily volume > $100M
- Listed on major exchanges
- Active development (GitHub commits)

**RWA Tokens:**
- Issued by regulated entities
- Minimum $10M TVL
- Clear redemption mechanism
- Audited reserves

**DeFi Tokens:**
- Protocol TVL > $100M
- Operating > 6 months
- No security incidents in past 6 months
- Clear revenue model

**Yield Strategies:**
- Protocol audit by reputable firm
- TVL > $500M
- APY within reasonable bounds (<30%)
- Proven track record

#### Weighting Methodology

**Within Categories:**
```
Crypto: Modified Market Cap Weighted
- Weight = (Market Cap)^0.75
- Adjusted to reduce concentration

DeFi: Equal Weighted within Top 10 by TVL
- Reconstituted quarterly
- TVL measured as 30-day average

RWA: Strategic Allocation
- 60% short-term (< 1 year maturity)
- 40% longer duration or yield-focused

Yield: Risk-Adjusted
- Higher allocation to lower-risk strategies
- Capped at 2% per protocol
```

#### Rebalancing Rules

**Monthly Rebalancing:**
- Occurs first Monday of each month
- Executed at 00:00 UTC

**Threshold-Triggered Rebalancing:**
- If any asset deviates > 5% from target
- If total deviation exceeds 10%
- Emergency rebalancing for risk events

**Rebalancing Process:**
1. Calculate current weights
2. Determine required trades
3. Optimize trade execution (minimal cost)
4. Execute swaps
5. Update divisor if needed

#### Index Calculation

```
BOCPIndex_t = (Σ(Asset_i * Weight_i * Price_i) / Divisor) * 100

Where:
- Asset_i = quantity of asset i
- Weight_i = target weight of asset i
- Price_i = USD price of asset i
- Divisor = adjustment factor for consistency
```

**Initial Index Level:** 100 (at launch)

#### Risk Parameters

**Expected Metrics:**
- Annualized Volatility: 35-45%
- Maximum Drawdown: <60% (historical crypto markets)
- Sharpe Ratio Target: 0.8-1.2
- Correlation to BTC: 0.4-0.6
- Correlation to TradFi: 0.2-0.3

**Risk Limits:**
- Maximum single asset: 20%
- Maximum category deviation: ±5%
- Liquidity requirement: Can liquidate 50% in <2 hours
- Circuit breaker: Pause if any asset moves >30% in 1 hour

---

### 2. DeFi Innovation Index (DII)

**Ticker:** $DII  
**Launch Date:** Q2 2026 (Target)

#### Objective
Capture the growth and innovation of decentralized finance protocols through exposure to governance tokens of leading DeFi platforms.

**Target Audience:** DeFi-native investors seeking concentrated DeFi exposure  
**Risk Profile:** High (Volatility: 50-80% annualized)  
**Rebalancing:** Quarterly

#### Asset Allocation

**Selection Methodology:**
1. Rank DeFi protocols by TVL
2. Filter for minimum criteria
3. Select top 15 protocols
4. Equal-weight allocation

**Target Allocation:**
- 15 DeFi protocol tokens
- 6.67% each (equal-weighted)
- Reconstituted quarterly

**Current Holdings (Illustrative):**
- Uniswap (UNI)
- Aave (AAVE)
- Curve (CRV)
- Lido (LDO)
- MakerDAO (MKR)
- Compound (COMP)
- Synthetix (SNX)
- Rocket Pool (RPL)
- Convex (CVX)
- Balancer (BAL)
- GMX
- Pendle (PENDLE)
- Frax (FXS)
- Euler (EUL)
- Radiant (RDNT)

#### Eligibility Criteria

**Minimum Requirements:**