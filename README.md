# Web3 Index Fund (Meta-Index) - Composable RWA Exposure

A next-generation, gas-optimized, ERC4626-compliant index fund vault featuring composable Real-World Asset (RWA) exposure strategies. The vault uses a modular multi-strategy architecture enabling dynamic optimization across Total Return Swaps (TRS), perpetual futures, and direct token strategies.

## 🚀 Key Features

### Composable RWA Architecture
- **Multi-Strategy Support**: TRS, Perpetual Trading, Direct Token purchases
- **Dynamic Optimization**: Real-time strategy selection based on cost and risk
- **Intelligent Risk Management**: Multi-counterparty diversification and concentration limits
- **Capital Efficiency**: Leveraged exposure strategies enable higher yield allocation

### Advanced TRS Implementation ✨ NEW
- **Multi-Counterparty Support**: AAA, BBB, BB rated counterparties with concentration limits
- **Real-time Quote Selection**: Competitive bidding with cost optimization
- **Contract Lifecycle Management**: Automated rollover and settlement
- **Risk Controls**: 40% max concentration per counterparty, position size limits

### Gas-Optimized Infrastructure
- **ERC4626 Compliance**: Standard vault interface with institutional features
- **Modular Architecture**: Clean separation via composable strategy bundles
- **Efficient Storage**: Optimized variable packing and data structures
- **Automated Rebalancing**: Cost-aware strategy switching and portfolio management

## 🏗️ Architecture Overview

```
IndexFundVaultV2 (ERC4626)
       │
       ▼
ComposableRWABundle
├── TRSExposureStrategy        ← ✅ IMPLEMENTED (26/26 tests passing)
├── EnhancedPerpetualStrategy  ← ✅ IMPLEMENTED  
├── DirectTokenStrategy        ← 🔄 IN PROGRESS
└── YieldStrategyBundle        ← ✅ IMPLEMENTED
       │
       ▼
StrategyOptimizer
├── Real-time Cost Analysis
├── Risk Assessment Engine
├── Performance Tracking
└── Rebalancing Logic
```

## 📁 Project Structure

```
├── src/
│   ├── ComposableRWABundle.sol         # Central multi-strategy orchestrator
│   ├── StrategyOptimizer.sol            # Strategy optimization engine
│   ├── interfaces/
│   │   ├── IExposureStrategy.sol        # Unified strategy interface
│   │   ├── ITRSProvider.sol             # TRS provider interface
│   │   └── IStrategyOptimizer.sol       # Optimizer interface
│   ├── strategies/
│   │   ├── TRSExposureStrategy.sol      # ✅ Total Return Swap strategy
│   │   ├── EnhancedPerpetualStrategy.sol # ✅ Enhanced perpetual trading
│   │   └── DirectTokenStrategy.sol      # 🔄 Direct RWA token purchases
│   ├── mocks/
│   │   ├── MockTRSProvider.sol          # ✅ Production-like TRS provider
│   │   ├── MockUSDC.sol                 # ✅ Test token
│   │   └── MockPriceOracle.sol          # ✅ Price oracle mock
│   ├── IndexFundVaultV2.sol             # ✅ Main ERC4626 vault
│   ├── FeeManager.sol                   # ✅ Fee calculation and collection
│   └── errors/
│       └── CommonErrors.sol             # ✅ Standardized error handling
├── test/                                # ✅ 100% test coverage for TRS
│   ├── TRSExposureStrategy.t.sol        # ✅ 26/26 tests passing
│   ├── ComposableRWABundle.t.sol        # ✅ Integration tests
│   └── StrategyOptimizer.t.sol          # ✅ Optimization tests
└── script/                              # ✅ Deployment scripts
    ├── DeployComposableRWA.s.sol        # ✅ Multi-strategy deployment
    └── DeployIndexFundVaultV2.s.sol     # ✅ Basic vault deployment
```

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- [Git](https://git-scm.com/downloads)
- [Node.js](https://nodejs.org/) (v16+) for frontend (optional)

### Installation

```shell
# Clone the repository
git clone https://github.com/yourusername/web3-index-fund.git
cd web3-index-fund

# Install dependencies
forge install

# Build contracts
forge build
```

### Testing

```shell
# Run all tests
forge test

# Run TRS-specific tests (26/26 passing)
forge test --match-contract TRSExposureStrategyTest

# Run with detailed output
forge test --match-contract TRSExposureStrategyTest -vv

# Run specific test
forge test --match-test test_AdjustExposure -vvv
```

### Local Deployment

```shell
# Start local Anvil node
anvil

# Deploy composable RWA system
forge script script/DeployComposableRWA.s.sol:DeployComposableRWA \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## 🔧 Strategy Details

### TRS Exposure Strategy (✅ IMPLEMENTED)

**Multi-Counterparty Risk Management**
- 3 mock counterparties with different credit ratings (AAA, BBB, BB)
- Concentration limits: 40% maximum per counterparty
- Dynamic quote selection based on cost and credit rating
- Real-time mark-to-market valuation and P&L tracking

**Key Features:**
- **Quote-based Trading**: Competitive bidding from multiple counterparties
- **Risk Controls**: Position limits, concentration constraints, emergency exits
- **Lifecycle Management**: Contract creation, adjustment, settlement, rollover
- **Cost Optimization**: Real-time borrowing rate comparison and selection

**Test Coverage:** 26/26 tests passing including edge cases:
- ✅ Multi-counterparty exposure distribution
- ✅ Concentration limit enforcement  
- ✅ Partial contract closing with leverage
- ✅ Reentrancy protection
- ✅ Emergency exit procedures
- ✅ Fuzz testing for robustness

### Enhanced Perpetual Strategy (✅ IMPLEMENTED)

Improved version of the original perpetual strategy with:
- IExposureStrategy interface compliance
- Better cost breakdown and funding rate tracking
- Enhanced risk management and emergency controls
- Integration with yield strategies for capital efficiency

### Direct Token Strategy (🔄 IN PROGRESS)

Next implementation phase featuring:
- Direct RWA token purchases via DEX routing
- Liquidity management and slippage protection
- Yield strategy integration for unused capital
- Cost optimization vs. other exposure methods

## 💰 Economic Model

### Multi-Strategy Cost Optimization

The system continuously optimizes between strategies based on:

1. **TRS Borrowing Rates**: Real-time rates from counterparties
2. **Perpetual Funding Rates**: Market-driven funding costs
3. **Direct Token Costs**: DEX slippage and liquidity premiums
4. **Yield Opportunities**: Available returns on unused capital

### Risk Management

- **Strategy Level**: Individual position and leverage limits
- **Bundle Level**: Cross-strategy correlation and concentration controls
- **Vault Level**: Total exposure limits and liquidity requirements
- **Emergency Controls**: Circuit breakers and emergency exit procedures

## 🔒 Security Features

### Smart Contract Security
- **Reentrancy Protection**: All state-changing functions protected
- **Access Controls**: Comprehensive ownership and permission management
- **Input Validation**: Extensive parameter validation and bounds checking
- **Emergency Systems**: Pause functionality and emergency exits

### TRS-Specific Security
- **Counterparty Diversification**: Multi-counterparty risk spreading
- **Quote Validation**: Expiration checks and authenticity verification
- **Collateral Management**: Proper calculation and posting procedures
- **Concentration Monitoring**: Real-time exposure limit enforcement

## 📊 Performance & Analytics

### Real-time Metrics
- Strategy performance attribution
- Cost breakdown analysis
- Risk exposure monitoring
- Capital efficiency tracking

### Optimization Engine
- Historical performance analysis
- Predictive cost modeling
- Risk-adjusted return optimization
- Automated rebalancing triggers

## 🗺️ Implementation Roadmap

### ✅ Phase 1: Core Infrastructure (COMPLETED)
- [x] IExposureStrategy interface
- [x] ComposableRWABundle contract
- [x] StrategyOptimizer implementation
- [x] TRS provider interface and mocks

### ✅ Phase 2: TRS Implementation (COMPLETED)
- [x] TRSExposureStrategy with multi-counterparty support
- [x] MockTRSProvider with realistic quote generation
- [x] Comprehensive test suite (26/26 tests passing)
- [x] Risk management and concentration limits

### 🔄 Phase 3: Direct Token Strategy (IN PROGRESS)
- [ ] DirectTokenStrategy implementation
- [ ] DEX integration and routing
- [ ] Liquidity management and slippage control
- [ ] Integration testing and optimization

### 📋 Phase 4: Production Ready (UPCOMING)
- [ ] Real TRS provider integrations
- [ ] Cross-chain RWA exposure
- [ ] Advanced analytics dashboard
- [ ] Institutional-grade compliance features

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow
1. Fork the repository
2. Create a feature branch
3. Implement changes with comprehensive tests
4. Run the full test suite: `forge test`
5. Submit a pull request with detailed description

### Testing Standards
- All new strategies must implement IExposureStrategy
- Minimum 90% test coverage for new contracts
- Include edge case and failure mode testing
- Gas optimization tests for public functions

## 📚 Documentation

- [Architecture Guide](ARCHITECTURE.md) - Detailed system architecture
- [Strategy Specification](COMPOSABLE_RWA_SPEC.md) - Strategy implementation details
- [API Reference](docs/api) - Contract interface documentation
- [Integration Guide](docs/integration) - How to integrate new strategies

## 🔍 Advanced Usage

### Adding Custom Strategies

```solidity
// Implement IExposureStrategy interface
contract MyCustomStrategy is IExposureStrategy {
    function getExposureInfo() external view override returns (ExposureInfo memory) {
        // Implementation
    }
    
    function openExposure(uint256 amount) external override returns (bool, uint256) {
        // Implementation
    }
    
    // ... other required functions
}

// Add to ComposableRWABundle
bundle.addExposureStrategy(
    address(myStrategy),
    2000,  // 20% target allocation
    3000,  // 30% max allocation
    false  // not primary strategy
);
```

### Custom Risk Parameters

```solidity
// Update TRS risk parameters
strategy.updateRiskParameters(IExposureStrategy.RiskParameters({
    maxLeverage: 300,           // 3x maximum leverage
    maxPositionSize: 5000000e6, // $5M maximum position
    liquidationBuffer: 1000,    // 10% liquidation buffer
    rebalanceThreshold: 500,    // 5% rebalance threshold
    slippageLimit: 200,         // 2% maximum slippage
    emergencyExitEnabled: true  // Enable emergency exits
}));
```

## 🏆 Gas Optimizations

- **Storage Packing**: Optimized variable arrangement to minimize storage slots
- **Efficient Loops**: Gas-conscious iteration patterns and early termination
- **Minimal External Calls**: Cached values and batched operations
- **Event Optimization**: Indexed parameters for efficient filtering
- **Conditional Logic**: Environment-specific optimizations for testing vs production

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenZeppelin](https://openzeppelin.com/) for security libraries
- [Foundry](https://book.getfoundry.sh/) for development framework
- [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) for vault standards

---

Built with ❤️ for the future of decentralized finance and real-world asset integration.