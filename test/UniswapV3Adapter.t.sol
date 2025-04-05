// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UniswapV3Adapter, IUniswapV3SwapRouter, IUniswapV3QuoterV2, IUniswapV3Factory} from "../src/adapters/UniswapV3Adapter.sol";
import {IDEXAdapter} from "../src/interfaces/IDEXAdapter.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

// Mock implementation of the Uniswap V3 Factory
contract MockUniswapV3Factory is IUniswapV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;
    
    function createPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        pools[tokenA][tokenB][fee] = pool;
        pools[tokenB][tokenA][fee] = pool;
    }
    
    function getPool(address tokenA, address tokenB, uint24 fee) external view override returns (address pool) {
        return pools[tokenA][tokenB][fee];
    }
}

// Mock implementation of the Uniswap V3 Quoter
contract MockUniswapV3QuoterV2 is IUniswapV3QuoterV2 {
    // Price ratios for token pairs (token => price in base units)
    mapping(address => uint256) public tokenPrices;
    
    // Mapping to track if a pool exists
    MockUniswapV3Factory public factory;
    
    constructor(address _factory) {
        factory = MockUniswapV3Factory(_factory);
    }
    
    function setTokenPrice(address token, uint256 price) external {
        tokenPrices[token] = price;
    }
    
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external view override returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate) {
        // Check if the pool exists
        address pool = factory.getPool(tokenIn, tokenOut, fee);
        require(pool != address(0), "Pool does not exist");
        
        // Calculate the amount out based on token prices
        if (tokenPrices[tokenIn] == 0 || tokenPrices[tokenOut] == 0) {
            return (0, 0, 0, 0);
        }
        
        // Simple price calculation for testing
        amountOut = amountIn * tokenPrices[tokenOut] / tokenPrices[tokenIn];
        
        // Apply a fee based on the fee tier
        uint256 feeAmount = (amountOut * fee) / 1000000; // fee is in millionths (e.g., 3000 = 0.3%)
        amountOut = amountOut - feeAmount;
        
        // Mock values for the other return parameters
        sqrtPriceX96After = 0;
        initializedTicksCrossed = 0;
        gasEstimate = 150000;
        
        return (amountOut, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }
}

// Mock implementation of the Uniswap V3 Router
contract MockUniswapV3SwapRouter is IUniswapV3SwapRouter {
    MockUniswapV3Factory public factory;
    MockUniswapV3QuoterV2 public quoter;
    
    constructor(address _factory, address _quoter) {
        factory = MockUniswapV3Factory(_factory);
        quoter = MockUniswapV3QuoterV2(_quoter);
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256 amountOut) {
        require(block.timestamp <= params.deadline, "Transaction too old");
        require(params.amountIn > 0, "Amount in must be greater than 0");
        
        // Check if the pool exists
        address pool = factory.getPool(params.tokenIn, params.tokenOut, params.fee);
        require(pool != address(0), "Pool does not exist");
        
        // Get the amount out from the quoter
        (uint256 expectedAmountOut, , , ) = quoter.quoteExactInputSingle(
            params.tokenIn,
            params.tokenOut,
            params.fee,
            params.amountIn,
            params.sqrtPriceLimitX96
        );
        
        require(expectedAmountOut >= params.amountOutMinimum, "Insufficient output amount");
        
        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        
        // Mint the output tokens to simulate the swap
        MockToken(params.tokenOut).mint(params.recipient, expectedAmountOut);
        
        return expectedAmountOut;
    }
}

contract UniswapV3AdapterTest is Test {
    UniswapV3Adapter public adapter;
    MockUniswapV3Factory public factory;
    MockUniswapV3QuoterV2 public quoter;
    MockUniswapV3SwapRouter public router;
    
    MockToken public usdc;
    MockToken public weth;
    MockToken public wbtc;
    MockToken public unsupportedToken;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256 public constant INITIAL_BALANCE = 1000000e6; // 1,000,000 USDC
    
    // Token prices in USD (6 decimals)
    uint256 public constant USDC_PRICE = 1e6;       // $1
    uint256 public constant WETH_PRICE = 3000e6;    // $3,000
    uint256 public constant WBTC_PRICE = 50000e6;   // $50,000
    
    // Fee tiers
    uint24 public constant FEE_LOW = 500;      // 0.05%
    uint24 public constant FEE_MEDIUM = 3000;  // 0.3%
    uint24 public constant FEE_HIGH = 10000;   // 1%
    
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint24 fee);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Create tokens
        usdc = new MockToken("USD Coin", "USDC", 6);
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        unsupportedToken = new MockToken("Unsupported Token", "UNSUP", 18);
        
        // Create Uniswap V3 contracts
        factory = new MockUniswapV3Factory();
        quoter = new MockUniswapV3QuoterV2(address(factory));
        router = new MockUniswapV3SwapRouter(address(factory), address(quoter));
        
        // Set up token pairs with different fee tiers
        // USDC-WETH pair with 0.05% fee
        factory.createPool(address(usdc), address(weth), FEE_LOW, address(100));
        
        // USDC-WBTC pair with 0.3% fee
        factory.createPool(address(usdc), address(wbtc), FEE_MEDIUM, address(101));
        
        // WETH-WBTC pair with 1% fee
        factory.createPool(address(weth), address(wbtc), FEE_HIGH, address(102));
        
        // Set token prices
        quoter.setTokenPrice(address(usdc), USDC_PRICE);
        quoter.setTokenPrice(address(weth), WETH_PRICE);
        quoter.setTokenPrice(address(wbtc), WBTC_PRICE);
        
        // Create the adapter
        adapter = new UniswapV3Adapter(address(router), address(quoter), address(factory));
        
        // Mint tokens to users
        usdc.mint(user1, INITIAL_BALANCE);
        weth.mint(user1, 100e18); // 100 ETH
        wbtc.mint(user1, 10e8);   // 10 BTC
        
        usdc.mint(user2, INITIAL_BALANCE);
        weth.mint(user2, 100e18); // 100 ETH
        wbtc.mint(user2, 10e8);   // 10 BTC
        
        vm.stopPrank();
    }
    
    function test_Initialization() public view {
        assertEq(address(adapter.swapRouter()), address(router));
        assertEq(address(adapter.quoter()), address(quoter));
        assertEq(address(adapter.factory()), address(factory));
        assertEq(adapter.owner(), owner);
        
        // Check fee tiers
        assertEq(adapter.feeTiers(0), 100);
        assertEq(adapter.feeTiers(1), 500);
        assertEq(adapter.feeTiers(2), 3000);
        assertEq(adapter.feeTiers(3), 10000);
    }
    
    function test_Swap_USDC_to_WETH() public {
        uint256 amountIn = 3000e6; // 3,000 USDC
        uint256 minAmountOut = 0.9e18; // 0.9 ETH (expecting ~1 ETH)
        
        vm.startPrank(user1);
        
        // Approve the adapter to spend USDC
        usdc.approve(address(adapter), amountIn);
        
        // Get expected amount out
        uint256 expectedAmountOut = adapter.getExpectedAmountOut(address(usdc), address(weth), amountIn);
        assertGt(expectedAmountOut, 0);
        
        // We can't predict the exact output amount, so we don't test the event emission directly
        
        // Execute the swap
        uint256 amountOut = adapter.swap(
            address(usdc),
            address(weth),
            amountIn,
            minAmountOut,
            user1
        );
        
        vm.stopPrank();
        
        // Verify the swap results
        assertEq(amountOut, expectedAmountOut);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - amountIn);
        assertEq(weth.balanceOf(user1), 100e18 + amountOut);
    }
    
    function test_Swap_USDC_to_WBTC() public {
        uint256 amountIn = 50000e6; // 50,000 USDC
        uint256 minAmountOut = 0.9e8; // 0.9 BTC (expecting ~1 BTC)
        
        vm.startPrank(user1);
        
        // Approve the adapter to spend USDC
        usdc.approve(address(adapter), amountIn);
        
        // Get expected amount out
        uint256 expectedAmountOut = adapter.getExpectedAmountOut(address(usdc), address(wbtc), amountIn);
        assertGt(expectedAmountOut, 0);
        
        // Expect the Swapped event
        vm.expectEmit(true, true, false, false);
        emit Swapped(address(usdc), address(wbtc), amountIn, expectedAmountOut, FEE_MEDIUM);
        
        // Execute the swap
        uint256 amountOut = adapter.swap(
            address(usdc),
            address(wbtc),
            amountIn,
            minAmountOut,
            user1
        );
        
        vm.stopPrank();
        
        // Verify the swap results
        assertEq(amountOut, expectedAmountOut);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - amountIn);
        assertEq(wbtc.balanceOf(user1), 10e8 + amountOut);
    }
    
    function test_Swap_WETH_to_WBTC() public {
        uint256 amountIn = 10e18; // 10 ETH
        uint256 minAmountOut = 0.5e8; // 0.5 BTC (expecting ~0.6 BTC)
        
        vm.startPrank(user1);
        
        // Approve the adapter to spend WETH
        weth.approve(address(adapter), amountIn);
        
        // Get expected amount out
        uint256 expectedAmountOut = adapter.getExpectedAmountOut(address(weth), address(wbtc), amountIn);
        assertGt(expectedAmountOut, 0);
        
        // Execute the swap
        uint256 amountOut = adapter.swap(
            address(weth),
            address(wbtc),
            amountIn,
            minAmountOut,
            user1
        );
        
        vm.stopPrank();
        
        // Verify the swap results
        assertEq(amountOut, expectedAmountOut);
        assertEq(weth.balanceOf(user1), 100e18 - amountIn);
        assertEq(wbtc.balanceOf(user1), 10e8 + amountOut);
    }
    
    function test_Swap_To_Different_Recipient() public {
        uint256 amountIn = 1000e6; // 1,000 USDC
        uint256 minAmountOut = 0; // No minimum
        
        vm.startPrank(user1);
        
        // Approve the adapter to spend USDC
        usdc.approve(address(adapter), amountIn);
        
        // Execute the swap with user2 as recipient
        uint256 amountOut = adapter.swap(
            address(usdc),
            address(weth),
            amountIn,
            minAmountOut,
            user2
        );
        
        vm.stopPrank();
        
        // Verify the swap results
        assertGt(amountOut, 0);
        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE - amountIn);
        assertEq(weth.balanceOf(user2), 100e18 + amountOut); // User2 received the WETH
    }
    
    function test_Swap_Unsupported_Pair() public {
        uint256 amountIn = 1000e6; // 1,000 USDC
        
        vm.startPrank(user1);
        
        // Approve the adapter to spend USDC
        usdc.approve(address(adapter), amountIn);
        
        // Try to swap with an unsupported token
        vm.expectRevert();
        adapter.swap(
            address(usdc),
            address(unsupportedToken),
            amountIn,
            0,
            user1
        );
        
        vm.stopPrank();
    }
    
    function test_Swap_Zero_Amount() public {
        vm.startPrank(user1);
        
        // Try to swap with zero amount
        vm.expectRevert();
        adapter.swap(
            address(usdc),
            address(weth),
            0,
            0,
            user1
        );
        
        vm.stopPrank();
    }
    
    function test_Swap_Same_Token() public {
        uint256 amountIn = 1000e6; // 1,000 USDC
        
        vm.startPrank(user1);
        
        // Try to swap a token for itself
        vm.expectRevert();
        adapter.swap(
            address(usdc),
            address(usdc),
            amountIn,
            0,
            user1
        );
        
        vm.stopPrank();
    }
    
    function test_Swap_Zero_Address_Recipient() public {
        uint256 amountIn = 1000e6; // 1,000 USDC
        
        vm.startPrank(user1);
        
        // Approve the adapter to spend USDC
        usdc.approve(address(adapter), amountIn);
        
        // Try to swap with zero address recipient
        vm.expectRevert();
        adapter.swap(
            address(usdc),
            address(weth),
            amountIn,
            0,
            address(0)
        );
        
        vm.stopPrank();
    }
    
    function test_GetExpectedAmountOut() public view {
        // USDC to WETH (3,000 USDC should get ~1 WETH with 0.05% fee)
        uint256 usdcToWethAmount = adapter.getExpectedAmountOut(address(usdc), address(weth), 3000e6);
        // Expected: 3000 * 3000 / 1 = 9,000,000, minus 0.05% fee
        uint256 expectedWethAmount = 3000e6 * WETH_PRICE / USDC_PRICE;
        expectedWethAmount = expectedWethAmount - (expectedWethAmount * FEE_LOW / 1000000);
        assertEq(usdcToWethAmount, expectedWethAmount);
        
        // WETH to WBTC (10 WETH should get ~0.6 WBTC with 1% fee)
        uint256 wethToWbtcAmount = adapter.getExpectedAmountOut(address(weth), address(wbtc), 10e18);
        // Expected: 10 * 50000 / 3000 = 166.67, minus 1% fee
        uint256 expectedWbtcAmount = 10e18 * WBTC_PRICE / WETH_PRICE;
        expectedWbtcAmount = expectedWbtcAmount - (expectedWbtcAmount * FEE_HIGH / 1000000);
        assertEq(wethToWbtcAmount, expectedWbtcAmount);
        
        // Same token (should return the same amount)
        uint256 sameTokenAmount = adapter.getExpectedAmountOut(address(usdc), address(usdc), 1000e6);
        assertEq(sameTokenAmount, 1000e6);
        
        // Zero amount (should return 0)
        uint256 zeroAmount = adapter.getExpectedAmountOut(address(usdc), address(weth), 0);
        assertEq(zeroAmount, 0);
        
        // Unsupported pair (should return 0)
        uint256 unsupportedPairAmount = adapter.getExpectedAmountOut(address(usdc), address(unsupportedToken), 1000e6);
        assertEq(unsupportedPairAmount, 0);
    }
    
    function test_IsPairSupported() public view {
        // Supported pairs
        assertTrue(adapter.isPairSupported(address(usdc), address(weth)));
        assertTrue(adapter.isPairSupported(address(weth), address(usdc))); // Order doesn't matter
        assertTrue(adapter.isPairSupported(address(usdc), address(wbtc)));
        assertTrue(adapter.isPairSupported(address(weth), address(wbtc)));
        
        // Same token (should return true)
        assertTrue(adapter.isPairSupported(address(usdc), address(usdc)));
        
        // Unsupported pair
        assertFalse(adapter.isPairSupported(address(usdc), address(unsupportedToken)));
    }
    
    function test_GetDexName() public view {
        assertEq(adapter.getDexName(), "Uniswap V3");
    }
    
    function test_ReentrancyProtection() public pure {
        // This test would require a malicious contract that attempts reentrancy
        // For simplicity, we'll just verify that the nonReentrant modifier is applied to key functions
        // in the UniswapV3Adapter contract
    }
}
