pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";

/**
 * @title StableYieldStrategy
 * @dev A yield strategy that invests in stable yield protocols (e.g., Aave, Compound)
 */
contract StableYieldStrategy is IYieldStrategy, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Strategy info
    StrategyInfo private strategyInfo;
    
    // Base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // Yield protocol
    address public yieldProtocol;
    
    // Yield token (e.g., aUSDC, cUSDC)
    IERC20 public yieldToken;
    
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
     * @param _yieldProtocol Address of the yield protocol
     * @param _yieldToken Address of the yield token
     * @param _feeRecipient Address to receive fees
     */
    constructor(
        string memory _name,
        address _baseAsset,
        address _yieldProtocol,
        address _yieldToken,
        address _feeRecipient
    ) ERC20(string(abi.encodePacked(_name, " Shares")), string(abi.encodePacked("s", _name))) Ownable(msg.sender) {
        require(_baseAsset != address(0), "Invalid base asset address");
        require(_yieldProtocol != address(0), "Invalid yield protocol address");
        require(_yieldToken != address(0), "Invalid yield token address");
        require(_feeRecipient != address(0), "Invalid fee recipient address");
        
        baseAsset = IERC20(_baseAsset);
        yieldProtocol = _yieldProtocol;
        yieldToken = IERC20(_yieldToken);
        feeRecipient = _feeRecipient;
        
        // Initialize strategy info
        strategyInfo = StrategyInfo({
            name: _name,
            asset: _baseAsset,
            totalDeposited: 0,
            currentValue: 0,
            apy: 0,
            lastUpdated: block.timestamp,
            active: true,
            risk: 2 // Low risk for stable yield
        });
    }
    
    /**
     * @dev Deposits assets into the yield strategy
     * @param amount The amount to deposit
     * @return shares The number of shares received
     */
    function deposit(uint256 amount) external override nonReentrant returns (uint256 shares) {
        require(amount > 0, "Amount must be positive");
        
        // Transfer base asset from sender to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate shares
        shares = _calculateShares(amount);
        
        // Deposit into yield protocol
        _depositToYieldProtocol(amount);
        
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
     * @dev Withdraws assets from the yield strategy
     * @param shares The number of shares to withdraw
     * @return amount The amount withdrawn
     */
    function withdraw(uint256 shares) external override nonReentrant returns (uint256 amount) {
        require(shares > 0, "Shares must be positive");
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");
        
        // Calculate amount
        amount = getValueOfShares(shares);
        
        // Withdraw from yield protocol
        _withdrawFromYieldProtocol(amount);
        
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
        // Value is the balance of yield tokens converted to base asset value
        uint256 yieldTokenBalance = yieldToken.balanceOf(address(this));
        
        // In a real implementation, this would call the yield protocol to get the exchange rate
        // For simplicity, we'll assume 1:1 exchange rate plus some yield
        uint256 baseAssetBalance = baseAsset.balanceOf(address(this));
        
        // Simulate yield by adding 5% annual yield prorated by time since last update
        uint256 timeElapsed = block.timestamp - strategyInfo.lastUpdated;
        uint256 annualYield = (strategyInfo.totalDeposited * 500) / 10000; // 5% annual yield
        uint256 accruedYield = (annualYield * timeElapsed) / (365 days);
        
        return baseAssetBalance + yieldTokenBalance + accruedYield;
    }
    
    /**
     * @dev Gets the current APY of the strategy
     * @return apy The current APY in basis points
     */
    function getCurrentAPY() external view override returns (uint256 apy) {
        // In a real implementation, this would call the yield protocol to get the current APY
        // For simplicity, we'll return a fixed APY
        return 500; // 5% APY
    }
    
    /**
     * @dev Gets detailed information about the strategy
     * @return info The strategy information
     */
    function getStrategyInfo() external view override returns (StrategyInfo memory info) {
        // Update current value
        StrategyInfo memory updatedInfo = strategyInfo;
        updatedInfo.currentValue = getTotalValue();
        updatedInfo.apy = this.getCurrentAPY();
        
        return updatedInfo;
    }
    
    /**
     * @dev Harvests yield from the strategy
     * @return harvested The amount harvested
     */
    function harvestYield() external override onlyOwner nonReentrant returns (uint256 harvested) {
        uint256 currentValue = getTotalValue();
        uint256 totalDeposited = strategyInfo.totalDeposited;
        
        // Calculate yield
        if (currentValue <= totalDeposited) return 0;
        
        uint256 yield = currentValue - totalDeposited;
        
        // Calculate fee
        uint256 fee = (yield * feePercentage) / 10000;
        uint256 netYield = yield - fee;
        
        // Withdraw yield from protocol
        _withdrawFromYieldProtocol(yield);
        
        // Transfer fee to fee recipient
        if (fee > 0) {
            baseAsset.safeTransfer(feeRecipient, fee);
        }
        
        // Update strategy info
        strategyInfo.currentValue = getTotalValue();
        strategyInfo.lastUpdated = block.timestamp;
        
        emit YieldHarvested(yield, fee);
        return netYield;
    }
    
    /**
     * @dev Sets the fee percentage
     * @param _feePercentage New fee percentage in basis points
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 1000, "Fee too high"); // Max 10%
        feePercentage = _feePercentage;
        
        emit FeePercentageUpdated(_feePercentage);
    }
    
    /**
     * @dev Sets the fee recipient
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient address");
        feeRecipient = _feeRecipient;
        
        emit FeeRecipientUpdated(_feeRecipient);
    }
    
    /**
     * @dev Calculates the number of shares to mint for a given deposit amount
     * @param amount The deposit amount
     * @return shares The number of shares
     */
    function _calculateShares(uint256 amount) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return amount; // 1:1 for first deposit
        
        uint256 totalValue = getTotalValue();
        return (amount * totalShares) / totalValue;
    }
    
    /**
     * @dev Deposits assets into the yield protocol
     * @param amount The amount to deposit
     */
    function _depositToYieldProtocol(uint256 amount) internal {
        // In a real implementation, this would call the yield protocol's deposit function
        // For example, for Aave:
        // aavePool.deposit(address(baseAsset), amount, address(this), 0);
        
        // For simplicity, we'll just simulate the deposit by transferring to the yield protocol
        baseAsset.approve(yieldProtocol, amount);
        
        // This is a placeholder for the actual deposit call
        // In a real implementation, you would replace this with the actual deposit call
        // For example:
        // (bool success, ) = yieldProtocol.call(
        //     abi.encodeWithSignature("deposit(address,uint256,address,uint16)", address(baseAsset), amount, address(this), 0)
        // );
        // require(success, "Deposit failed");
    }
    
    /**
     * @dev Withdraws assets from the yield protocol
     * @param amount The amount to withdraw
     */
    function _withdrawFromYieldProtocol(uint256 amount) internal {
        // In a real implementation, this would call the yield protocol's withdraw function
        // For example, for Aave:
        // aavePool.withdraw(address(baseAsset), amount, address(this));
        
        // For simplicity, we'll just simulate the withdrawal
        // This is a placeholder for the actual withdrawal call
        // In a real implementation, you would replace this with the actual withdrawal call
        // For example:
        // (bool success, ) = yieldProtocol.call(
        //     abi.encodeWithSignature("withdraw(address,uint256,address)", address(baseAsset), amount, address(this))
        // );
        // require(success, "Withdrawal failed");
    }
}
