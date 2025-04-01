// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDEXAdapter} from "../interfaces/IDEXAdapter.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

// Uniswap V3 interfaces
interface IUniswapV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IUniswapV3QuoterV2 {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/**
 * @title UniswapV3Adapter
 * @dev Adapter for Uniswap V3 DEX
 */
contract UniswapV3Adapter is IDEXAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Uniswap V3 contracts
    IUniswapV3SwapRouter public immutable swapRouter;
    IUniswapV3QuoterV2 public immutable quoter;
    IUniswapV3Factory public immutable factory;
    
    // Fee tiers to check for liquidity (in order of preference)
    uint24[] public feeTiers;
    
    // Cache for supported pairs
    mapping(bytes32 => bool) private pairSupported;
    mapping(bytes32 => uint24) private pairFeeTier;
    
    // Events
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint24 fee);
    
    /**
     * @dev Constructor
     * @param _swapRouter The Uniswap V3 swap router address
     * @param _quoter The Uniswap V3 quoter address
     * @param _factory The Uniswap V3 factory address
     */
    constructor(
        address _swapRouter,
        address _quoter,
        address _factory
    ) Ownable(msg.sender) {
        if (_swapRouter == address(0)) revert CommonErrors.ZeroAddress();
        if (_quoter == address(0)) revert CommonErrors.ZeroAddress();
        if (_factory == address(0)) revert CommonErrors.ZeroAddress();
        
        swapRouter = IUniswapV3SwapRouter(_swapRouter);
        quoter = IUniswapV3QuoterV2(_quoter);
        factory = IUniswapV3Factory(_factory);
        
        // Initialize fee tiers (from lowest to highest)
        feeTiers = [100, 500, 3000, 10000]; // 0.01%, 0.05%, 0.3%, 1%
    }
    
    /**
     * @dev Swaps tokens using Uniswap V3
     * @param tokenIn The token to swap from
     * @param tokenOut The token to swap to
     * @param amountIn The amount of tokenIn to swap
     * @param minAmountOut The minimum amount of tokenOut to receive
     * @param recipient The address to receive the swapped tokens
     * @return amountOut The amount of tokenOut received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external override nonReentrant returns (uint256 amountOut) {
        if (tokenIn == tokenOut) revert CommonErrors.InvalidValue();
        if (amountIn == 0) revert CommonErrors.ValueTooLow();
        if (recipient == address(0)) revert CommonErrors.ZeroAddress();
        
        // Find the best fee tier for this pair
        uint24 feeTier = _getBestFeeTier(tokenIn, tokenOut);
        if (feeTier == 0) revert CommonErrors.PairNotSupported();
        
        // Transfer tokens from the sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Approve the router to spend the tokens
        IERC20(tokenIn).safeApprove(address(swapRouter), 0);
        IERC20(tokenIn).safeApprove(address(swapRouter), amountIn);
        
        // Execute the swap
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: feeTier,
            recipient: recipient,
            deadline: block.timestamp + 15 minutes,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });
        
        amountOut = swapRouter.exactInputSingle(params);
        
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut, feeTier);
        
        return amountOut;
    }
    
    /**
     * @dev Gets the expected amount of tokenOut for a given amount of tokenIn
     * @param tokenIn The token to swap from
     * @param tokenOut The token to swap to
     * @param amountIn The amount of tokenIn to swap
     * @return amountOut The expected amount of tokenOut
     */
    function getExpectedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        if (tokenIn == tokenOut) return amountIn;
        if (amountIn == 0) return 0;
        
        // Find the best fee tier for this pair
        uint24 feeTier = _getBestFeeTier(tokenIn, tokenOut);
        if (feeTier == 0) return 0;
        
        // Use the cached fee tier to get the quote
        try quoter.quoteExactInputSingle(
            tokenIn,
            tokenOut,
            feeTier,
            amountIn,
            0
        ) returns (uint256 _amountOut, uint160, uint32, uint256) {
            return _amountOut;
        } catch {
            return 0;
        }
    }
    
    /**
     * @dev Checks if Uniswap V3 supports a specific token pair
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @return supported Whether the pair is supported
     */
    function isPairSupported(
        address tokenIn,
        address tokenOut
    ) external view override returns (bool supported) {
        if (tokenIn == tokenOut) return true;
        
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        
        // Check cache first
        if (pairSupported[pairKey]) {
            return true;
        }
        
        // Check if any fee tier has liquidity
        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = factory.getPool(tokenIn, tokenOut, feeTiers[i]);
            if (pool != address(0)) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Gets the name of the DEX
     * @return name The name of the DEX
     */
    function getDexName() external pure override returns (string memory name) {
        return "Uniswap V3";
    }
    
    /**
     * @dev Gets the best fee tier for a token pair
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @return feeTier The best fee tier
     */
    function _getBestFeeTier(address tokenIn, address tokenOut) internal view returns (uint24 feeTier) {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        
        // Check cache first
        if (pairSupported[pairKey]) {
            return pairFeeTier[pairKey];
        }
        
        // Check all fee tiers and find the one with the most liquidity
        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = factory.getPool(tokenIn, tokenOut, feeTiers[i]);
            if (pool != address(0)) {
                return feeTiers[i];
            }
        }
        
        return 0;
    }
    
    /**
     * @dev Generates a unique key for a token pair
     */
    function _getPairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            tokenA < tokenB ? tokenA : tokenB,
            tokenA < tokenB ? tokenB : tokenA
        ));
    }
}
