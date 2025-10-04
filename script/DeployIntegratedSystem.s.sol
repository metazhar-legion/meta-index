// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IndexFundVaultV2} from "../src/IndexFundVaultV2.sol";
import {RWAAssetWrapper} from "../src/RWAAssetWrapper.sol";
import {PerpetualPositionAdapter} from "../src/adapters/PerpetualPositionAdapter.sol";
import {PerpetualPositionWrapper} from "../src/PerpetualPositionWrapper.sol";
import {StableYieldStrategy} from "../src/StableYieldStrategy.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRWASyntheticToken} from "../src/interfaces/IRWASyntheticToken.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IPerpetualTrading} from "../src/interfaces/IPerpetualTrading.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";

/**
 * @title DeployIntegratedSystem
 * @dev Script to deploy the complete integrated system with IndexFundVaultV2, RWAAssetWrapper, and PerpetualPositionAdapter
 * This script is designed to be run on a forked mainnet for testing purposes
 */
contract DeployIntegratedSystem is Script {
    // Constants
    uint256 constant BASIS_POINTS = 10000; // 100% in basis points

    // Mainnet addresses (replace with actual addresses for production)
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PRICE_ORACLE_ADDRESS = 0x0000000000000000000000000000000000000000; // Replace with actual oracle
    address constant DEX_ADDRESS = 0x0000000000000000000000000000000000000000; // Replace with actual DEX
    address constant PERP_TRADING_ADDRESS = 0x0000000000000000000000000000000000000000; // Replace with actual perp protocol

    // Market IDs for perpetual markets
    bytes32 constant SP500_MARKET_ID = keccak256("SP500");
    bytes32 constant BTC_MARKET_ID = keccak256("BTC");
    bytes32 constant ETH_MARKET_ID = keccak256("ETH");

    // Main contracts
    IndexFundVaultV2 public vault;
    RWAAssetWrapper public sp500Wrapper;
    RWAAssetWrapper public btcWrapper;
    RWAAssetWrapper public ethWrapper;
    PerpetualPositionAdapter public sp500Adapter;
    PerpetualPositionAdapter public btcAdapter;
    PerpetualPositionAdapter public ethAdapter;
    PerpetualPositionWrapper public sp500PerpWrapper;
    PerpetualPositionWrapper public btcPerpWrapper;
    PerpetualPositionWrapper public ethPerpWrapper;
    StableYieldStrategy public yieldStrategy;
    FeeManager public feeManager;

    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Get contract references
        IERC20 usdc = IERC20(USDC_ADDRESS);
        IPriceOracle priceOracle = IPriceOracle(PRICE_ORACLE_ADDRESS);
        IDEX dex = IDEX(DEX_ADDRESS);
        IPerpetualTrading perpetualTrading = IPerpetualTrading(PERP_TRADING_ADDRESS);

        // Deploy fee manager
        feeManager = new FeeManager();
        feeManager.setDepositFee(50); // 0.5% deposit fee
        feeManager.setWithdrawalFee(50); // 0.5% withdrawal fee
        feeManager.setPerformanceFee(1000); // 10% performance fee

        // Deploy yield strategy
        yieldStrategy = new StableYieldStrategy(
            usdc,
            "USDC Lending Strategy"
        );

        // Deploy vault
        vault = new IndexFundVaultV2(
            usdc,
            feeManager,
            priceOracle,
            dex
        );

        // Deploy perpetual position wrappers
        sp500PerpWrapper = new PerpetualPositionWrapper(
            usdc,
            priceOracle,
            perpetualTrading,
            SP500_MARKET_ID,
            "SPX",
            300 // 3x leverage
        );

        btcPerpWrapper = new PerpetualPositionWrapper(
            usdc,
            priceOracle,
            perpetualTrading,
            BTC_MARKET_ID,
            "BTC",
            200 // 2x leverage
        );

        ethPerpWrapper = new PerpetualPositionWrapper(
            usdc,
            priceOracle,
            perpetualTrading,
            ETH_MARKET_ID,
            "ETH",
            200 // 2x leverage
        );

        // Deploy perpetual position adapters
        sp500Adapter = new PerpetualPositionAdapter(
            address(sp500PerpWrapper),
            "S&P 500 Synthetic",
            IRWASyntheticToken.AssetType.EQUITY_INDEX
        );

        btcAdapter = new PerpetualPositionAdapter(
            address(btcPerpWrapper),
            "Bitcoin Synthetic",
            IRWASyntheticToken.AssetType.COMMODITY
        );

        ethAdapter = new PerpetualPositionAdapter(
            address(ethPerpWrapper),
            "Ethereum Synthetic",
            IRWASyntheticToken.AssetType.CRYPTO
        );

        // Deploy RWA asset wrappers
        sp500Wrapper = new RWAAssetWrapper(
            "S&P 500 Wrapper",
            usdc,
            IRWASyntheticToken(address(sp500Adapter)),
            IYieldStrategy(address(yieldStrategy)),
            priceOracle
        );

        btcWrapper = new RWAAssetWrapper(
            "Bitcoin Wrapper",
            usdc,
            IRWASyntheticToken(address(btcAdapter)),
            IYieldStrategy(address(yieldStrategy)),
            priceOracle
        );

        ethWrapper = new RWAAssetWrapper(
            "Ethereum Wrapper",
            usdc,
            IRWASyntheticToken(address(ethAdapter)),
            IYieldStrategy(address(yieldStrategy)),
            priceOracle
        );

        // Set up risk parameters for each wrapper
        sp500Wrapper.setRiskParameters(
            350, // Max leverage 3.5x
            5000, // Max position size 50%
            50,   // Slippage tolerance 0.5%
            200   // Rebalance threshold 2%
        );

        btcWrapper.setRiskParameters(
            250, // Max leverage 2.5x
            3000, // Max position size 30%
            100,  // Slippage tolerance 1%
            300   // Rebalance threshold 3%
        );

        ethWrapper.setRiskParameters(
            250, // Max leverage 2.5x
            2000, // Max position size 20%
            100,  // Slippage tolerance 1%
            300   // Rebalance threshold 3%
        );

        // Set rebalance intervals
        sp500Wrapper.setRebalanceInterval(1 days);
        btcWrapper.setRebalanceInterval(1 days);
        ethWrapper.setRebalanceInterval(1 days);

        // Set up permissions
        sp500Adapter.transferOwnership(address(sp500Wrapper));
        btcAdapter.transferOwnership(address(btcWrapper));
        ethAdapter.transferOwnership(address(ethWrapper));

        // Add asset wrappers to the vault with weights
        vault.addAsset(address(sp500Wrapper), 6000); // 60% S&P 500
        vault.addAsset(address(btcWrapper), 3000);   // 30% BTC
        vault.addAsset(address(ethWrapper), 1000);   // 10% ETH

        // Set vault parameters
        vault.setRebalanceThreshold(300); // 3% threshold for rebalancing
        vault.setRebalanceInterval(1 days); // Rebalance once per day at most

        // Transfer ownership of fee manager to vault
        feeManager.transferOwnership(address(vault));

        // Log deployed addresses
        console.log("Deployment complete!");
        console.log("Vault address:", address(vault));
        console.log("S&P 500 Wrapper address:", address(sp500Wrapper));
        console.log("BTC Wrapper address:", address(btcWrapper));
        console.log("ETH Wrapper address:", address(ethWrapper));
        console.log("S&P 500 Adapter address:", address(sp500Adapter));
        console.log("BTC Adapter address:", address(btcAdapter));
        console.log("ETH Adapter address:", address(ethAdapter));
        console.log("Yield Strategy address:", address(yieldStrategy));
        console.log("Fee Manager address:", address(feeManager));

        vm.stopBroadcast();
    }
}
