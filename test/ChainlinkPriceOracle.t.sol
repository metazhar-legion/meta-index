// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {CommonErrors} from "../src/errors/CommonErrors.sol";

// Mock Chainlink Aggregator for testing
contract MockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    
    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
    }
    
    function setPrice(int256 price) external {
        _price = price;
    }
    
    function decimals() external view override returns (uint8) {
        return _decimals;
    }
    
    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }
    
    function version() external pure override returns (uint256) {
        return 1;
    }
    
    function getRoundData(uint80)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
    
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
}

contract ChainlinkPriceOracleTest is Test {
    ChainlinkPriceOracle public oracle;
    MockERC20 public usdc;
    MockERC20 public wbtc;
    MockERC20 public weth;
    MockAggregator public btcAggregator;
    MockAggregator public ethAggregator;
    
    // Constants
    uint256 public constant BTC_PRICE = 60000 * 1e8; // $60,000 with 8 decimals
    uint256 public constant ETH_PRICE = 3000 * 1e8;  // $3,000 with 8 decimals
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        
        // Deploy mock aggregators
        btcAggregator = new MockAggregator(int256(BTC_PRICE), 8);
        ethAggregator = new MockAggregator(int256(ETH_PRICE), 8);
        
        // Deploy price oracle
        oracle = new ChainlinkPriceOracle(address(usdc));
        
        // Set price feeds
        oracle.setPriceFeed(address(wbtc), address(btcAggregator));
        oracle.setPriceFeed(address(weth), address(ethAggregator));
    }
    
    function test_GetPrice() public view {
        // Test BTC price
        uint256 btcPrice = oracle.getPrice(address(wbtc));
        assertEq(btcPrice, 60000 * 1e18); // Converted to 18 decimals
        
        // Test ETH price
        uint256 ethPrice = oracle.getPrice(address(weth));
        assertEq(ethPrice, 3000 * 1e18); // Converted to 18 decimals
        
        // Test base asset price
        uint256 usdcPrice = oracle.getPrice(address(usdc));
        assertEq(usdcPrice, 1e18); // Base asset price is always 1
    }
    
    function test_ConvertToBaseAsset() public view {
        // Test BTC to USDC conversion
        uint256 btcAmount = 1 * 1e8; // 1 BTC
        uint256 usdcAmount = oracle.convertToBaseAsset(address(wbtc), btcAmount);
        assertEq(usdcAmount, 60000 * 1e6); // 60,000 USDC
        
        // Test ETH to USDC conversion
        uint256 ethAmount = 10 * 1e18; // 10 ETH
        usdcAmount = oracle.convertToBaseAsset(address(weth), ethAmount);
        assertEq(usdcAmount, 30000 * 1e6); // 30,000 USDC
    }
    
    function test_ConvertFromBaseAsset() public view {
        // Test USDC to BTC conversion
        uint256 usdcAmount = 60000 * 1e6; // 60,000 USDC
        uint256 btcAmount = oracle.convertFromBaseAsset(address(wbtc), usdcAmount);
        assertEq(btcAmount, 1 * 1e8); // 1 BTC
        
        // Test USDC to ETH conversion
        usdcAmount = 3000 * 1e6; // 3,000 USDC
        uint256 ethAmount = oracle.convertFromBaseAsset(address(weth), usdcAmount);
        assertEq(ethAmount, 1 * 1e18); // 1 ETH
    }
    
    function test_UpdatePriceFeed() public {
        // Create a new aggregator with a different price
        MockAggregator newBtcAggregator = new MockAggregator(int256(70000 * 1e8), 8);
        
        // Update the price feed
        oracle.setPriceFeed(address(wbtc), address(newBtcAggregator));
        
        // Test the new price
        uint256 btcPrice = oracle.getPrice(address(wbtc));
        assertEq(btcPrice, 70000 * 1e18); // Converted to 18 decimals
    }
    
    function test_RevertOnInvalidPriceFeed() public {
        // Try to get price for a token without a price feed
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);
        vm.expectRevert(CommonErrors.PriceNotAvailable.selector);
        oracle.getPrice(address(randomToken));
    }
    
    function test_RevertOnNegativePrice() public {
        // Set a negative price
        btcAggregator.setPrice(-1);
        
        // Try to get the price
        vm.expectRevert(CommonErrors.PriceNotAvailable.selector);
        oracle.getPrice(address(wbtc));
    }
}
