// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockDEXRouter
 * @dev Mock DEX router for testing token swaps
 */
contract MockDEXRouter {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable tokenA; // Base token (e.g., USDC)
    IERC20 public immutable tokenB; // RWA token
    
    uint256 public exchangeRate = 1e18; // 1:1 ratio by default
    uint256 public slippageRate = 50; // 0.5% slippage
    bool public shouldFail = false;
    
    mapping(address => mapping(address => uint256)) public prices;
    
    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        
        // Set default prices (simplified)
        prices[_tokenA][_tokenB] = 100e18; // 1 tokenA = 100 tokenB units
        prices[_tokenB][_tokenA] = 1e16;   // 1 tokenB = 0.01 tokenA units
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut
    ) external returns (uint256 amountOut) {
        require(!shouldFail, "DEX router failure");
        require(amountIn > 0, "Invalid input amount");
        
        // Calculate output amount with slippage
        uint256 rate = prices[tokenIn][tokenOut];
        amountOut = (amountIn * rate) / 1e18;
        
        // Apply slippage
        uint256 slippage = (amountOut * slippageRate) / 10000;
        amountOut = amountOut - slippage;
        
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        
        return amountOut;
    }
    
    function getAmountsOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amountOut) {
        uint256 rate = prices[tokenIn][tokenOut];
        amountOut = (amountIn * rate) / 1e18;
        return amountOut;
    }
    
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        prices[tokenIn][tokenOut] = rate;
    }
    
    function setSlippageRate(uint256 rate) external {
        slippageRate = rate;
    }
    
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
    
    // Emergency functions for testing
    function withdrawToken(address token, uint256 amount) external {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}