// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {ILiquidStaking} from "./interfaces/ILiquidStaking.sol";
import {CommonErrors} from "./errors/CommonErrors.sol";

/**
 * @title StakingReturnsStrategy
 * @dev A yield strategy that stakes assets in liquid staking protocols
 */
contract StakingReturnsStrategy is IYieldStrategy, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Strategy info
    StrategyInfo private strategyInfo;
    
    // Base asset (e.g., ETH or stETH)
    IERC20 public baseAsset;
    
    // Staking token (e.g., stETH)
    IERC20 public stakingToken;
    
    // Staking protocol
    address public stakingProtocol;
    
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
     * @param _baseAsset Address of the base asset
     * @param _stakingToken Address of the staking token
     * @param _stakingProtocol Address of the staking protocol
     * @param _feeRecipient Address to receive fees
     */
    constructor(
        string memory _name,
        address _baseAsset,
        address _stakingToken,
        address _stakingProtocol,
        address _feeRecipient
    ) ERC20(string(abi.encodePacked(_name, " Shares")), string(abi.encodePacked("s", _name))) Ownable(msg.sender) {
        if (_baseAsset == address(0)) revert CommonErrors.ZeroAddress();
        if (_stakingToken == address(0)) revert CommonErrors.ZeroAddress();
        if (_stakingProtocol == address(0)) revert CommonErrors.ZeroAddress();
        if (_feeRecipient == address(0)) revert CommonErrors.ZeroAddress();
        
        baseAsset = IERC20(_baseAsset);
        stakingToken = IERC20(_stakingToken);
        stakingProtocol = _stakingProtocol;
        feeRecipient = _feeRecipient;
        
        // Initialize strategy info
        strategyInfo = StrategyInfo({
            name: _name,
            asset: _baseAsset,
            totalDeposited: 0,
            currentValue: 0,
            apy: 450, // 4.5% APY initially, will be updated
            lastUpdated: block.timestamp,
            active: true,
            risk: 2 // Low risk for staking
        });
        
        // Approve staking protocol to spend base asset
        baseAsset.approve(_stakingProtocol, type(uint256).max);
    }
    
    /**
     * @dev Deposits assets into staking protocol
     * @param amount The amount to deposit
     * @return shares The number of shares received
     */
    function deposit(uint256 amount) external override nonReentrant returns (uint256 shares) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer base asset from sender to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate shares
        shares = _calculateShares(amount);
        
        // Deposit into staking protocol
        _depositToStakingProtocol(amount);
        
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
     * @dev Withdraws assets from staking protocol
     * @param shares The number of shares to withdraw
     * @return amount The amount withdrawn
     */
    function withdraw(uint256 shares) external override nonReentrant returns (uint256 amount) {
        if (shares == 0) revert CommonErrors.ValueTooLow();
        if (balanceOf(msg.sender) < shares) revert CommonErrors.InsufficientBalance();
        
        // Calculate amount
        amount = getValueOfShares(shares);
        
        // Withdraw from staking protocol
        _withdrawFromStakingProtocol(amount);
        
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
        // Value is the balance of staking tokens converted to base asset value
        uint256 stakingTokenBalance = stakingToken.balanceOf(address(this));
        
        // In a real implementation, this would call the staking protocol to get the exchange rate
        // For example:
        // return ILiquidStaking(stakingProtocol).getBaseAssetValue(stakingTokenBalance);
        
        // For now, use a simple calculation that assumes staking tokens appreciate over time
        uint256 timeElapsed = block.timestamp - strategyInfo.lastUpdated;
        uint256 annualYield = (stakingTokenBalance * strategyInfo.apy) / 10000; // APY in basis points
        uint256 accruedYield = (annualYield * timeElapsed) / 365 days;
        
        return stakingTokenBalance + accruedYield;
    }
    
    /**
     * @dev Gets the current APY of the strategy
     * @return apy The current APY in basis points
     */
    function getCurrentAPY() external view override returns (uint256 apy) {
        // In a real implementation, this would query the staking protocol for current rates
        // For example:
        // return ILiquidStaking(stakingProtocol).getCurrentAPR();
        
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
        
        // Withdraw yield from staking protocol
        _withdrawFromStakingProtocol(yield);
        
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
     * @dev Deposits to the staking protocol
     * @param amount The amount to deposit
     */
    function _depositToStakingProtocol(uint256 amount) internal {
        // In a real implementation, this would call the staking protocol's stake function
        // For example:
        // ILiquidStaking(stakingProtocol).stake(amount);
        
        // For mock implementation, just simulate the deposit by transferring tokens
        baseAsset.safeTransfer(stakingProtocol, amount);
    }
    
    /**
     * @dev Withdraws from the staking protocol
     * @param amount The amount to withdraw
     */
    function _withdrawFromStakingProtocol(uint256 amount) internal {
        // In a real implementation, this would call the staking protocol's unstake function
        // For example:
        // ILiquidStaking(stakingProtocol).unstake(amount);
        
        // For mock implementation, just simulate the withdrawal
        IERC20(stakingProtocol).safeTransfer(address(this), amount);
    }
}
