// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDEXAdapter} from "../interfaces/IDEXAdapter.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

// SushiSwap interfaces
interface ISushiSwapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function factory() external view returns (address);
}

interface ISushiSwapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/**
 * @title SushiSwapAdapter
 * @dev Adapter for SushiSwap DEX
 */
contract SushiSwapAdapter is IDEXAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // SushiSwap contracts
    ISushiSwapRouter public immutable router;
    ISushiSwapFactory public immutable factory;
    
    // Cache for supported pairs
    mapping(bytes32 => bool) private pairSupported;
    
    // Events
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    
    /**
     * @dev Constructor
     * @param _router The SushiSwap router address
     */
    constructor(address _router) Ownable(msg.sender) {
        if (_router == address(0)) revert CommonErrors.ZeroAddress();
        
        router = ISushiSwapRouter(_router);
        factory = ISushiSwapFactory(router.factory());
    }
    
    /**
     * @dev Swaps tokens using SushiSwap
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
        
        // Check if the pair is supported
        if (!_isPairSupported(tokenIn, tokenOut)) revert CommonErrors.PairNotSupported();
        
        // Transfer tokens from the sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Approve the router to spend the tokens
        IERC20(tokenIn).safeApprove(address(router), 0);
        IERC20(tokenIn).safeApprove(address(router), amountIn);
        
        // Create the path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        // Execute the swap
        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            recipient,
            block.timestamp + 15 minutes
        );
        
        amountOut = amounts[amounts.length - 1];
        
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
        
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
        
        // Check if the pair is supported
        if (!_isPairSupported(tokenIn, tokenOut)) return 0;
        
        // Create the path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        // Get the expected amount out
        try router.getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            return 0;
        }
    }
    
    /**
     * @dev Checks if SushiSwap supports a specific token pair
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @return supported Whether the pair is supported
     */
    function isPairSupported(
        address tokenIn,
        address tokenOut
    ) external view override returns (bool supported) {
        return _isPairSupported(tokenIn, tokenOut);
    }
    
    /**
     * @dev Gets the name of the DEX
     * @return name The name of the DEX
     */
    function getDexName() external pure override returns (string memory name) {
        return "SushiSwap";
    }
    
    /**
     * @dev Internal function to check if a pair is supported
     */
    function _isPairSupported(address tokenIn, address tokenOut) internal view returns (bool) {
        if (tokenIn == tokenOut) return true;
        
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        
        // Check cache first
        if (pairSupported[pairKey]) {
            return true;
        }
        
        // Check if the pair exists
        address pair = factory.getPair(tokenIn, tokenOut);
        return pair != address(0);
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
