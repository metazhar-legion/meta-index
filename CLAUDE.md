# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Smart Contracts (Foundry)
- `forge build` - Compile contracts
- `forge test` - Run all tests
- `forge test -vvv` - Run tests with verbose output
- `forge test --match-test <TEST_NAME> -vvv` - Run specific test with verbose output
- `forge coverage` - Generate test coverage report
- `anvil` - Start local Ethereum node for development
- `forge script script/DeployIndexFundVaultV2.s.sol:DeployIndexFundVaultV2 --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` - Deploy basic vault locally
- `forge script script/DeployMultiAssetVault.s.sol:DeployMultiAssetVault --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` - Deploy multi-asset vault locally

### Frontend (React/TypeScript)
- `cd frontend && npm start` - Start development server
- `cd frontend && npm run build` - Build production bundle
- `cd frontend && npm test` - Run frontend tests
- `cd frontend && npm run lint` - Run ESLint
- `cd frontend && npm run lint:fix` - Fix ESLint issues automatically

## Architecture Overview

This is a Web3 Index Fund project implementing an ERC4626-compliant vault system with Real-World Asset (RWA) support. The system uses a modular architecture with asset wrappers to manage different types of assets uniformly.

### Core Contracts

1. **IndexFundVaultV2** (`src/IndexFundVaultV2.sol`) - The main ERC4626 vault contract
   - Gas-optimized with packed storage variables
   - Handles deposits, withdrawals, and rebalancing
   - Uses asset wrappers for modular asset management

2. **RWAAssetWrapper** (`src/RWAAssetWrapper.sol`) - Wrapper for RWA tokens
   - Encapsulates RWA tokens and yield strategies
   - Provides uniform interface for different asset types

3. **Asset Management Components**:
   - `CapitalAllocationManager.sol` - Manages capital allocation across asset classes
   - `StakingReturnsStrategy.sol` - Handles staking-based yield generation
   - `StablecoinLendingStrategy.sol` - Manages stablecoin lending
   - `TokenizedTBillStrategy.sol` - Manages tokenized T-Bills

4. **Trading & Price Infrastructure**:
   - `DEXRouter.sol` - Routes trades across multiple DEXes
   - `PerpetualRouter.sol` - Manages perpetual trading positions
   - `ChainlinkPriceOracle.sol` - Price oracle integration
   - Adapters in `src/adapters/` for external protocol integration

5. **Fee Management**:
   - `FeeManager.sol` - Handles management and performance fees

### Testing Environment Considerations

The codebase uses environment-specific logic to balance test simplicity with production functionality:

- **Local Testing** (block.number ≤ 100): Simplified calculations for predictable testing
- **Production/Forked Testing** (block.number > 100): Full protocol integration

When working with contracts like `StakingReturnsStrategy`, be aware of this dual-mode behavior.

### Key Patterns

1. **Asset Wrappers**: All assets are managed through the `IAssetWrapper` interface for uniformity
2. **Gas Optimization**: Storage variables are packed to minimize storage slots
3. **Modular Design**: Clear separation between asset management, trading, and fee collection
4. **Safety**: Uses OpenZeppelin libraries with reentrancy protection

### Deployment Scripts

- `script/DeployIndexFundVaultV2.s.sol` - Basic vault deployment
- `script/DeployMultiAssetVault.s.sol` - Full multi-asset vault with RWA support
- `script/DeployBasicSetup.s.sol` - Basic setup for testing

### Frontend Architecture

React TypeScript frontend with role-based access:
- **Investor**: Deposit/withdraw assets
- **DAO Member**: Manage index composition
- **Portfolio Manager**: Rebalancing and fee collection

Uses Web3React for wallet connectivity and Material UI for components.

### Important Files to Reference

- `ARCHITECTURE.md` - Detailed system architecture
- `README.md` - Setup and usage instructions
- `PROJECT_SUMMARY.md` - High-level project overview
- `foundry.toml` - Foundry configuration with optimizer disabled for faster compilation
- Test files in `test/` for understanding contract behavior

### Common Development Tasks

When making changes to contracts:
1. Run `forge build` to ensure compilation
2. Run `forge test` to verify existing functionality
3. Add appropriate tests for new features
4. Consider gas optimization implications
5. Update documentation if architecture changes

When working with the frontend:
1. Start local development with `cd frontend && npm start`
2. Run linting with `npm run lint` before committing
3. Ensure wallet connectivity works with test contracts