// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IDEXAdapter} from "./interfaces/IDEXAdapter.sol";
import {IDEX} from "./interfaces/IDEX.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title DEXRouter
 * @dev Routes trades to the best DEX based on available liquidity and pricing
 */
contract DEXRouter is IDEX, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Array of DEX adapters
    IDEXAdapter[] public dexAdapters;
    
    // Mapping to check if a DEX adapter is already added
    mapping(address => bool) public isAdapter;
    
    // Events
    event AdapterAdded(address indexed adapter, string name);
    event AdapterRemoved(address indexed adapter);
    event Swapped(address indexed fromToken, address indexed toToken, uint256 fromAmount, uint256 toAmount, address indexed dex);
    
    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Adds a new DEX adapter
     * @param adapter The address of the DEX adapter
     */
    function addAdapter(address adapter) external onlyOwner {
        if (adapter == address(0)) revert CommonErrors.ZeroAddress();
        if (isAdapter[adapter]) revert CommonErrors.InvalidValue();
        
        IDEXAdapter dexAdapter = IDEXAdapter(adapter);
        dexAdapters.push(dexAdapter);
        isAdapter[adapter] = true;
        
        emit AdapterAdded(adapter, dexAdapter.getDexName());
    }
    
    /**
     * @dev Removes a DEX adapter
     * @param adapter The address of the DEX adapter to remove
     */
    function removeAdapter(address adapter) external onlyOwner {
        if (!isAdapter[adapter]) revert CommonErrors.NotFound();
        
        // Find the adapter in the array
        uint256 adapterIndex = type(uint256).max;
        for (uint256 i = 0; i < dexAdapters.length; i++) {
            if (address(dexAdapters[i]) == adapter) {
                adapterIndex = i;
                break;
            }
        }
        
        if (adapterIndex == type(uint256).max) revert CommonErrors.NotFound();
        
        // Remove the adapter by swapping with the last element and popping
        dexAdapters[adapterIndex] = dexAdapters[dexAdapters.length - 1];
        dexAdapters.pop();
        isAdapter[adapter] = false;
        
        emit AdapterRemoved(adapter);
    }
    
    /**
     * @dev Gets the number of DEX adapters
     * @return count The number of adapters
     */
    function getAdapterCount() external view returns (uint256 count) {
        return dexAdapters.length;
    }
    
    /**
     * @dev Swaps tokens using the best available DEX
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param fromAmount The amount of fromToken to swap
     * @param minToAmount The minimum amount of toToken to receive
     * @return toAmount The amount of toToken received
     */
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount
    ) external override nonReentrant returns (uint256 toAmount) {
        return _swap(fromToken, toToken, fromAmount, minToAmount);
    }
    
    /**
     * @dev Swaps an exact amount of input tokens for as many output tokens as possible
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param fromAmount The exact amount of fromToken to swap
     * @param minToAmount The minimum amount of toToken to receive
     * @return toAmount The amount of toToken received
     */
    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount
    ) external override nonReentrant returns (uint256 toAmount) {
        return _swap(fromToken, toToken, fromAmount, minToAmount);
    }
    
    /**
     * @dev Gets the expected amount of toToken for a given amount of fromToken
     * @param fromToken The token to swap from
     * @param toToken The token to swap to
     * @param fromAmount The amount of fromToken to swap
     * @return toAmount The expected amount of toToken
     */
    function getExpectedAmount(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view override returns (uint256 toAmount) {
        (uint256 bestAmount, ) = _getBestQuote(fromToken, toToken, fromAmount);
        return bestAmount;
    }
    
    /**
     * @dev Internal function to handle swaps
     */
    function _swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount
    ) internal returns (uint256 toAmount) {
        if (fromToken == toToken) revert CommonErrors.InvalidValue();
        if (fromAmount == 0) revert CommonErrors.ValueTooLow();
        if (dexAdapters.length == 0) revert CommonErrors.NotInitialized();
        
        // Get the best DEX for this swap
        (uint256 expectedAmount, IDEXAdapter bestDex) = _getBestQuote(fromToken, toToken, fromAmount);
        
        if (expectedAmount < minToAmount) revert CommonErrors.SlippageTooHigh();
        if (address(bestDex) == address(0)) revert CommonErrors.NotFound();
        
        // Transfer tokens from the user to this contract
        IERC20(fromToken).safeTransferFrom(msg.sender, address(this), fromAmount);
        
        // Approve the DEX to spend the tokens
        IERC20(fromToken).safeApprove(address(bestDex), 0);
        IERC20(fromToken).safeApprove(address(bestDex), fromAmount);
        
        // Execute the swap
        toAmount = bestDex.swap(fromToken, toToken, fromAmount, minToAmount, msg.sender);
        
        emit Swapped(fromToken, toToken, fromAmount, toAmount, address(bestDex));
        
        return toAmount;
    }
    
    /**
     * @dev Gets the best quote from all available DEXes
     * @return bestAmount The best amount out
     * @return bestDex The DEX offering the best rate
     */
    function _getBestQuote(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) internal view returns (uint256 bestAmount, IDEXAdapter bestDex) {
        bestAmount = 0;
        
        for (uint256 i = 0; i < dexAdapters.length; i++) {
            IDEXAdapter dex = dexAdapters[i];
            
            // Check if this DEX supports the token pair
            if (!dex.isPairSupported(fromToken, toToken)) {
                continue;
            }
            
            try dex.getExpectedAmountOut(fromToken, toToken, fromAmount) returns (uint256 amount) {
                if (amount > bestAmount) {
                    bestAmount = amount;
                    bestDex = dex;
                }
            } catch {
                // Skip this DEX if there's an error
                continue;
            }
        }
        
        return (bestAmount, bestDex);
    }
}
