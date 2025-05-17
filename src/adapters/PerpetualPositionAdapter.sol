// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PerpetualPositionWrapper} from "../PerpetualPositionWrapper.sol";
import {IRWASyntheticToken} from "../interfaces/IRWASyntheticToken.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {CommonErrors} from "../errors/CommonErrors.sol";

/**
 * @title PerpetualPositionAdapter
 * @dev Adapter that wraps a PerpetualPositionWrapper and implements the IRWASyntheticToken interface
 * This allows the PerpetualPositionWrapper to be used with the RWAAssetWrapper
 */
contract PerpetualPositionAdapter is IRWASyntheticToken, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // The underlying perpetual position wrapper
    PerpetualPositionWrapper public perpWrapper;
    
    // The base asset (e.g., USDC)
    IERC20 public baseAsset;
    
    // The price oracle
    IPriceOracle public priceOracle;
    
    // Asset information
    AssetInfo private assetInfo;
    
    // Total supply of synthetic tokens
    uint256 private _totalSupply;
    
    // Balances of synthetic tokens
    mapping(address => uint256) private _balances;
    
    // Allowances for synthetic tokens
    mapping(address => mapping(address => uint256)) private _allowances;
    
    /**
     * @dev Constructor
     * @param _perpWrapper The perpetual position wrapper
     * @param _assetName The name of the asset
     * @param _assetType The type of the asset
     */
    constructor(
        address _perpWrapper,
        string memory _assetName,
        AssetType _assetType
    ) Ownable(msg.sender) {
        if (_perpWrapper == address(0)) revert CommonErrors.ZeroAddress();
        
        perpWrapper = PerpetualPositionWrapper(_perpWrapper);
        baseAsset = IERC20(perpWrapper.baseAsset());
        priceOracle = IPriceOracle(perpWrapper.priceOracle());
        
        // Initialize asset info
        assetInfo = AssetInfo({
            name: _assetName,
            symbol: perpWrapper.assetSymbol(),
            assetType: _assetType,
            oracle: address(priceOracle),
            lastPrice: 0,
            lastUpdated: 0,
            marketId: perpWrapper.marketId(),
            isActive: true
        });
        
        // Update price
        updatePrice();
    }
    
    /**
     * @dev Gets information about the synthetic asset
     * @return info The asset information
     */
    function getAssetInfo() external view override returns (AssetInfo memory info) {
        return assetInfo;
    }
    
    /**
     * @dev Gets the current price of the asset in USD
     * @return price The current price (scaled by 10^18)
     */
    function getCurrentPrice() external view override returns (uint256 price) {
        return assetInfo.lastPrice;
    }
    
    /**
     * @dev Updates the asset price from the oracle
     * @return success Whether the update was successful
     */
    function updatePrice() public override returns (bool success) {
        // Get the current position value from the perpetual wrapper
        uint256 positionValue = perpWrapper.getPositionValue();
        
        // Update asset info
        assetInfo.lastPrice = positionValue > 0 ? positionValue : getCurrentPriceFromOracle();
        assetInfo.lastUpdated = block.timestamp;
        
        return true;
    }
    
    /**
     * @dev Gets the current price from the oracle
     * @return price The current price (scaled by 10^18)
     */
    function getCurrentPriceFromOracle() internal view returns (uint256 price) {
        // Get the base token address from the perpetual wrapper
        address baseToken = address(perpWrapper.baseAsset());
        
        // Get the price from the oracle
        return priceOracle.getPrice(baseToken);
    }
    
    /**
     * @dev Mints synthetic tokens
     * @param to The address to mint tokens to
     * @param amount The amount to mint
     * @return success Whether the mint was successful
     */
    function mint(address to, uint256 amount) external override onlyOwner returns (bool success) {
        if (to == address(0)) revert CommonErrors.ZeroAddress();
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer base asset from sender to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve and open position in the perpetual wrapper
        baseAsset.approve(address(perpWrapper), amount);
        perpWrapper.openPosition(amount);
        
        // Mint synthetic tokens
        _mint(to, amount);
        
        return true;
    }
    
    /**
     * @dev Burns synthetic tokens
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     * @return success Whether the burn was successful
     */
    function burn(address from, uint256 amount) external override onlyOwner returns (bool success) {
        if (from == address(0)) revert CommonErrors.ZeroAddress();
        if (amount == 0) revert CommonErrors.ValueTooLow();
        if (_balances[from] < amount) revert CommonErrors.InsufficientBalance();
        
        // Burn synthetic tokens
        _burn(from, amount);
        
        // Close position in the perpetual wrapper
        perpWrapper.closePosition();
        
        // Transfer base asset back to the owner
        uint256 balance = baseAsset.balanceOf(address(this));
        if (balance > 0) {
            baseAsset.safeTransfer(owner(), balance);
        }
        
        return true;
    }
    
    /**
     * @dev Internal function to mint tokens
     * @param to The address to mint tokens to
     * @param amount The amount to mint
     */
    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    /**
     * @dev Internal function to burn tokens
     * @param from The address to burn tokens from
     * @param amount The amount to burn
     */
    function _burn(address from, uint256 amount) internal {
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
    
    // ERC20 interface implementations
    
    /**
     * @dev Returns the name of the token
     */
    function name() external view returns (string memory) {
        return assetInfo.name;
    }
    
    /**
     * @dev Returns the symbol of the token
     */
    function symbol() external view returns (string memory) {
        return assetInfo.symbol;
    }
    
    /**
     * @dev Returns the decimals of the token
     */
    function decimals() external pure returns (uint8) {
        return 18;
    }
    
    /**
     * @dev Returns the total supply of the token
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @dev Returns the balance of the specified address
     * @param account The address to query the balance of
     */
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @dev Returns the allowance of the spender for the owner
     * @param owner The address that owns the tokens
     * @param spender The address that can spend the tokens
     */
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    /**
     * @dev Approves the spender to spend tokens on behalf of the sender
     * @param spender The address that can spend the tokens
     * @param amount The amount of tokens to approve
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @dev Transfers tokens from the sender to the recipient
     * @param recipient The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        if (recipient == address(0)) revert CommonErrors.ZeroAddress();
        if (_balances[msg.sender] < amount) revert CommonErrors.InsufficientBalance();
        
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }
    
    /**
     * @dev Transfers tokens from the sender to the recipient using an allowance
     * @param sender The address to transfer tokens from
     * @param recipient The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if (sender == address(0) || recipient == address(0)) revert CommonErrors.ZeroAddress();
        if (_balances[sender] < amount) revert CommonErrors.InsufficientBalance();
        if (_allowances[sender][msg.sender] < amount) revert CommonErrors.InsufficientAllowance();
        
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        _allowances[sender][msg.sender] -= amount;
        
        emit Transfer(sender, recipient, amount);
        return true;
    }
    
    /**
     * @dev Adjusts the position size
     * @param additionalCollateral Additional collateral to add to the position
     * @return success Whether the adjustment was successful
     */
    function adjustPositionSize(uint256 additionalCollateral) external onlyOwner nonReentrant returns (bool success) {
        if (additionalCollateral == 0) revert CommonErrors.ValueTooLow();
        
        // Transfer additional collateral from sender to this contract
        baseAsset.safeTransferFrom(msg.sender, address(this), additionalCollateral);
        
        // Approve and adjust position in the perpetual wrapper
        baseAsset.approve(address(perpWrapper), additionalCollateral);
        perpWrapper.adjustPosition(additionalCollateral);
        
        // Update price after adjustment
        updatePrice();
        
        return true;
    }
    
    /**
     * @dev Changes the leverage of the position
     * @param newLeverage New leverage value
     * @return success Whether the leverage change was successful
     */
    function changeLeverage(uint256 newLeverage) external onlyOwner nonReentrant returns (bool success) {
        if (newLeverage == 0) revert CommonErrors.ValueTooLow();
        
        // Change leverage in the perpetual wrapper
        perpWrapper.changeLeverage(newLeverage);
        
        // Update price after leverage change
        updatePrice();
        
        return true;
    }
    
    /**
     * @dev Withdraws base asset from the adapter
     * @param amount Amount to withdraw
     * @return success Whether the withdrawal was successful
     */
    function withdrawBaseAsset(uint256 amount) external onlyOwner nonReentrant returns (bool success) {
        if (amount == 0) revert CommonErrors.ValueTooLow();
        
        // Withdraw from the perpetual wrapper
        perpWrapper.withdrawBaseAsset(amount);
        
        // Transfer base asset to the owner
        uint256 balance = baseAsset.balanceOf(address(this));
        if (balance >= amount) {
            baseAsset.safeTransfer(owner(), amount);
        } else if (balance > 0) {
            baseAsset.safeTransfer(owner(), balance);
        } else {
            revert CommonErrors.InsufficientBalance();
        }
        
        // Update price after withdrawal
        updatePrice();
        
        return true;
    }
    
    /**
     * @dev Emergency function to recover tokens sent to this contract
     * @param token The token to recover
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
}
