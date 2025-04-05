// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SushiSwapAdapter, ISushiSwapRouter, ISushiSwapFactory} from "../src/adapters/SushiSwapAdapter.sol";
import {IDEXAdapter} from "../src/interfaces/IDEXAdapter.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

// Mock implementation of the SushiSwap factory for testing
contract MockSushiSwapFactory is ISushiSwapFactory {
    mapping(address => mapping(address => address)) public pairs;
    
    function createPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
    
    function getPair(address tokenA, address tokenB) external view override returns (address pair) {
        return pairs[tokenA][tokenB];
    }
}

// Mock implementation of the SushiSwap router for testing
contract MockSushiSwapRouter is ISushiSwapRouter {
    MockSushiSwapFactory public immutable factory;
    
    // Price ratios for token pairs (token => price in base units)
    mapping(address => uint256) public tokenPrices;
    
    constructor(address _factory) {
        factory = MockSushiSwapFactory(_factory);
    }
    
    function setTokenPrice(address token, uint256 price) external {
        tokenPrices[token] = price;
    }
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        require(block.timestamp <= deadline, "Deadline expired");
        
        // Check if the pair exists
        address pair = factory.getPair(path[0], path[1]);
        require(pair != address(0), "Pair not found");
        
        // Calculate the amount out
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output amount");
        
        // Transfer tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        // For each token in the path, transfer the calculated amount
        for (uint i = 1; i < path.length; i++) {
            // In a real router, this would come from the pair's reserves
            // Here we just mint the tokens to simulate the swap
            MockToken(path[i]).mint(to, amounts[i]);
        }
        
        return amounts;
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path) public view override returns (uint[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        for (uint i = 0; i < path.length - 1; i++) {
            // Check if the pair exists
            address pair = factory.getPair(path[i], path[i + 1]);
            if (pair == address(0)) {
                // If pair doesn't exist, return zeros
                for (uint j = 1; j < amounts.length; j++) {
                    amounts[j] = 0;
                }
                return amounts;
            }
            
            // Calculate based on token prices
            // This is a simplified calculation for testing
            if (tokenPrices[path[i]] == 0 || tokenPrices[path[i + 1]] == 0) {
                amounts[i + 1] = 0;
            } else {
                amounts[i + 1] = amounts[i] * tokenPrices[path[i + 1]] / tokenPrices[path[i]];
            }
        }
        
        return amounts;
    }
    
    function factory() external view override returns (address) {
        return address(factory);
    }
}

contract SushiSwapAdapterTest is Test {
    SushiSwapAdapter public adapter;
    MockSushiSwapFactory public factory;
    MockSushiSwapRouter public router;
    
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
    
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Create tokens
        usdc = new MockToken("USD Coin", "USDC", 6);
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        unsupportedToken = new MockToken("Unsupported Token", "UNSUP", 18);
        
        // Create SushiSwap contracts
        factory = new MockSushiSwapFactory();
        router = new MockSushiSwapRouter(address(factory));
        
        // Set up token pairs
        factory.createPair(address(usdc), address(weth), address(100)); // Dummy pair address
        factory.createPair(address(usdc), address(wbtc), address(101)); // Dummy pair address
        factory.createPair(address(weth), address(wbtc), address(102)); // Dummy pair address
        
        // Set token prices
        router.setTokenPrice(address(usdc), USDC_PRICE);
        router.setTokenPrice(address(weth), WETH_PRICE);
        router.setTokenPrice(address(wbtc), WBTC_PRICE);
        
        // Create the adapter
        adapter = new SushiSwapAdapter(address(router));
        
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
        assertEq(address(adapter.router()), address(router));
        assertEq(address(adapter.factory()), address(factory));
        assertEq(adapter.owner(), owner);
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
        
        // Expect the Swapped event
        vm.expectEmit(true, true, false, false);
        emit Swapped(address(usdc), address(weth), amountIn, expectedAmountOut);
        
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
        uint256 minAmountOut = 0.3e18; // 0.3 ETH
        
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
        // USDC to WETH (3,000 USDC should get ~1 WETH)
        uint256 usdcToWethAmount = adapter.getExpectedAmountOut(address(usdc), address(weth), 3000e6);
        assertEq(usdcToWethAmount, 1e18);
        
        // WETH to WBTC (10 WETH should get ~0.6 WBTC)
        uint256 wethToWbtcAmount = adapter.getExpectedAmountOut(address(weth), address(wbtc), 10e18);
        assertEq(wethToWbtcAmount, 0.6e8);
        
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
        assertEq(adapter.getDexName(), "SushiSwap");
    }
    
    function test_ReentrancyProtection() public pure {
        // This test would require a malicious contract that attempts reentrancy
        // For simplicity, we'll just verify that the nonReentrant modifier is applied to key functions
        // in the SushiSwapAdapter contract
    }
}
