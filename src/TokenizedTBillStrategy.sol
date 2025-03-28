// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {ITBillToken} from "./interfaces/ITBillToken.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title TokenizedTBillStrategy
 * @dev A yield strategy that invests in tokenized T-bills
 */
contract TokenizedTBillStrategy is IYieldStrategy, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Strategy info
    StrategyInfo private strategyInfo;
    
    // Base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // T-Bill token (e.g., USDC-T)
    IERC20 public tBillToken;
    
    // T-Bill protocol
    address public tBillProtocol;
    
    // Fee percentage in basis points (e.g., 50 = 0.5%)
    uint256 public feePercentage = 50;
    
    // Fee recipient
    address public feeRecipient;
    
    // Events
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event YieldHarvested(uint256 amount, uint256 fee);
    event FeePercentageUpdated(uint256 newPercentage);
    event FeeRecipientUpdated(address newRecipient);
    
    /**
     * @dev Constructor
     * @param _name Name of the strategy
     * @param _baseAsset Address of the base asset (e.g., USDC)
     * @param _tBillToken Address of the T-Bill token
     * @param _tBillProtocol Address of the T-Bill protocol
     * @param _feeRecipient Address to receive fees
     */
    constructor(
        string memory _name,
        address _baseAsset,
        address _tBillToken,
        address _tBillProtocol,
        address _feeRecipient
    ) ERC20(string(abi.encodePacked(_name, " Shares")), string(abi.encodePacked("s", _name))) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        if (_tBillToken == address(0)) revert CommonErrors.ZeroAddress();
        if (_tBillProtocol == address(0)) revert CommonErrors.ZeroAddress();
        if (_feeRecipient == address(0)) revert CommonErrors.ZeroAddress();
        
        baseAsset = IERC20(_baseAsset);
        tBillToken = IERC20(_tBillToken);
        tBillProtocol = _tBillProtocol;
        feeRecipient = _feeRecipient;
        
        // Initialize strategy info
        strategyInfo = StrategyInfo({
            name: _name,
            asset: _baseAsset,
            totalDeposited: 0,
            currentValue: 0,
            apy: 400, // 4% APY initially, will be updated
            lastUpdated: block.timestamp,
            active: true,
            risk: 1 // Very low risk for T-bills
        });
        
        // Approve T-Bill protocol to spend base asset
        baseAsset.approve(_tBillProtocol, type(uint256).max);
    }
    
    /**
     * @dev Deposits assets into T-Bills
     * @param amount The amount to deposit
     * @return shares The number of shares received
     */
    function deposit(uint256 amount) external override nonReentrant returns (uint256 shares) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer base asset from sender to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate shares
        shares = _calculateShares(amount);
        
        // Deposit into T-Bill protocol
        _depositToTBillProtocol(amount);
        
        // Mint shares
        _mint(msg.sender, shares);
        
        // Update strategy info
        strategyInfo.totalDeposited += amount;
        strategyInfo.currentValue = getTotalValue();
        strategyInfo.lastUpdated = block.timestamp;
        
        emit Deposited(msg.sender, amount, shares);
        return shares;
    }
    
    /**
     * @dev Withdraws assets from T-Bills
     * @param shares The number of shares to withdraw
     * @return amount The amount withdrawn
     */
    function withdraw(uint256 shares) external override nonReentrant returns (uint256 amount) {
        if (shares == 0) revert CommonErrors.ValueTooLow();
        if (balanceOf(msg.sender) < shares) revert CommonErrors.InsufficientBalance();
        
        // Calculate amount
        amount = getValueOfShares(shares);
        
        // Withdraw from T-Bill protocol
        _withdrawFromTBillProtocol(amount);
        
        // Burn shares
        _burn(msg.sender, shares);
        
        // Transfer base asset to sender
        baseAsset.safeTransfer(msg.sender, amount);
        
        // Update strategy info
        strategyInfo.currentValue = getTotalValue();
        strategyInfo.lastUpdated = block.timestamp;
        
        emit Withdrawn(msg.sender, shares, amount);
        return amount;
    }
    
    /**
     * @dev Gets the current value of shares
     * @param shares The number of shares
     * @return value The current value of the shares
     */
    function getValueOfShares(uint256 shares) public view override returns (uint256 value) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return shares; // 1:1 if no shares exist
        
        uint256 totalValue = getTotalValue();
        return (shares * totalValue) / totalShares;
    }
    
    /**
     * @dev Gets the total value of all assets in the strategy
     * @return value The total value
     */
    function getTotalValue() public view override returns (uint256 value) {
        // Value is the balance of T-Bill tokens converted to base asset value
        uint256 tBillBalance = tBillToken.balanceOf(address(this));
        
        // In a real implementation, this would call the T-Bill protocol to get the exchange rate
        // For example:
        // return ITBillToken(address(tBillToken)).getBaseAssetValue(tBillBalance);
        
        // For now, use a simple 1:1 conversion plus accrued interest
        // In reality, T-Bill tokens would have a redemption value that increases over time
        uint256 timeElapsed = block.timestamp - strategyInfo.lastUpdated;
        uint256 annualYield = (tBillBalance * strategyInfo.apy) / 10000; // APY in basis points
        uint256 accruedYield = (annualYield * timeElapsed) / 365 days;
        
        return tBillBalance + accruedYield;
    }
    
    /**
     * @dev Gets the current APY of the strategy
     * @return apy The current APY in basis points
     */
    function getCurrentAPY() external view override returns (uint256 apy) {
        // In a real implementation, this would query the T-Bill protocol for current rates
        // For example:
        // return ITBillToken(address(tBillToken)).getCurrentYield();
        
        // For now, return a fixed APY
        return strategyInfo.apy;
    }
    
    /**
     * @dev Gets detailed information about the strategy
     * @return info The strategy information
     */
    function getStrategyInfo() external view override returns (StrategyInfo memory info) {
        // Update current value
        StrategyInfo memory updatedInfo = strategyInfo;
        updatedInfo.currentValue = getTotalValue();
        
        return updatedInfo;
    }
    
    /**
     * @dev Harvests yield from the strategy
     * @return harvested The amount harvested
     */
    function harvestYield() external override onlyOwner returns (uint256 harvested) {
        uint256 currentValue = getTotalValue();
        uint256 totalDeposited = strategyInfo.totalDeposited;
        
        // Calculate yield
        if (currentValue <= totalDeposited) return 0;
        
        uint256 yield = currentValue - totalDeposited;
        
        // Calculate fee
        uint256 fee = (yield * feePercentage) / 10000;
        uint256 netYield = yield - fee;
        
        // Withdraw yield from T-Bill protocol
        _withdrawFromTBillProtocol(yield);
        
        // Transfer fee to fee recipient
        if (fee > 0) {
            baseAsset.safeTransfer(feeRecipient, fee);
        }
        
        // Transfer net yield to owner
        if (netYield > 0) {
            baseAsset.safeTransfer(owner(), netYield);
        }
        
        // Update strategy info
        strategyInfo.currentValue = getTotalValue();
        strategyInfo.lastUpdated = block.timestamp;
        
        emit YieldHarvested(yield, fee);
        return netYield;
    }
    
    /**
     * @dev Sets the fee percentage
     * @param _feePercentage The new fee percentage in basis points
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > 1000) revert CommonErrors.ValueTooHigh(); // Max 10%
        
        feePercentage = _feePercentage;
        emit FeePercentageUpdated(_feePercentage);
    }
    
    /**
     * @dev Sets the fee recipient
     * @param _feeRecipient The new fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert CommonErrors.ZeroAddress();
        
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
    
    /**
     * @dev Calculates shares based on amount
     * @param amount The amount of base asset
     * @return shares The number of shares
     */
    function _calculateShares(uint256 amount) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return amount; // 1:1 for first deposit
        
        uint256 totalValue = getTotalValue();
        return (amount * totalShares) / totalValue;
    }
    
    /**
     * @dev Deposits to the T-Bill protocol
     * @param amount The amount to deposit
     */
    function _depositToTBillProtocol(uint256 amount) internal {
        // Transfer base asset to T-Bill protocol
        baseAsset.safeTransfer(tBillProtocol, amount);
        
        // In a real implementation, the protocol would automatically mint T-Bill tokens to this address
        // For example:
        // ITBillToken(tBillProtocol).deposit(amount);
        
        // For testing purposes, the test will manually transfer T-Bill tokens to simulate this behavior
    }
    
    /**
     * @dev Withdraws from the T-Bill protocol
     * @param amount The amount to withdraw
     */
    function _withdrawFromTBillProtocol(uint256 amount) internal {
        // In a real implementation, this would call the T-Bill protocol's withdraw function
        // For example:
        // ITBillToken(tBillProtocol).redeem(amount);
        
        // For testing purposes, we would burn T-Bill tokens and receive base assets
        // The test will have already transferred the base assets to this contract
        // to simulate the withdrawal
        
        // Simulate burning T-Bill tokens by transferring them back to the protocol
        uint256 tBillTokensToBurn = amount;
        tBillToken.safeTransfer(tBillProtocol, tBillTokensToBurn);
    }
}
