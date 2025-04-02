// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {DEXRouter} from "../src/DEXRouter.sol";
import {IDEXAdapter} from "../src/interfaces/IDEXAdapter.sol";
import {IDEX} from "../src/interfaces/IDEX.sol";
import {MockDEX} from "../src/mocks/MockDEX.sol";
// Import MockToken directly

/**
 * @title MockToken for testing
 */
contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";

/**
 * @title MockDEXAdapter
 * @dev Mock implementation of the IDEXAdapter interface for testing
 */
contract MockDEXAdapter is IDEXAdapter {
    string public dexName;
    mapping(bytes32 => bool) public supportedPairs;
    mapping(bytes32 => uint256) public exchangeRates;
    uint256 public fee;

    constructor(string memory _dexName, uint256 _fee) {
        dexName = _dexName;
        fee = _fee;
    }

    function setPairSupported(address tokenIn, address tokenOut, bool supported) external {
        bytes32 pairKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        supportedPairs[pairKey] = supported;
    }

    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        bytes32 pairKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        exchangeRates[pairKey] = rate;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external override returns (uint256 amountOut) {
        bytes32 pairKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        require(supportedPairs[pairKey], "Pair not supported");

        uint256 rate = exchangeRates[pairKey];
        amountOut = (amountIn * rate * (10000 - fee)) / 10000 / 1e18;
        require(amountOut >= minAmountOut, "Slippage too high");

        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        ERC20(tokenOut).transfer(recipient, amountOut);

        return amountOut;
    }

    function getExpectedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        bytes32 pairKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        if (!supportedPairs[pairKey]) return 0;

        uint256 rate = exchangeRates[pairKey];
        return (amountIn * rate * (10000 - fee)) / 10000 / 1e18;
    }

    function isPairSupported(
        address tokenIn,
        address tokenOut
    ) external view override returns (bool supported) {
        bytes32 pairKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        return supportedPairs[pairKey];
    }

    function getDexName() external view override returns (string memory name) {
        return dexName;
    }
}

contract DEXRouterTest is Test {
    DEXRouter public router;
    MockDEXAdapter public adapter1;
    MockDEXAdapter public adapter2;
    MockToken public tokenA;
    MockToken public tokenB;
    address public user;

    function setUp() public {
        // Create tokens
        tokenA = new MockToken("Token A", "TKNA", 18);
        tokenB = new MockToken("Token B", "TKNB", 18);

        // Create DEX router
        router = new DEXRouter();

        // Create mock adapters with different fees
        adapter1 = new MockDEXAdapter("DEX 1", 30); // 0.3% fee
        adapter2 = new MockDEXAdapter("DEX 2", 20); // 0.2% fee

        // Setup exchange rates
        // 1 TokenA = 2 TokenB on DEX 1
        adapter1.setExchangeRate(address(tokenA), address(tokenB), 2 * 1e18);
        // 1 TokenA = 1.9 TokenB on DEX 2
        adapter2.setExchangeRate(address(tokenA), address(tokenB), 1.9 * 1e18);

        // Setup supported pairs
        adapter1.setPairSupported(address(tokenA), address(tokenB), true);
        adapter2.setPairSupported(address(tokenA), address(tokenB), true);

        // Add adapters to router
        router.addAdapter(address(adapter1));
        router.addAdapter(address(adapter2));

        // Setup user
        user = address(0x1);
        vm.startPrank(user);
        
        // Mint tokens to user
        tokenA.mint(user, 100000 * 1e18);
        tokenB.mint(user, 100000 * 1e18);
        
        // Also mint tokens to the mock DEXes for liquidity
        tokenA.mint(address(adapter1), 100000 * 1e18);
        tokenB.mint(address(adapter1), 100000 * 1e18);
        tokenA.mint(address(adapter2), 100000 * 1e18);
        tokenB.mint(address(adapter2), 100000 * 1e18);
        
        // Approve router to spend tokens
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        
        vm.stopPrank();
    }

    function testAddAdapter() public {
        assertEq(router.getAdapterCount(), 2);
        
        // Create a new adapter
        MockDEXAdapter adapter3 = new MockDEXAdapter("DEX 3", 25);
        
        // Add it to the router
        vm.prank(router.owner());
        router.addAdapter(address(adapter3));
        
        assertEq(router.getAdapterCount(), 3);
        assertTrue(router.isAdapter(address(adapter3)));
    }

    function testRemoveAdapter() public {
        assertEq(router.getAdapterCount(), 2);
        
        // Remove an adapter
        vm.prank(router.owner());
        router.removeAdapter(address(adapter1));
        
        assertEq(router.getAdapterCount(), 1);
        assertFalse(router.isAdapter(address(adapter1)));
        assertTrue(router.isAdapter(address(adapter2)));
    }

    function testGetExpectedAmount() public view {
        // Should route to DEX 1 since it has better rate despite higher fee
        uint256 amountIn = 10 * 1e18;
        uint256 expectedAmount = router.getExpectedAmount(address(tokenA), address(tokenB), amountIn);
        
        // Calculate expected amount from DEX 1
        uint256 dex1Amount = adapter1.getExpectedAmountOut(address(tokenA), address(tokenB), amountIn);
        
        assertEq(expectedAmount, dex1Amount);
    }

    function testSwap() public {
        uint256 amountIn = 10 * 1e18;
        uint256 minAmountOut = 19 * 1e18; // Slightly less than expected to account for fees
        
        uint256 userABalanceBefore = tokenA.balanceOf(user);
        uint256 userBBalanceBefore = tokenB.balanceOf(user);
        
        vm.prank(user);
        uint256 amountOut = router.swap(address(tokenA), address(tokenB), amountIn, minAmountOut);
        
        uint256 userABalanceAfter = tokenA.balanceOf(user);
        uint256 userBBalanceAfter = tokenB.balanceOf(user);
        
        // Check balances
        assertEq(userABalanceBefore - userABalanceAfter, amountIn);
        assertEq(userBBalanceAfter - userBBalanceBefore, amountOut);
        
        // Should be routed to DEX 1 (better rate)
        uint256 dex1Amount = adapter1.getExpectedAmountOut(address(tokenA), address(tokenB), amountIn);
        assertEq(amountOut, dex1Amount);
    }

    function testSwapWithSlippage() public {
        uint256 amountIn = 10 * 1e18;
        uint256 minAmountOut = 20 * 1e18; // Higher than expected, should fail
        
        vm.prank(user);
        vm.expectRevert(); // Should revert due to slippage
        router.swap(address(tokenA), address(tokenB), amountIn, minAmountOut);
    }

    function testSwapWithBestDEX() public {
        // Change the exchange rate on DEX 2 to make it better than DEX 1
        adapter2.setExchangeRate(address(tokenA), address(tokenB), 2.1 * 1e18);
        
        uint256 amountIn = 10 * 1e18;
        uint256 minAmountOut = 20 * 1e18;
        
        vm.prank(user);
        uint256 amountOut = router.swap(address(tokenA), address(tokenB), amountIn, minAmountOut);
        
        // Should be routed to DEX 2 now (better rate)
        uint256 dex2Amount = adapter2.getExpectedAmountOut(address(tokenA), address(tokenB), amountIn);
        assertEq(amountOut, dex2Amount);
    }

    function testSwapWithUnsupportedPair() public {
        // Create a new token
        MockToken tokenC = new MockToken("Token C", "TKNC", 18);
        
        uint256 amountIn = 10 * 1e18;
        uint256 minAmountOut = 1;
        
        vm.prank(user);
        vm.expectRevert(); // Should revert as no DEX supports this pair
        router.swap(address(tokenA), address(tokenC), amountIn, minAmountOut);
    }
}
